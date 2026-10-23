import base64
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import py7zr

import garmin_ci as ci


class GarminCiTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cache = self.root / "cache"
        self.device = self.cache / "Devices" / "testwatch"
        self.device.mkdir(parents=True)
        (self.cache / "Fonts").mkdir()
        (self.device / "compiler.json").write_text(json.dumps(
            {"partNumbers": [{"number": "006-B0001-00"}, {"number": "006-B0002-00"}]}))
        (self.device / "simulator.json").write_text(json.dumps({"fonts": [{"fonts": [
            {"filename": "required"},
            {"filename": "vector", "type": "ttf"},
            {"filename": "system", "type": "system_ttf"},
            {"filename": "bitstreamVeraSans 16"},
        ]}]}))
        (self.device / "testwatch.bin").write_bytes(b"device")
        for name in ("required.cft", "required.md5", "vector.ttf", "system.ttf", "unused.ttf"):
            (self.cache / "Fonts" / name).write_bytes(b"font")

    def iq(self, parts=("006-B0001-00", "006-B0002-00"), signature=True, extra=False):
        folder = self.root / "iq"
        folder.mkdir()
        nodes = "".join(
            f'<iq:product partNumber="{part}" filename="{part}/test.prg" '
            f'sig2="{"A" * 1024 if signature else ""}" sigFormat="rsa-4096"/>'
            for part in parts)
        (folder / "manifest.xml").write_text(
            f'<iq:manifest xmlns:iq="{ci.NS["iq"]}"><iq:products>{nodes}</iq:products></iq:manifest>')
        for name in ("manifest.sig2", "dev_key.pub"):
            (folder / name).write_bytes(b"synthetic signing material")
        for part in parts:
            (folder / part).mkdir()
            (folder / part / "test.prg").write_bytes(b"signed-program" * 3)
            (folder / part / "debug.xml").write_bytes(b"<debug/>")
        if extra:
            (folder / "unexpected.txt").write_bytes(b"extra")
        output = self.root / "test.iq"
        with py7zr.SevenZipFile(output, "w") as archive:
            for path in folder.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(folder).as_posix())
        return output

    def test_selects_only_referenced_fonts(self):
        names = {path.name for path in ci.selected_cache_files(self.cache, ["testwatch"])}
        self.assertTrue({"required.cft", "required.md5", "vector.ttf", "system.ttf"} <= names)
        self.assertNotIn("unused.ttf", names)

    def test_missing_font_fails(self):
        (self.cache / "Fonts" / "vector.ttf").unlink()
        with self.assertRaisesRegex(ValueError, "Missing referenced font"):
            ci.selected_cache_files(self.cache, ["testwatch"])

    def test_missing_device_fails(self):
        with self.assertRaisesRegex(ValueError, "Missing device file"):
            ci.selected_cache_files(self.cache, ["missingwatch"])

    def test_archive_is_deterministic_and_no_overwrite(self):
        one, two = self.root / "one.zip", self.root / "two.zip"
        with patch.object(ci, "products", return_value=["testwatch"]):
            ci.package_cache(self.cache, one)
            ci.package_cache(self.cache, two)
            self.assertEqual(ci.digest(one), ci.digest(two))
            with self.assertRaisesRegex(ValueError, "overwrite"):
                ci.package_cache(self.cache, one)
        with zipfile.ZipFile(one) as archive:
            self.assertTrue(all(name.startswith(("Devices/testwatch/", "Fonts/"))
                                for name in archive.namelist()))

    def test_unsafe_archive_fails(self):
        path = self.root / "unsafe.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("../escape", b"bad")
        with self.assertRaisesRegex(ValueError, "Unsafe archive"):
            ci.extract_zip(path, self.root / "output")

    def test_unconfigured_pin_never_downloads(self):
        with patch.dict(os.environ, {"GARMIN_DEVICE_PACKAGE_SHA256": "PENDING"}), \
                patch.object(ci, "download") as download:
            with self.assertRaisesRegex(ValueError, "approval"):
                ci.provision(self.root / "provision")
            download.assert_not_called()

    def test_authenticated_redirect_fails(self):
        with self.assertRaisesRegex(ValueError, "redirects"):
            ci.NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.com")

    def test_valid_export_covers_all_hardware_variants(self):
        self.assertEqual(ci.validate_iq(self.iq(), ["testwatch"], self.cache), 2)

    def test_incomplete_export_fails(self):
        with self.assertRaisesRegex(ValueError, "hardware variants"):
            ci.validate_iq(self.iq(parts=("006-B0001-00",)), ["testwatch"], self.cache)

    def test_unsigned_export_fails(self):
        with self.assertRaisesRegex(ValueError, "signed IQ"):
            ci.validate_iq(self.iq(signature=False), ["testwatch"], self.cache)

    def test_extra_export_files_fail(self):
        with self.assertRaisesRegex(ValueError, "Unexpected IQ"):
            ci.validate_iq(self.iq(extra=True), ["testwatch"], self.cache)

    def test_renamed_prg_is_not_iq(self):
        path = self.root / "fake.iq"
        path.write_bytes(b"not an archive")
        with self.assertRaises(py7zr.Bad7zFile):
            ci.validate_iq(path, ["testwatch"], self.cache)

    def test_localization(self):
        ci.validate_localization()

    def build_environment(self):
        (self.root / "source").mkdir(exist_ok=True)
        (self.root / "source" / "StandaloneApp.mc").write_text('const APP_VERSION = "5.8.3";')
        return {
            "GITLAB_CI": "true", "CI_PROJECT_ID": "6783",
            "CI_PROJECT_URL": "https://git.tak.gov/core/weartak-core/weartak-garmin",
            "CI_COMMIT_REF_PROTECTED": "true", "CI_COMMIT_SHA": "a" * 40,
            "CI_PIPELINE_ID": "1234", "CI_PIPELINE_IID": "42", "CI_JOB_ID": "456",
            "GARMIN_DEVELOPER_KEY_B64": base64.b64encode(b"disposable test data").decode(),
            "GARMIN_DEVELOPER_KEY_SHA256": hashlib.sha256(b"disposable test data").hexdigest(),
        }

    def test_signing_fingerprint_mismatch_never_compiles(self):
        environment = self.build_environment()
        environment["GARMIN_DEVELOPER_KEY_SHA256"] = "0" * 64
        with patch.dict(os.environ, environment), patch.object(ci, "ROOT", self.root), \
                patch.object(ci, "validate_localization"), \
                patch.object(ci.subprocess, "check_output", return_value="a" * 40), \
                patch.object(ci.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "signing key SHA256"):
                ci.build(self.root / "sdk", self.root / "home", self.root / "output")
            self.assertEqual(run.call_count, 1)  # Only git diff, never Java.
        self.assertFalse((self.root / "output" / "release-build.json").exists())

    def test_build_uses_export_semantics_and_truthful_iid_provenance(self):
        environment = self.build_environment()
        commands = []
        def execute(command, **kwargs):
            commands.append(command)
            if command[0] == "java":
                Path(command[command.index("-o") + 1]).write_bytes(b"synthetic validated IQ")
        output = self.root / "output"
        with patch.dict(os.environ, environment), patch.object(ci, "ROOT", self.root), \
                patch.object(ci, "validate_localization"), \
                patch.object(ci, "products", return_value=["testwatch"]), \
                patch.object(ci, "validate_iq", return_value=2), \
                patch.object(ci.subprocess, "check_output", return_value="a" * 40), \
                patch.object(ci.subprocess, "run", side_effect=execute):
            ci.build(self.root / "sdk", self.root / "home", output)
        java = commands[-1]
        self.assertIn("-e", java)
        self.assertIn("-Djava.awt.headless=true", java)
        self.assertFalse(Path(java[java.index("-y") + 1]).exists())
        record = json.loads((output / "release-build.json").read_text())
        self.assertEqual(record["pipeline_iid"], "42")
        self.assertEqual(record["pipeline_id"], "1234")
        self.assertEqual(record["tests"], "not-run-headless-linux")
        self.assertEqual(record["hardware_variants"], 2)
        self.assertEqual(record["artifacts"][0]["name"], "WearTAK-Garmin-5.8.3-p42.iq")

    def test_unprotected_build_never_reads_key(self):
        with patch.dict(os.environ, {"GITLAB_CI": "false"}):
            with self.assertRaisesRegex(ValueError, "protected canonical"):
                ci.build(self.root / "sdk", self.root / "home", self.root / "output")


if __name__ == "__main__":
    unittest.main()
