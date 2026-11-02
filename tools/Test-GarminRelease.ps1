$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot "GarminRelease.psm1") -Force
$root = Join-Path ([IO.Path]::GetTempPath()) ("garmin-publisher-test-" + [guid]::NewGuid())
$script:checks = 0
$script:case = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:checks++
}
function Reject([scriptblock]$Action, [string]$Pattern) {
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert ($null -ne $message -and $message -match $Pattern) "Expected '$Pattern'; got '$message'"
}
function Expected-Body($State) {
    $lines = @(
        "Automatically published stable Garmin main-channel build.",
        "",
        "- IQ version: **$($State.version)**",
        "- Build: GitLab pipeline **$($State.pipeline)** (project pipeline **$($State.iid)**)",
        "- Pipeline: https://git.tak.gov/core/weartak-core/weartak-garmin/-/pipelines/$($State.pipeline)",
        ('- Source commit: `{0}` on TAK.gov `main`' -f $State.sha),
        "",
        "| Target | Hardware part | Device mapping | Artifact | SHA-256 |",
        "| --- | --- | --- | --- | --- |"
    )
    foreach ($asset in $State.assets) {
        $urlName = [uri]::EscapeDataString([string]$asset.filename)
        $url = "https://github.com/aegorsuch/weartak-garmin/releases/download/TAK.gov-Forge-CI-CD-Pipeline-Release/$urlName"
        $target = [string]$asset.product
        if (-not $asset.part_number) { $target = "IQ distribution" }
        $part = if ($asset.part_number) { [string]$asset.part_number } else { "N/A" }
        $lines += "| $target | $part | $($asset.model) | [Download]($url) | $($asset.hash) |"
    }
    $lines += @(
        "",
        'The `.iq` is a distribution bundle. Download the matching signed `.prg` for direct device installation. The fixed GitHub source archives use the original rolling-release anchor; the source commit above identifies this build.'
    )
    $lines += "<!-- weartak-garmin-rolling:v2 $($State | ConvertTo-Json -Compress) -->"
    return ($lines -join "`n")
}
function Expected-BodyV1($State) {
    return (@(
        "Automatically published stable Garmin main-channel build.",
        "",
        "- IQ version: **$($State.version)**",
        "- Build: GitLab pipeline **$($State.pipeline)** (project pipeline **$($State.iid)**)",
        "- Pipeline: https://git.tak.gov/core/weartak-core/weartak-garmin/-/pipelines/$($State.pipeline)",
        ('- Source commit: `{0}` on TAK.gov `main`' -f $State.sha),
        ('- SHA256: `{0}`' -f $State.hash),
        "",
        'Use the IQ bundle above with Garmin distribution tooling; do not copy it directly to a watch. GitHub''s "Source code" archives come from the fixed release anchor tag, not from this build; the source commit above is authoritative and may not yet be mirrored to GitHub.',
        "",
        "<!-- weartak-garmin-rolling:v1 $($State | ConvertTo-Json -Compress) -->"
    ) -join "`n")
}
function Setup([switch]$Existing) {
    $script:case++
    $script:directory = Join-Path $root "case-$script:case"
    $null = New-Item -ItemType Directory -Path $script:directory
    $script:context = @{
        Enabled = "true"; Protected = "true"; Source = "push"; Branch = "main"; DefaultBranch = "main"
        ProjectId = "6783"; PipelineId = "123"; PipelineIid = "42"; JobId = "789"; Sha = ("a" * 40)
        ProjectUrl = "https://git.tak.gov/core/weartak-core/weartak-garmin"; ApiUrl = "https://git.tak.gov/api/v4"
    }
    $script:products = @("fenix7x", "fenix847mm")
    $script:assetName = "WearTAK-Garmin-5.8.3-9f1ec78-p42.iq"
    $script:bytes = [byte[]]@(0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c) + [byte[]](1..100)
    $script:variantSpecs = @(
        @{product = "fenix7x"; part_number = "006-B3907-00"; model = "Fenix 7X"},
        @{product = "fenix7x"; part_number = "006-B3910-00"; model = "Fenix 7X"},
        @{product = "fenix847mm"; part_number = "006-B4536-00"; model = "Fenix 8 AMOLED"},
        @{product = "fenix847mm"; part_number = "006-B4775-00"; model = "Tactix 8 AMOLED (47/51 mm)"}
    )
    $script:distFiles = @(@{name = $script:assetName; bytes = $script:bytes})
    foreach ($variant in $script:variantSpecs) {
        $name = "WearTAK-Garmin-5.8.3-9f1ec78-p42-$($variant.product)-$($variant.part_number).prg"
        $script:distFiles += @{name = $name; bytes = [byte[]]@(1, 2, 3, 4, 5, 6, 7)}
        $variant.artifact = $name
        $variant.sha256 = $null
    }
    $script:artifactEntries = @()
    $script:checksumLines = @()
    foreach ($distFile in $script:distFiles) {
        $path = Join-Path $script:directory $distFile.name
        [IO.File]::WriteAllBytes($path, $distFile.bytes)
        $hash = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $script:artifactEntries += @{name = $distFile.name; sha256 = $hash}
        $script:checksumLines += "$hash  $($distFile.name)"
        if ($distFile.name -like "*.prg") {
            $variant = @($script:variantSpecs | Where-Object { $_.artifact -ceq $distFile.name })[0]
            $variant.sha256 = $hash
        }
    }
    $script:hash = ($script:artifactEntries | Where-Object { $_.name -ceq $script:assetName }).sha256
    $script:checksumLines | Set-Content (Join-Path $script:directory "SHA256SUMS.txt") -Encoding ASCII
    $checksumHash = (Get-FileHash (Join-Path $script:directory "SHA256SUMS.txt") -Algorithm SHA256).Hash.ToLowerInvariant()
    $script:metadata = @{
        schema = 3; signing = "production-key-fingerprint-verified"; tests = "not-run-headless-linux"
        sdk = "9.2.0"; export = "monkeyc-e"; hardware_variants = $script:variantSpecs.Count; products = $script:products
        source_sha = $script:context.Sha; project_id = "6783"; pipeline_id = "123"; build_job_id = "456"
        pipeline_iid = "42"; version = "5.8.3-9f1ec78"
        devices = $script:variantSpecs
        artifacts = @($script:artifactEntries) + @(@{name = "SHA256SUMS.txt"; sha256 = $checksumHash})
    }
    Save-Metadata
    $script:plan = New-GarminReleasePlan $script:directory $script:context $script:products
    $script:calls = @()
    $script:release = $null
    $script:tag = $null
    $script:assets = @()
    $script:remote = @{}
    $script:nextAssetId = 92
    $script:oldAssetNames = @()
    $script:flags = @{}
    foreach ($flag in @("stale", "mirror", "source", "collision", "corruptNew", "corruptOld",
        "corruptPublished", "patched", "unknownAfterUpload", "uploaded", "edit", "staleAfterUpload",
        "moveAnchor", "editPublished", "wrongLabel", "badDraft", "corruptOldPublished")) {
        $script:flags[$flag] = $false
    }
    $script:flags.incompleteUpload = $false
    $script:flags.uploadCount = 0
    $script:oldAssetIds = @("91")
    if ($Existing) {
        $script:oldState = [ordered]@{
            project = "6783"; pipeline = "122"; iid = "41"; build = "455"; version = "5.8.3-9f1ec78"
            sha = ("b" * 40); asset = "91"; filename = "WearTAK-Garmin-5.8.3-9f1ec78-p41.iq"; hash = $script:hash
        }
        $script:release = @{
            id = 42; name = "TAK.gov Forge CI/CD Pipeline Release (5.8.3-9f1ec78-p41)"
            tag_name = $script:plan.Tag; target_commitish = ("b" * 40)
            body = (Expected-BodyV1 $script:oldState); draft = $false; prerelease = $false
        }
        $script:tag = @{object = @{type = "commit"; sha = ("b" * 40)}}
        $script:assets = @(@{id = 91; name = $script:oldState.filename; label = $script:oldState.filename; size = $script:bytes.Length})
        $script:remote["91"] = $script:bytes
        $script:oldAssetNames = @($script:oldState.filename)
    }
}
function Setup-V2Existing {
    Setup
    $previousAssets = @()
    $script:assets = @()
    $script:remote = @{}
    $script:oldAssetIds = @()
    $id = 91
    $oldFiles = @(@{name = "WearTAK-Garmin-5.8.3-9f1ec78-p41.iq"; bytes = $script:bytes;
        product = "IQ distribution bundle"; part_number = ""; model = "All validated targets"})
    foreach ($variant in $script:variantSpecs) {
        $name = "WearTAK-Garmin-5.8.3-9f1ec78-p41-$($variant.product)-$($variant.part_number).prg"
        $oldFiles += @{name = $name; bytes = [byte[]]@(9, 8, 7, 6, 5);
            product = $variant.product; part_number = $variant.part_number; model = $variant.model}
    }
    foreach ($file in $oldFiles) {
        $hash = (Get-FileHash -InputStream ([IO.MemoryStream]::new($file.bytes)) -Algorithm SHA256).Hash.ToLowerInvariant()
        $asset = [ordered]@{
            id = [string]$id; filename = $file.name; hash = $hash
            product = $file.product; part_number = $file.part_number; model = $file.model
        }
        $previousAssets += $asset
        $script:assets += @{id = $id; name = $file.name; label = $file.name; size = $file.bytes.Length}
        $script:remote[[string]$id] = $file.bytes
        $script:oldAssetIds += [string]$id
        $script:oldAssetNames += $file.name
        $id++
    }
    $script:nextAssetId = $id
    $script:oldState = [ordered]@{
        project = "6783"; pipeline = "122"; iid = "41"; build = "455"
        version = "5.8.3-9f1ec78"; sha = ("b" * 40)
        products = @($script:products); assets = @($previousAssets)
    }
    $script:release = @{
        id = 42; name = "TAK.gov Forge CI/CD Pipeline Release (5.8.3-9f1ec78-p41)"
        tag_name = $script:plan.Tag; target_commitish = ("b" * 40)
        body = (Expected-Body $script:oldState); draft = $false; prerelease = $false
    }
    $script:tag = @{object = @{type = "commit"; sha = ("b" * 40)}}
}
function Save-Metadata {
    $script:metadata | ConvertTo-Json -Depth 8 |
        Set-Content (Join-Path $script:directory "release-build.json") -Encoding UTF8
}
function Copy-Value($Value) {
    if ($null -eq $Value) { return $null }
    return ($Value | ConvertTo-Json -Depth 15 | ConvertFrom-Json)
}
$request = {
    param($op)
    $script:calls += $op
    if ($op.Path -like "/repository/branches?*") {
        return @{name = "main"; commit = @{id = $(if ($script:flags.stale) { "c" * 40 } else { $script:context.Sha })}}
    }
    if ($op.Path -eq "/git/ref/heads/main") {
        return @{object = @{type = "commit"; sha = $(if ($script:flags.mirror) { "d" * 40 } else { $script:context.Sha })}}
    }
    if ($op.Path -like "/commits/*") { return @{sha = $(if ($script:flags.source) { "e" * 40 } else { $script:context.Sha })} }
    if ($op.Path -eq "/releases/tags/$($script:plan.Tag)") { return (Copy-Value $script:release) }
    if ($op.Path -eq "/git/ref/tags/$($script:plan.Tag)") { return (Copy-Value $script:tag) }
    if ($op.Path -like "/releases?per_page=*") {
        if ($script:flags.collision) { return @{id = 99; tag_name = $script:plan.Tag; draft = $true} }
        if ($null -ne $script:release) { return (Copy-Value $script:release) }
        return @()
    }
    if ($op.ContainsKey("OutFile")) {
        $id = $op.Path.Split("/")[-1]
        $data = $script:remote[$id]
        if (($script:flags.corruptNew -and $id -ne "91") -or ($script:flags.corruptOld -and $id -eq "91") -or
            ($script:flags.corruptOldPublished -and $script:flags.patched -and $id -eq "91") -or
            ($script:flags.corruptPublished -and $script:flags.patched -and $id -ne "91")) {
            $data = [byte[]]@(1, 2, 3)
        }
        [IO.File]::WriteAllBytes($op.OutFile, $data)
        return $true
    }
    if ($op.Path -like "/releases/42/assets?per_page=*") {
        if ($script:flags.unknownAfterUpload -and $script:flags.uploaded) {
            return (@($script:assets) + @(@{id = 999; name = "manual.txt"; label = ""; size = 1}))
        }
        return @(Copy-Value $script:assets)
    }
    if ($op.Method -eq "GET" -and $op.Path -eq "/releases/42") {
        if ($script:flags.edit -and $script:flags.uploaded) { $script:release.body += "`nmanual note" }
        if ($script:flags.editPublished -and $script:flags.patched) { $script:release.body += "`nnewer release" }
        return (Copy-Value $script:release)
    }
    if ($op.Method -eq "POST" -and $op.Path -eq "/releases") {
        Assert (Test-Path (Join-Path $script:plan.BackupDirectory "before.json")) "Snapshot saved before create"
        $script:release = @{id = 42}
        foreach ($key in $op.Body.Keys) { $script:release[$key] = $op.Body[$key] }
        if ($script:flags.badDraft) { $script:release.target_commitish = "bad" }
        return (Copy-Value $script:release)
    }
    if ($op.ContainsKey("InFile")) {
        Assert (Test-Path (Join-Path $script:plan.BackupDirectory "before.json")) "Snapshot saved before upload"
        if ($script:remote.ContainsKey("91")) {
            Assert ((Get-FileHash (Join-Path $script:plan.BackupDirectory $script:oldAssetNames[0])).Hash.ToLowerInvariant() -ceq $script:hash) "Previous bytes backed up before upload"
        }
        if ($script:flags.incompleteUpload -and $script:flags.uploadCount -eq 1) {
            throw "Synthetic interrupted upload."
        }
        $name = Split-Path -Leaf $op.InFile
        $data = [IO.File]::ReadAllBytes($op.InFile)
        $id = [string]$script:nextAssetId
        $script:nextAssetId++
        $asset = @{id = [int]$id; name = $name; label = $name; size = $data.Length}
        $script:assets += $asset
        $script:remote[$id] = $data
        $script:flags.uploaded = $true
        $script:flags.uploadCount++
        if ($script:flags.staleAfterUpload) { $script:flags.stale = $true }
        if ($script:flags.moveAnchor) { $script:tag.object.sha = "c" * 40 }
        if ($script:flags.wrongLabel) { $asset.label = "wrong" }
        return (Copy-Value $asset)
    }
    if ($op.Method -eq "PATCH" -and $op.Path -eq "/releases/42") {
        foreach ($key in $op.Body.Keys) { $script:release[$key] = $op.Body[$key] }
        if ($null -eq $script:tag) { $script:tag = @{object = @{type = "commit"; sha = $script:context.Sha}} }
        $script:flags.patched = $true
        return (Copy-Value $script:release)
    }
    if ($op.Method -eq "DELETE") {
        $id = $op.Path.Split("/")[-1]
        Assert ($id -in $script:oldAssetIds) "Only prior owned assets eligible for deletion"
        Assert ($script:flags.patched -and -not $script:release.draft) "New build published before prior asset deletion"
        Assert ($script:release.body -ceq (Expected-Body $script:plan.State)) "Exact new body before deletion"
        $script:assets = @($script:assets | Where-Object { [string]$_.id -cne $id })
        return $true
    }
    throw "Unexpected request: $($op.Method) $($op.Path)"
}
function No-Writes {
    Assert (@($script:calls | Where-Object { $_.Method -in "POST", "PATCH", "DELETE" }).Count -eq 0) "Rejected preflight makes no writes"
}
function No-Deletes {
    Assert (@($script:calls | Where-Object { $_.Method -eq "DELETE" }).Count -eq 0) "Failure never deletes old assets"
}
try {
    Setup
    Assert ($script:plan.Tag -ceq "TAK.gov-Forge-CI-CD-Pipeline-Release") "Fixed rolling anchor"
    Assert ($script:plan.Files.Count -eq 5) "IQ plus every hardware-specific PRG planned"
    Assert (@($script:plan.Files | Where-Object { $_.Name -like "*.prg" }).Count -eq 4) "All hardware variants planned"
    Assert (@($script:plan.Files | Where-Object { $_.Name -like "*fenix847mm-006-B4775-00.prg" }).Count -eq 1) "Tactix alias target and part retained in asset name"
    Assert (@($script:plan.Files | Where-Object { $_.Name -ceq $script:assetName -and $_.Label -ceq $script:assetName }).Count -eq 1) "Filename-equals-label IQ"
    Assert ($script:plan.Release.name -ceq "TAK.gov Forge CI/CD Pipeline Release (5.8.3-9f1ec78-p42)") "Exact title with project IID"
    Assert ($script:plan.Release.body -ceq (Expected-Body $script:plan.State)) "Exact full release body"
    Assert (@($script:plan.Release.body -split "`n" | Where-Object { $_ -like "- *" }).Count -eq 4) "Build provenance bullets retained"
    Assert ($script:plan.Release.draft -and -not $script:plan.Release.prerelease) "Draft first, stable published channel"
    foreach ($key in @("Enabled", "Protected", "Source", "Branch", "Sha", "PipelineId", "PipelineIid", "ProjectId")) {
        $bad = $script:context.Clone(); $bad[$key] = "invalid"
        Reject { New-GarminReleasePlan $script:directory $bad $script:products } "requires|Invalid"
    }
    foreach ($key in @("signing", "tests", "source_sha", "project_id", "pipeline_id", "pipeline_iid", "build_job_id", "version", "sdk", "export")) {
        $saved = $script:metadata[$key]; $script:metadata[$key] = "invalid"; Save-Metadata
        Reject { New-GarminReleasePlan $script:directory $script:context $script:products } "provenance"
        $script:metadata[$key] = $saved
    }
    Save-Metadata
    Reject { New-GarminReleasePlan $script:directory $script:context @("fenix7x") } "complete manifest"
    Add-Content (Join-Path $script:directory $script:assetName) "tamper"
    Reject { New-GarminReleasePlan $script:directory $script:context $script:products } "checksum mismatch"
    Setup
    $script:variantSpecs[3].product = "unknown-target"
    Save-Metadata
    Reject { New-GarminReleasePlan $script:directory $script:context $script:products } "Invalid target"
    Setup
    $script:variantSpecs[3].part_number = "006-B4536-00"
    $script:variantSpecs[3].artifact = "WearTAK-Garmin-5.8.3-9f1ec78-p42-fenix847mm-006-B4536-00.prg"
    Save-Metadata
    Reject { New-GarminReleasePlan $script:directory $script:context $script:products } "Duplicate hardware variant"
    Setup
    Remove-Item (Join-Path $script:directory $script:variantSpecs[0].artifact)
    Reject { New-GarminReleasePlan $script:directory $script:context $script:products } "Cannot find|complete manifest distribution set"

    Setup
    Invoke-GarminPublication $script:plan $request | Out-Null
    Assert ($script:release.body -ceq (Expected-Body $script:plan.State)) "First published body exact including owned asset ID"
    Assert ($script:plan.State.assets.Count -eq 5 -and $script:assets.Count -eq 5) "First publication records every asset"
    Assert (@($script:plan.State.assets | Where-Object { $_.id -match '^[1-9][0-9]*$' }).Count -eq 5) "Every uploaded asset ID recorded"
    Assert (Test-Path (Join-Path $script:plan.BackupDirectory "after.json")) "Published snapshot retained"
    No-Deletes

    Setup -Existing
    Invoke-GarminPublication $script:plan $request | Out-Null
    Assert ($script:assets.Count -eq 5) "Rolling update leaves complete current asset set"
    Assert ($script:tag.object.sha -ceq ("b" * 40)) "Anchor commit never moves"
    Assert (@($script:calls | Where-Object { $_.Method -eq "POST" -and $_.Path -eq "/releases" }).Count -eq 0) "Rolling update reuses release"
    Assert (@($script:calls | Where-Object { $_.Method -eq "DELETE" }).Count -eq 1) "Only one prior owned asset removed"
    Assert ($script:release.body -ceq (Expected-Body $script:plan.State)) "Updated full body exact"

    Setup-V2Existing
    Invoke-GarminPublication $script:plan $request | Out-Null
    Assert ($script:assets.Count -eq 5) "Schema-v2 rolling update replaces complete prior inventory"
    Assert (@($script:calls | Where-Object { $_.Method -eq "DELETE" }).Count -eq 5) "All prior managed assets removed after publish"
    Assert ((Get-ChildItem $script:plan.BackupDirectory -Filter "WearTAK-Garmin-*-p41*").Count -eq 5) "Every previous variant backed up"

    Setup-V2Existing
    $wrongHardware = $script:oldState.assets | Where-Object { $_.part_number -eq $script:variantSpecs[0].part_number } | Select-Object -First 1
    $wrongHardware.part_number = "006-B9999-00"
    $wrongHardware.filename = "WearTAK-Garmin-$($script:oldState.version)-p$($script:oldState.iid)-" +
        "$($wrongHardware.product)-$($wrongHardware.part_number).prg"
    $script:release.body = Expected-Body $script:oldState
    Reject { Invoke-GarminPublication $script:plan $request } "complete target/part inventory"
    No-Writes

    foreach ($flag in @("stale", "mirror", "source", "collision")) {
        Setup
        $script:flags[$flag] = $true
        Reject { Invoke-GarminPublication $script:plan $request } "Stale|mirror|not available|collision"
        No-Writes
    }
    Setup
    $script:tag = @{object = @{type = "commit"; sha = ("b" * 40)}}
    Reject { Invoke-GarminPublication $script:plan $request } "collision"; No-Writes
    foreach ($flag in @("corruptNew", "edit", "unknownAfterUpload", "staleAfterUpload", "corruptPublished",
        "moveAnchor", "editPublished", "wrongLabel", "corruptOldPublished")) {
        Setup -Existing
        $script:flags[$flag] = $true
        Reject { Invoke-GarminPublication $script:plan $request } "checksum|concurrently|inventory|Stale|identity mismatch"
        No-Deletes
        Assert (@($script:assets | Where-Object { $_.id -eq 91 }).Count -eq 1) "Prior release bytes preserved on failure"
        Assert ((Get-FileHash (Join-Path $script:plan.BackupDirectory $script:oldState.filename)).Hash.ToLowerInvariant() -ceq $script:hash) "Original backup survives failed re-verification"
    }
    Setup -Existing
    $script:flags.incompleteUpload = $true
    Reject { Invoke-GarminPublication $script:plan $request } "interrupted upload"
    No-Deletes
    Setup -Existing
    $script:flags.corruptOld = $true
    Reject { Invoke-GarminPublication $script:plan $request } "checksum"; No-Writes
    Setup
    $script:flags.badDraft = $true
    Reject { Invoke-GarminPublication $script:plan $request } "Draft creation response mismatch"
    No-Deletes
    foreach ($change in @("unknown-notes", "manual-note", "unknown-asset", "newer", "draft")) {
        Setup -Existing
        switch ($change) {
            "unknown-notes" { $script:release.body = "manual notes" }
            "manual-note" { $script:release.body += "`nmanual note" }
            "unknown-asset" { $script:assets += @{id = 900; name = "manual.txt"; label = ""; size = 1} }
            "newer" {
                $script:oldState.pipeline = "124"; $script:oldState.iid = "43"
                $script:oldState.filename = "WearTAK-Garmin-5.8.3-9f1ec78-p43.iq"
                $script:release.name = "TAK.gov Forge CI/CD Pipeline Release (5.8.3-9f1ec78-p43)"
                $script:release.body = Expected-BodyV1 $script:oldState
            }
            "draft" { $script:release.draft = $true }
        }
        Reject { Invoke-GarminPublication $script:plan $request } "Unknown|edited|newer|managed stable"
        No-Writes
    }
    Setup
    $null = New-Item -ItemType Directory $script:plan.BackupDirectory
    Reject { Invoke-GarminPublication $script:plan $request } "backup already exists"; No-Writes
    $saved = @{}
    foreach ($key in @("GITLAB_CI", "CI_JOB_TOKEN", "GARMIN_GITHUB_RELEASE_TOKEN")) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    }
    try {
        $env:GITLAB_CI = "false"
        Reject { & (Join-Path $PSScriptRoot "Publish-GarminRelease.ps1") -Directory $script:directory } "only in GitLab CI"
        $env:GITLAB_CI = "true"; $env:CI_JOB_TOKEN = "synthetic"; $env:GARMIN_GITHUB_RELEASE_TOKEN = $null
        Reject { & (Join-Path $PSScriptRoot "Publish-GarminRelease.ps1") -Directory $script:directory } "Missing protected"
    } finally {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], "Process") }
    }
    Write-Output "PASS: $script:checks Garmin rolling publisher assertions; all network requests mocked."
} finally {
    if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}
