[CmdletBinding()]
param(
    [ValidateSet("CI", "Release")]
    [string]$Mode = "CI",
    [string]$SdkPath = $env:CONNECTIQ_SDK,
    [string]$TestDevice = "fenix7x",
    [string[]]$TestNames = @(),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) "bin\ci"),
    [int]$TestTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$simulator = $null
$testProcess = $null
$temporary = $null

function Invoke-Compiler([string[]]$CompilerArguments) {
    $ErrorActionPreference = "Continue"
    & (Join-Path $SdkPath "bin\monkeyc.bat") @CompilerArguments 2>&1 |
        Tee-Object -FilePath (Join-Path $OutputDirectory "build.log") -Append | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "Monkey C compilation failed ($LASTEXITCODE)." }
}

try {
    if (-not $SdkPath -or -not (Test-Path (Join-Path $SdkPath "bin\monkeyc.bat"))) {
        throw "Set CONNECTIQ_SDK to the installed Windows Connect IQ SDK directory."
    }
    $SdkPath = (Resolve-Path $SdkPath).Path
    [void](Get-Command java -ErrorAction Stop)
    New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
    $OutputDirectory = (Resolve-Path $OutputDirectory).Path
    if (Get-ChildItem -LiteralPath $OutputDirectory -Force) {
        throw "Output directory must be empty to prevent publishing stale artifacts: $OutputDirectory"
    }
    & (Join-Path $PSScriptRoot "Validate-Localization.ps1") -ProjectRoot $root
    if (-not $?) { throw "Localization validation failed." }

    $temporary = Join-Path ([IO.Path]::GetTempPath()) ("weartak-ci-" + [guid]::NewGuid())
    New-Item -ItemType Directory $temporary | Out-Null
    $acl = Get-Acl $temporary
    $acl.SetAccessRuleProtection($true, $false)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $identity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"))
    Set-Acl -LiteralPath $temporary -AclObject $acl
    $key = Join-Path $temporary "developer_key.der"
    $packages = Join-Path $temporary "packages"
    New-Item -ItemType Directory $packages | Out-Null
    if ($Mode -eq "Release") {
        if (-not $env:GARMIN_DEVELOPER_KEY_B64 -or -not $env:GARMIN_DEVELOPER_KEY_SHA256) {
            throw "Signed builds require GARMIN_DEVELOPER_KEY_B64 and GARMIN_DEVELOPER_KEY_SHA256."
        }
        [IO.File]::WriteAllBytes($key, [Convert]::FromBase64String($env:GARMIN_DEVELOPER_KEY_B64))
        $expected = $env:GARMIN_DEVELOPER_KEY_SHA256.Trim().ToUpperInvariant()
        if ($expected -notmatch '^[0-9A-F]{64}$' -or (Get-FileHash $key -Algorithm SHA256).Hash -ne $expected) {
            throw "Garmin signing key does not match the configured SHA-256 fingerprint."
        }
    } else {
        $openssl = Get-Command openssl -ErrorAction SilentlyContinue
        $opensslPath = if ($openssl) { $openssl.Source } else { "C:\Program Files\Git\usr\bin\openssl.exe" }
        if (-not (Test-Path $opensslPath)) { throw "OpenSSL is required to generate a disposable CI signing key." }
        $pem = Join-Path $temporary "temporary.pem"
        & $opensslPath genrsa -out $pem 4096
        if ($LASTEXITCODE -ne 0) { throw "Unable to generate disposable CI key." }
        & $opensslPath pkcs8 -topk8 -inform PEM -outform DER -in $pem -out $key -nocrypt
        if ($LASTEXITCODE -ne 0) { throw "Unable to encode disposable CI key." }
    }

    $jungle = Join-Path $root "monkey.jungle"
    $program = Join-Path $OutputDirectory "tests.prg"
    Invoke-Compiler @("-f", $jungle, "-d", $TestDevice, "-t", "-o", $program, "-y", $key)
    if (Get-Process -Name simulator -ErrorAction SilentlyContinue) {
        throw "Use a dedicated runner with no existing Garmin simulator session."
    }
    $simulator = Start-Process (Join-Path $SdkPath "bin\simulator.exe") -PassThru
    Start-Sleep -Seconds 5
    if ($simulator.HasExited) { throw "Garmin simulator exited before tests started." }
    $arguments = @("-classpath", (Join-Path $SdkPath "bin\monkeybrains.jar"),
        "com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux",
        "-f", $program, "-d", $TestDevice, "-s", (Join-Path $SdkPath "bin\shell.exe"), "-t") + $TestNames
    if ($arguments | Where-Object { $_ -match '["\r\n]' }) { throw "Invalid simulator argument." }
    $quoted = ($arguments | ForEach-Object { '"' + $_ + '"' }) -join " "
    $testLog = Join-Path $OutputDirectory "tests.log"
    $testProcess = Start-Process java -ArgumentList $quoted -PassThru -NoNewWindow `
        -RedirectStandardOutput $testLog -RedirectStandardError (Join-Path $OutputDirectory "tests-error.log")
    $null = $testProcess.Handle
    if (-not $testProcess.WaitForExit($TestTimeoutSeconds * 1000)) { throw "Garmin tests timed out." }
    $testProcess.WaitForExit()
    Get-Content $testLog | Write-Host
    $result = Get-Content -Raw $testLog
    $summary = [regex]::Match($result, '(?m)^PASSED \(passed=([1-9][0-9]*), failed=0, errors=0\)\s*\z')
    $ran = [regex]::Match($result, '(?m)^Ran ([1-9][0-9]*) tests\s*$')
    # SDK 9.2's Java launcher misparses its simulator's passing summary and exits 1.
    # Require an exact, complete zero-failure summary instead of trusting that exit code alone.
    if ($testProcess.ExitCode -notin @(0, 1) -or -not $summary.Success -or -not $ran.Success -or
        $summary.Groups[1].Value -ne $ran.Groups[1].Value -or
        $result -match '(?m)^FAILED\b' -or
        (Get-Item (Join-Path $OutputDirectory "tests-error.log")).Length -gt 0) {
        throw "Garmin simulator tests failed (exit '$($testProcess.ExitCode)') or produced no successful result. See tests.log and tests-error.log."
    }
    if ($testProcess.ExitCode -eq 1) {
        Write-Warning "SDK launcher returned 1 despite a verified passing summary ($($ran.Groups[1].Value) tests)."
    }
    if ($Mode -eq "Release") {
        [xml]$manifest = Get-Content -Raw (Join-Path $root "manifest.xml")
        foreach ($product in $manifest.manifest.application.products.product) {
            Invoke-Compiler @("-f", $jungle, "-d", $product.id, "-r", "-O", "3z",
                "-o", (Join-Path $packages ("WearTAK-Garmin-" + $product.id + ".prg")), "-y", $key)
        }
    }
    Invoke-Compiler @("-f", $jungle, "-r", "-O", "3z",
        "-o", (Join-Path $packages "WearTAK-Garmin.iq"), "-y", $key)
    Get-ChildItem $packages -File | Where-Object { $_.Extension -in ".prg", ".iq" } |
        Copy-Item -Destination $OutputDirectory
    Get-ChildItem $OutputDirectory -Filter "WearTAK-Garmin*" -File |
        Where-Object { $_.Extension -in ".prg", ".iq" } |
        Get-FileHash -Algorithm SHA256 |
        ForEach-Object { "$($_.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_.Path))" } |
        Set-Content (Join-Path $OutputDirectory "SHA256SUMS.txt") -Encoding ASCII
} finally {
    if ($testProcess -and -not $testProcess.HasExited) { Stop-Process -Id $testProcess.Id -Force }
    if ($simulator -and -not $simulator.HasExited) { Stop-Process -Id $simulator.Id -Force }
    if ($temporary) {
        foreach ($name in @("developer_key.der", "temporary.pem")) {
            $file = Join-Path $temporary $name
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        }
        $packages = Join-Path $temporary "packages"
        if (Test-Path -LiteralPath $packages) {
            [IO.Directory]::Delete($packages, $true)
        }
        [IO.Directory]::Delete($temporary)
    }
}
