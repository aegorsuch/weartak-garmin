$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot "GarminRelease.psm1") -Force
$directory = Join-Path ([IO.Path]::GetTempPath()) ("garmin-publisher-test-" + [guid]::NewGuid())
$script:checks = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:checks++
}
function Reject([scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert ($null -ne $message -and $message -match $Pattern) "Expected rejection matching '$Pattern'; got '$message'"
}
try {
    New-Item -ItemType Directory $directory | Out-Null
    $context = @{
        Enabled = "true"; Protected = "true"; Source = "push"; Branch = "main"; DefaultBranch = "main"
        ProjectId = "6783"; PipelineId = "123"; JobId = "789"; Sha = ("a" * 40)
        ProjectUrl = "https://git.tak.gov/core/weartak-core/weartak-garmin"; ApiUrl = "https://git.tak.gov/api/v4"
    }
    $products = @("fenix7x", "fenix847mm")
    foreach ($name in @("WearTAK-Garmin-fenix7x.prg", "WearTAK-Garmin-fenix847mm.prg", "WearTAK-Garmin.iq")) {
        Set-Content (Join-Path $directory $name) "Synthetic test data: $name" -Encoding ASCII
    }
    Get-ChildItem $directory -File | Get-FileHash -Algorithm SHA256 |
        ForEach-Object { "$($_.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($_.Path))" } |
        Set-Content (Join-Path $directory "SHA256SUMS.txt") -Encoding ASCII
    $metadata = @{
        schema = 1; signing = "production-key-fingerprint-verified"; tests = "full-suite-passed"
        source_sha = $context.Sha; project_id = "6783"; pipeline_id = "123"; build_job_id = "456"
        version = "5.8.3-9f1ec78"
        artifacts = @(Get-ChildItem $directory -File | ForEach-Object {
            @{name = $_.Name; sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
        })
    }
    $metadataPath = Join-Path $directory "release-build.json"
    function Save-Metadata { $metadata | ConvertTo-Json -Depth 6 | Set-Content $metadataPath -Encoding UTF8 }
    Save-Metadata
    $plan = New-GarminReleasePlan $directory $context $products
    Assert ($plan.Files.Count -eq 4) "All manifest PRGs, actual IQ and separate checksums included"
    Assert ($plan.Tag -eq "auto-garmin-5.8.3-9f1ec78-p123-b456") "Owned immutable tag"
    Assert ($plan.Release.target_commitish -ceq $context.Sha) "Exact build commit, not version suffix"
    Assert ($plan.Release.body.Contains($context.Sha)) "Full source SHA in notes"
    foreach ($path in @("/-/pipelines/123", "/-/jobs/456", "/-/jobs/789")) {
        Assert ($plan.Release.body.Contains($path)) "Pipeline, build and publisher links"
    }
    Assert ($plan.Release.body.Contains("development channel")) "Truthful channel"
    Assert ($plan.Release.body -notmatch "APK|versionCode") "No Android claims"
    Assert ($plan.Files[0].Label -eq "Fenix 7X direct-install app (.prg)") "Readable device label"
    Assert ($plan.Release.body.Contains("## SHA-256")) "Separate per-asset checksums"
    Assert ($plan.Release.draft -and $plan.Release.prerelease -and $plan.Release.make_latest -eq "false") "Safe draft/prerelease channel"
    foreach ($key in @("Enabled", "Protected", "Source", "Branch", "Sha", "PipelineId")) {
        $bad = $context.Clone(); $bad[$key] = "invalid"
        Reject { New-GarminReleasePlan $directory $bad $products } "requires|Invalid"
    }
    foreach ($key in @("signing", "tests", "source_sha", "project_id", "pipeline_id", "build_job_id", "version")) {
        $saved = $metadata[$key]; $metadata[$key] = "invalid"; Save-Metadata
        Reject { New-GarminReleasePlan $directory $context $products } "provenance"
        $metadata[$key] = $saved
    }
    Save-Metadata
    Reject { New-GarminReleasePlan $directory $context @("fenix7x") } "complete manifest"
    $file = Join-Path $directory "WearTAK-Garmin-fenix7x.prg"
    $bytes = [IO.File]::ReadAllBytes($file)
    Add-Content $file "tampered"
    Reject { New-GarminReleasePlan $directory $context $products } "checksum mismatch"
    [IO.File]::WriteAllBytes($file, $bytes)
    $checksum = Join-Path $directory "SHA256SUMS.txt"
    $bytes = [IO.File]::ReadAllBytes($checksum)
    Set-Content $checksum "omitted inventory"
    $hashEntry = @($metadata.artifacts | Where-Object { $_.name -eq "SHA256SUMS.txt" })[0]
    $originalHash = $hashEntry.sha256
    $hashEntry.sha256 = (Get-FileHash $checksum -Algorithm SHA256).Hash.ToLowerInvariant()
    Save-Metadata
    Reject { New-GarminReleasePlan $directory $context $products } "exactly the distributables"
    [IO.File]::WriteAllBytes($checksum, $bytes)
    $hashEntry.sha256 = $originalHash
    Save-Metadata
    $script:calls = @()
    $script:remote = @{}
    $script:assets = @()
    $script:existingRelease = $null
    $script:existingTag = $null
    $script:stale = $false
    $script:corrupt = $false
    $script:staleAfterUpload = $false
    $script:edited = $false
    $script:missingSource = $false
    $script:draftCollision = $false
    $script:badInventory = $false
    $request = {
        param($operation)
        $script:calls += $operation
        if ($operation.Path -like "/repository/branches?*") {
            return @{name = "main"; commit = @{id = $(if ($script:stale) { "b" * 40 } else { $context.Sha })}}
        }
        if ($operation.Path -eq "/commits/$($context.Sha)") {
            return @{sha = $(if ($script:missingSource) { "c" * 40 } else { $context.Sha })}
        }
        if ($operation.Path -like "/releases?per_page=*") {
            if ($script:draftCollision) { return @{tag_name = $plan.Tag} }
            return @()
        }
        if ($operation.Path -eq "/releases/tags/$($plan.Tag)") { return $script:existingRelease }
        if ($operation.Path -eq "/git/ref/tags/$($plan.Tag)") { return $script:existingTag }
        if ($operation.ContainsKey("InFile")) {
            $fileInfo = Get-Item $operation.InFile
            $filePlan = @($plan.Files | Where-Object { $_.Name -ceq $fileInfo.Name })[0]
            $assetId = 100 + $script:assets.Count
            $script:remote["/releases/assets/$assetId"] = [IO.File]::ReadAllBytes($operation.InFile)
            $asset = @{id = $assetId; name = $filePlan.Name; label = $filePlan.Label}
            $script:assets += $asset
            if ($script:staleAfterUpload) { $script:stale = $true }
            return $asset
        }
        if ($operation.ContainsKey("OutFile")) {
            if (-not $script:remote.ContainsKey($operation.Path)) { return $null }
            if ($script:corrupt) { Set-Content $operation.OutFile "corrupt" }
            else { [IO.File]::WriteAllBytes($operation.OutFile, $script:remote[$operation.Path]) }
            return $true
        }
        if ($operation.Method -eq "POST" -and $operation.Path -eq "/releases") {
            Assert ($operation.Body.target_commitish -ceq $context.Sha) "Publication uses exact ref"
            return @{id = 42; tag_name = $plan.Tag; target_commitish = $context.Sha; draft = $true}
        }
        if ($operation.Path -eq "/releases/42/assets?per_page=100") {
            if ($script:badInventory) { return @() }
            return $script:assets
        }
        if ($operation.Method -eq "GET" -and $operation.Path -eq "/releases/42") {
            $body = if ($script:edited) { "manual note" } else { $plan.Release.body }
            return @{draft = $true; prerelease = $true; name = $plan.Release.name
                body = $body; tag_name = $plan.Tag; target_commitish = $context.Sha}
        }
        if ($operation.Method -eq "PATCH") {
            $script:existingTag = @{object = @{type = "commit"; sha = $context.Sha}}
            return @{draft = $false; prerelease = $true; tag_name = $plan.Tag}
        }
        throw "Unexpected request: $($operation.Method) $($operation.Path)"
    }
    Invoke-GarminPublication $plan $request | Out-Null
    Assert (@($script:calls | Where-Object { $_.ContainsKey("InFile") }).Count -eq 4) "Upload every validated artifact"
    Assert ($script:calls[-2].Method -eq "PATCH") "Release exposed only after byte verification"
    Assert (@($script:calls | Where-Object { $_.Method -eq "DELETE" }).Count -eq 0) "Never clean up previous publications"
    Assert (@($script:calls | Where-Object { $_.Method -eq "PATCH" -and $_.Path -ne "/releases/42" }).Count -eq 0) "Only own new draft modified"
    $script:calls = @()
    $script:existingRelease = @{body = "manual notes"}
    Reject { Invoke-GarminPublication $plan $request } "refusing to overwrite"
    $script:existingRelease = $null; $script:existingTag = @{name = $plan.Tag}
    Reject { Invoke-GarminPublication $plan $request } "refusing to claim"
    $script:existingTag = $null; $script:stale = $true; $script:calls = @()
    Reject { Invoke-GarminPublication $plan $request } "Stale pipeline"
    Assert (@($script:calls | Where-Object { $_.Method -in "PATCH", "POST" }).Count -eq 0) "Stale run does not write"
    $script:stale = $false; $script:missingSource = $true; $script:calls = @()
    Reject { Invoke-GarminPublication $plan $request } "not available on GitHub"
    Assert (@($script:calls | Where-Object { $_.Method -in "PATCH", "POST" }).Count -eq 0) "Unmirrored source does not write"
    $script:missingSource = $false; $script:draftCollision = $true; $script:calls = @()
    Reject { Invoke-GarminPublication $plan $request } "Draft or release already exists"
    Assert (@($script:calls | Where-Object { $_.Method -in "PATCH", "POST" }).Count -eq 0) "Existing unpublished draft is not overwritten"
    $script:draftCollision = $false
    $script:stale = $false; $script:corrupt = $true; $script:calls = @()
    Reject { Invoke-GarminPublication $plan $request } "Remote checksum mismatch"
    Assert (@($script:calls | Where-Object { $_.Method -eq "PATCH" }).Count -eq 0) "Mismatch cannot expose release"
    $script:corrupt = $false; $script:remote = @{}; $script:assets = @()
    $script:staleAfterUpload = $true; $script:calls = @()
    Reject { Invoke-GarminPublication $plan $request } "Stale pipeline"
    Assert (@($script:calls | Where-Object { $_.Method -eq "PATCH" }).Count -eq 0) "Head change during upload cannot expose release"
    $script:staleAfterUpload = $false; $script:stale = $false; $script:assets = @()
    $script:edited = $true; $script:calls = @()
    Reject { Invoke-GarminPublication $plan $request } "changed concurrently"
    Assert (@($script:calls | Where-Object { $_.Method -eq "PATCH" }).Count -eq 0) "Manual note edit cannot be published over"
    $script:edited = $false; $script:assets = @(); $script:badInventory = $true; $script:calls = @()
    Reject { Invoke-GarminPublication $plan $request } "asset count mismatch"
    Assert (@($script:calls | Where-Object { $_.Method -eq "PATCH" }).Count -eq 0) "Missing remote asset prevents publication"
    $savedEnvironment = @{}
    foreach ($key in @("GITLAB_CI", "CI_JOB_TOKEN", "GARMIN_GITHUB_RELEASE_TOKEN")) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    }
    try {
        $env:GITLAB_CI = "false"
        Reject { & (Join-Path $PSScriptRoot "Publish-GarminRelease.ps1") -Directory $directory } "only in GitLab CI"
        $env:GITLAB_CI = "true"; $env:CI_JOB_TOKEN = "synthetic-test-token"; $env:GARMIN_GITHUB_RELEASE_TOKEN = $null
        Reject { & (Join-Path $PSScriptRoot "Publish-GarminRelease.ps1") -Directory $directory } "Missing protected"
    } finally {
        foreach ($key in $savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], "Process")
        }
    }
    Write-Output "PASS: $script:checks Garmin publisher assertions; all network requests mocked."
} finally {
    if (Test-Path -LiteralPath $directory) {
        Get-ChildItem -LiteralPath $directory -File | Remove-Item -Force
        [IO.Directory]::Delete($directory)
    }
}
