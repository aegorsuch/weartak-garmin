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
    [IO.File]::WriteAllBytes((Join-Path $script:directory $script:assetName), $script:bytes)
    $script:hash = (Get-FileHash (Join-Path $script:directory $script:assetName)).Hash.ToLowerInvariant()
    "$script:hash  $script:assetName" | Set-Content (Join-Path $script:directory "SHA256SUMS.txt") -Encoding ASCII
    $script:metadata = @{
        schema = 2; signing = "production-key-fingerprint-verified"; tests = "not-run-headless-linux"
        sdk = "9.2.0"; export = "monkeyc-e"; hardware_variants = 3; products = $script:products
        source_sha = $script:context.Sha; project_id = "6783"; pipeline_id = "123"; build_job_id = "456"
        pipeline_iid = "42"; version = "5.8.3-9f1ec78"
        artifacts = @(Get-ChildItem $script:directory -File | ForEach-Object {
            @{name = $_.Name; sha256 = (Get-FileHash $_.FullName).Hash.ToLowerInvariant()}
        })
    }
    Save-Metadata
    $script:plan = New-GarminReleasePlan $script:directory $script:context $script:products
    $script:calls = @()
    $script:release = $null
    $script:tag = $null
    $script:assets = @()
    $script:remote = @{}
    $script:flags = @{}
    foreach ($flag in @("stale", "mirror", "source", "collision", "corruptNew", "corruptOld",
        "corruptPublished", "patched", "unknownAfterUpload", "uploaded", "edit", "staleAfterUpload",
        "moveAnchor", "editPublished", "wrongLabel", "badDraft", "corruptOldPublished")) {
        $script:flags[$flag] = $false
    }
    if ($Existing) {
        $script:oldState = [ordered]@{
            project = "6783"; pipeline = "122"; iid = "41"; build = "455"; version = "5.8.3-9f1ec78"
            sha = ("b" * 40); asset = "91"; filename = "WearTAK-Garmin-5.8.3-9f1ec78-p41.iq"; hash = $script:hash
        }
        $script:release = @{
            id = 42; name = "TAK.gov Forge CI/CD Pipeline Release (5.8.3-9f1ec78-p41)"
            tag_name = $script:plan.Tag; target_commitish = ("b" * 40)
            body = (Expected-Body $script:oldState); draft = $false; prerelease = $false
        }
        $script:tag = @{object = @{type = "commit"; sha = ("b" * 40)}}
        $script:assets = @(@{id = 91; name = $script:oldState.filename; label = $script:oldState.filename; size = $script:bytes.Length})
        $script:remote["91"] = $script:bytes
    }
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
            Assert ((Get-FileHash (Join-Path $script:plan.BackupDirectory $script:oldState.filename)).Hash.ToLowerInvariant() -ceq $script:hash) "Previous bytes backed up before upload"
        }
        $asset = @{id = 92; name = $script:assetName; label = $script:assetName; size = $script:bytes.Length}
        $script:assets += $asset
        $script:remote["92"] = [IO.File]::ReadAllBytes($op.InFile)
        $script:flags.uploaded = $true
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
        Assert ($op.Path -ceq "/releases/assets/91") "Only prior owned asset eligible for deletion"
        Assert ($script:flags.patched -and -not $script:release.draft) "New build published before prior asset deletion"
        Assert ($script:release.body -ceq (Expected-Body $script:plan.State)) "Exact new body before deletion"
        $script:assets = @($script:assets | Where-Object { $_.id -ne 91 })
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
    Assert ($script:plan.Files.Count -eq 1 -and $script:plan.Files[0].Name -ceq $script:assetName -and
        $script:plan.Files[0].Label -ceq $script:assetName) "Exactly one filename-equals-label IQ"
    Assert ($script:plan.Release.name -ceq "TAK.gov Forge CI/CD Pipeline Release (5.8.3-9f1ec78-p42)") "Exact title with project IID"
    Assert ($script:plan.Release.body -ceq (Expected-Body $script:plan.State)) "Exact full release body"
    Assert (@($script:plan.Release.body -split "`n" | Where-Object { $_ -like "- *" }).Count -eq 5) "Exactly five bullets"
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
    Invoke-GarminPublication $script:plan $request | Out-Null
    Assert ($script:release.body -ceq (Expected-Body $script:plan.State)) "First published body exact including owned asset ID"
    Assert ($script:plan.State.asset -ceq "92" -and $script:assets.Count -eq 1) "First publication records owned asset"
    Assert (Test-Path (Join-Path $script:plan.BackupDirectory "after.json")) "Published snapshot retained"
    No-Deletes

    Setup -Existing
    Invoke-GarminPublication $script:plan $request | Out-Null
    Assert ($script:assets.Count -eq 1 -and $script:assets[0].id -eq 92) "Rolling update leaves exactly one current IQ"
    Assert ($script:tag.object.sha -ceq ("b" * 40)) "Anchor commit never moves"
    Assert (@($script:calls | Where-Object { $_.Method -eq "POST" -and $_.Path -eq "/releases" }).Count -eq 0) "Rolling update reuses release"
    Assert (@($script:calls | Where-Object { $_.Method -eq "DELETE" }).Count -eq 1) "Only one prior owned asset removed"
    Assert ($script:release.body -ceq (Expected-Body $script:plan.State)) "Updated full body exact"

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
                $script:release.body = Expected-Body $script:oldState
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
