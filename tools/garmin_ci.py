"""Headless Connect IQ provisioning, export, and local device-cache packaging."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

import py7zr
from py7zr.io import BytesIOFactory

ROOT = Path(__file__).resolve().parent.parent
SDK_NAME = "connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2.zip"
SDK_SHA256 = "4907d8455b651c5a00a865e364cc4f1921c055b9279c7c8634c7a7a6773b5593"
SDK_BASE = "https://developer.garmin.com/downloads/connect-iq/sdks/"
NS = {"iq": "http://www.garmin.com/xml/connectiq"}


def digest(path):
    with Path(path).open("rb") as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
        return result.hexdigest()


def products(manifest=ROOT / "manifest.xml"):
    result = [node.attrib["id"] for node in
              ET.parse(manifest).findall(".//iq:product", NS)]
    if not result or len(set(result)) != len(result) or any(
            not re.fullmatch("[a-z0-9]+", item) for item in result):
        raise ValueError("Invalid manifest product set")
    return result


def selected_cache_files(cache, device_ids):
    """Include only manifest devices and the fonts referenced by their definitions."""
    files = set()
    for device in device_ids:
        directory = cache / "Devices" / device
        for required in ("compiler.json", "simulator.json", f"{device}.bin"):
            if not (directory / required).is_file():
                raise ValueError(f"Missing device file: {device}/{required}")
        files.update(path for path in directory.rglob("*") if path.is_file())
        definition = json.loads((directory / "simulator.json").read_text("utf-8"))
        for font_set in definition["fonts"]:
            for font in font_set["fonts"]:
                stem = font["filename"]
                # Garmin's legacy Thai definitions use the simulator's built-in fonts.
                if re.fullmatch(r"bitstreamVeraSans (16|21|27)", stem):
                    continue
                if not re.fullmatch(r"[A-Za-z0-9_.-]+", stem):
                    raise ValueError(f"Unsafe font reference: {stem}")
                suffix = ".ttf" if font.get("type") in ("ttf", "system_ttf") else ".cft"
                path = cache / "Fonts" / (stem + suffix)
                if not path.is_file():
                    raise ValueError(f"Missing referenced font: {path.name}")
                files.add(path)
                if path.with_suffix(".md5").is_file():
                    files.add(path.with_suffix(".md5"))
    for path in files:
        if path.is_symlink() or not path.resolve().is_relative_to(cache.resolve()):
            raise ValueError(f"Unsafe cache file: {path}")
    return sorted(files)


def package_cache(cache, output):
    if output.exists():
        raise ValueError("Refusing to overwrite an existing cache archive")
    files = selected_cache_files(cache, products())
    with zipfile.ZipFile(output, "x", zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            info = zipfile.ZipInfo(path.relative_to(cache).as_posix())
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())
    print(json.dumps({"sha256": digest(output), "files": len(files),
                      "bytes": output.stat().st_size,
                      "font_files": sum(path.parent.name == "Fonts" for path in files)}))


def extract_zip(path, destination):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate archive entries")
        for entry in archive.infolist():
            name = PurePosixPath(entry.filename)
            if (name.is_absolute() or ".." in name.parts or "\\" in entry.filename
                    or ":" in entry.filename
                    or (entry.external_attr >> 16) & 0o170000 == 0o120000):
                raise ValueError(f"Unsafe archive entry: {entry.filename}")
        archive.extractall(destination)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Authenticated package redirects are not permitted")


def download(url, destination, expected, token=None):
    if not re.fullmatch("[0-9a-f]{64}", expected) or expected == "0" * 64:
        raise ValueError("Unconfigured SHA256 pin; package storage approval is required")
    request = urllib.request.Request(url, headers={"JOB-TOKEN": token} if token else {})
    opener = urllib.request.build_opener(NoRedirect()) if token else urllib.request.build_opener()
    with opener.open(request, timeout=120) as response, destination.open("xb") as stream:
        for block in iter(lambda: response.read(1024 * 1024), b""):
            stream.write(block)
    if digest(destination) != expected:
        raise ValueError("Download SHA256 mismatch")


def provision(destination):
    pin = os.environ["GARMIN_DEVICE_PACKAGE_SHA256"]
    if not re.fullmatch("[0-9a-f]{64}", pin) or pin == "0" * 64:
        raise ValueError("Device package pin pending private-storage approval; no downloads attempted")
    if destination.exists():
        raise ValueError("Provisioning directory must not exist")
    destination.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="garmin-download-") as temporary:
        temporary = Path(temporary)
        sdk_zip = temporary / "sdk.zip"
        download(SDK_BASE + SDK_NAME, sdk_zip, SDK_SHA256)
        extract_zip(sdk_zip, destination / "sdk")
        cache_zip = temporary / "devices.zip"
        download("https://git.tak.gov/api/v4/projects/6783/packages/generic/"
                 "garmin-device-cache/9.2.0-1/devices-fonts.zip",
                 cache_zip, pin, os.environ["CI_JOB_TOKEN"])
        cache = destination / "home" / ".Garmin" / "ConnectIQ"
        extract_zip(cache_zip, cache)
        expected = {path.relative_to(cache).as_posix()
                    for path in selected_cache_files(cache, products())}
        actual = {path.relative_to(cache).as_posix()
                  for path in cache.rglob("*") if path.is_file()}
        if expected != actual:
            raise ValueError("Device package contains files outside the selected device/font set")


def validate_iq(path, device_ids, cache):
    expected_parts = set()
    for device in device_ids:
        definition = json.loads((cache / "Devices" / device / "compiler.json").read_text("utf-8"))
        expected_parts.update(part["number"] for part in definition["partNumbers"])
    with py7zr.SevenZipFile(path, "r") as archive:
        names = archive.getnames()
        prgs = [name for name in names if name.endswith(".prg")]
        if len(names) != len(set(names)) or not {"manifest.xml", "manifest.sig2", "dev_key.pub"} <= set(names):
            raise ValueError("Invalid IQ export inventory")
        for name in names:
            if (PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts
                    or "\\" in name or ":" in name):
                raise ValueError("Unsafe IQ export entry")
        if any(item.is_directory or item.is_symlink for item in archive.files):
            raise ValueError("IQ export must contain only regular files")
        entries_info = archive.list()
        if any(item.uncompressed > 64 * 1024 * 1024 for item in entries_info):
            raise ValueError("Oversized IQ export member")
        if sum(item.uncompressed for item in entries_info) > 512 * 1024 * 1024:
            raise ValueError("Oversized IQ export")
        # Garmin omits some 7z file timestamps; in-memory extraction avoids
        # py7zr's filesystem timestamp handling while still checking archive CRCs.
        factory = BytesIOFactory(limit=64 * 1024 * 1024)
        archive.extractall(factory=factory)
        def content(name):
            stream = factory.get(name)
            stream.seek(0)
            return stream.read()
        exported = ET.fromstring(content("manifest.xml"))
        entries = exported.findall(".//iq:product", NS)
        parts = [entry.attrib["partNumber"] for entry in entries]
        filenames = [entry.attrib["filename"] for entry in entries]
        if (len(parts) != len(set(parts)) or set(parts) != expected_parts
                or len(prgs) != len(parts) or sorted(prgs) != sorted(filenames)):
            raise ValueError("IQ export does not cover exactly the manifest hardware variants")
        wanted = {"manifest.xml", "manifest.sig2", "dev_key.pub"} | set(filenames)
        wanted.update(f"{part}/debug.xml" for part in parts)
        if set(names) != wanted:
            raise ValueError("Unexpected IQ export files")
        for entry in entries:
            filename = entry.attrib["filename"]
            if (PurePosixPath(filename).parent.as_posix() != entry.attrib["partNumber"]
                    or len(content(filename)) < 16
                    or entry.attrib.get("sigFormat") != "rsa-4096"
                    or not re.fullmatch("[0-9A-Fa-f]{1024}", entry.attrib.get("sig2", ""))):
                raise ValueError("Missing signed IQ program")
        if any(not content(name) for name in ("manifest.sig2", "dev_key.pub")):
            raise ValueError("Missing IQ signing material")
    return len(expected_parts)


def validate_localization():
    def keys(path):
        return {node.attrib["id"] for node in ET.parse(path).getroot().findall("string")}
    expected = keys(ROOT / "resources" / "resources.xml")
    for directory in ROOT.glob("resources-*"):
        if directory.is_dir() and keys(directory / "resources.xml") != expected:
            raise ValueError(f"Localization key mismatch: {directory.name}")


def build(sdk, home, output):
    env = os.environ
    if (env.get("GITLAB_CI") != "true" or env.get("CI_PROJECT_ID") != "6783"
            or env.get("CI_PROJECT_URL") != "https://git.tak.gov/core/weartak-core/weartak-garmin"
            or env.get("CI_COMMIT_REF_PROTECTED") != "true"):
        raise ValueError("Signed export requires protected canonical GitLab CI")
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if sha != env["CI_COMMIT_SHA"]:
        raise ValueError("Build checkout SHA mismatch")
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--"], cwd=ROOT, check=True)
    validate_localization()
    if output.exists() and any(output.iterdir()):
        raise ValueError("Output directory must be empty")
    output.mkdir(parents=True, exist_ok=True)
    version = re.search(r'const APP_VERSION = "([^"]+)";',
                        (ROOT / "source" / "StandaloneApp.mc").read_text("utf-8")).group(1)
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9a-f]+)?", version):
        raise ValueError("Invalid APP_VERSION")
    for key in ("CI_PIPELINE_ID", "CI_PIPELINE_IID", "CI_JOB_ID"):
        if not re.fullmatch("[1-9][0-9]*", env[key]):
            raise ValueError(f"Invalid {key}")
    name = f"WearTAK-Garmin-{version}-p{env['CI_PIPELINE_IID']}.iq"
    with tempfile.TemporaryDirectory(prefix="garmin-sign-") as temporary:
        key = Path(temporary) / "developer_key.der"
        key.write_bytes(base64.b64decode(env["GARMIN_DEVELOPER_KEY_B64"], validate=True))
        key.chmod(0o600)
        fingerprint = env["GARMIN_DEVELOPER_KEY_SHA256"].strip().lower()
        if not re.fullmatch("[0-9a-f]{64}", fingerprint) or digest(key) != fingerprint:
            raise ValueError("Production signing key SHA256 mismatch")
        command = ["java", "-Xms1g", "-Dfile.encoding=UTF-8",
                   f"-Duser.home={home}", "-Djava.awt.headless=true",
                   "-cp", str(sdk / "bin" / "monkeybrains.jar"),
                   "com.garmin.monkeybrains.Monkeybrains",
                   "-f", str(ROOT / "monkey.jungle"), "-e", "-r", "-O", "3z",
                   "-o", str(output / name), "-y", str(key)]
        with (output / "build.log").open("w", encoding="utf-8") as log:
            try:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
            except subprocess.CalledProcessError:
                log.flush()
                print((output / "build.log").read_text("utf-8"))
                raise
    variants = validate_iq(output / name, products(), home / ".Garmin" / "ConnectIQ")
    (output / "SHA256SUMS.txt").write_text(f"{digest(output / name)}  {name}\n", encoding="ascii")
    record = dict(schema=2, signing="production-key-fingerprint-verified",
                  tests="not-run-headless-linux", sdk="9.2.0", export="monkeyc-e",
                  products=products(), hardware_variants=variants, source_sha=sha, project_id=env["CI_PROJECT_ID"],
                  pipeline_id=env["CI_PIPELINE_ID"], pipeline_iid=env["CI_PIPELINE_IID"],
                  build_job_id=env["CI_JOB_ID"], version=version,
                  artifacts=[dict(name=n, sha256=digest(output / n))
                             for n in (name, "SHA256SUMS.txt")])
    (output / "release-build.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"Exported {name}; simulator tests NOT RUN (interactive desktop required).")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    package = commands.add_parser("package")
    package.add_argument("--cache", type=Path, required=True)
    package.add_argument("--output", type=Path, required=True)
    setup = commands.add_parser("provision")
    setup.add_argument("--destination", type=Path, required=True)
    release = commands.add_parser("build")
    release.add_argument("--sdk", type=Path, required=True)
    release.add_argument("--home", type=Path, required=True)
    release.add_argument("--output", type=Path, default=ROOT / "bin" / "ci")
    args = parser.parse_args()
    if args.command == "package":
        package_cache(args.cache.resolve(), args.output.resolve())
    elif args.command == "provision":
        provision(args.destination.resolve())
    else:
        build(args.sdk.resolve(), args.home.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
