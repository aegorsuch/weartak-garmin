Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-GarminReleasePlan {
    param([string]$Directory, [hashtable]$Context, [string[]]$Products)
    foreach ($key in @("ProjectId", "PipelineId", "PipelineIid", "JobId")) {
        if ($Context[$key] -notmatch '^[1-9][0-9]*$') { throw "Invalid release context: $key" }
    }
    if ($Context.Sha -cnotmatch '^[0-9a-f]{40}$' -or $Context.ProjectUrl -notmatch '^https://[^?#\s]+$') {
        throw "Invalid source SHA or canonical project URL."
    }
    if ($Context.Enabled -ne "true" -or $Context.Protected -ne "true" -or $Context.Source -ne "push" -or
        -not $Context.DefaultBranch -or $Context.Branch -cne $Context.DefaultBranch) {
        throw "Publishing requires an enabled, protected default-branch push."
    }
    if ($Context.ProjectId -cne "6783" -or $Context.DefaultBranch -cne "main" -or
        $Context.ProjectUrl -cne "https://git.tak.gov/core/weartak-core/weartak-garmin") {
        throw "Invalid canonical project or protected branch."
    }
    $metadata = Get-Content -Raw (Join-Path $Directory "release-build.json") | ConvertFrom-Json
    if ($metadata.schema -ne 2 -or $metadata.signing -cne "production-key-fingerprint-verified" -or
        $metadata.tests -cne "not-run-headless-linux" -or $metadata.sdk -cne "9.2.0" -or
        $metadata.export -cne "monkeyc-e" -or $metadata.hardware_variants -lt $Products.Count -or
        $metadata.source_sha -cne $Context.Sha -or
        [string]$metadata.project_id -cne $Context.ProjectId -or [string]$metadata.pipeline_id -cne $Context.PipelineId -or
        [string]$metadata.pipeline_iid -cne $Context.PipelineIid -or
        [string]$metadata.build_job_id -notmatch '^[1-9][0-9]*$' -or
        $metadata.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9a-f]+)?$') {
        throw "Missing or mismatched production build provenance."
    }
    if (-not $Products.Count -or @($Products | Select-Object -Unique).Count -ne $Products.Count -or
        @($Products | Where-Object { $_ -notmatch '^[a-z0-9]+$' }).Count) { throw "Invalid manifest product set." }
    if (Compare-Object ($Products | Sort-Object) ($metadata.products | Sort-Object)) {
        throw "Build products do not match the complete manifest distribution set."
    }
    $assetName = "WearTAK-Garmin-$($metadata.version)-p$($Context.PipelineIid).iq"
    $expected = @($assetName, "SHA256SUMS.txt")
    $recorded = @($metadata.artifacts | ForEach-Object { $_.name })
    if ($recorded.Count -ne $expected.Count -or (Compare-Object ($expected | Sort-Object) ($recorded | Sort-Object))) {
        throw "Build artifacts do not match the complete manifest distribution set."
    }
    $files = @()
    foreach ($name in $expected) {
        $file = Get-Item -LiteralPath (Join-Path $Directory $name)
        if ($file.PSIsContainer -or $file.Length -le 0 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Invalid release file: $name"
        }
        $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry = @($metadata.artifacts | Where-Object { $_.name -ceq $name })
        if ($entry.Count -ne 1 -or $entry[0].sha256 -cne $hash) { throw "Build checksum mismatch: $name" }
        $files += [pscustomobject]@{Name = $name; Path = $file.FullName; Hash = $hash}
    }
    $checksumLines = @(Get-Content (Join-Path $Directory "SHA256SUMS.txt"))
    $wantedLines = @($files | Where-Object { $_.Name -ne "SHA256SUMS.txt" } | ForEach-Object { "$($_.Hash)  $($_.Name)" })
    if ($checksumLines.Count -ne $wantedLines.Count -or
        (Compare-Object ($checksumLines | Sort-Object) ($wantedLines | Sort-Object))) {
        throw "SHA256SUMS.txt does not cover exactly the distributables."
    }
    $header = [IO.File]::ReadAllBytes((Join-Path $Directory $assetName))
    if ($header.Length -lt 32 -or [BitConverter]::ToString($header[0..5]) -cne "37-7A-BC-AF-27-1C") {
        throw "Release asset is not a Connect IQ 7z export."
    }
    # Checksums stay in the notes and CI artifacts; GitHub gets exactly one IQ.
    $files = @($files | Where-Object { $_.Name -ceq $assetName })
    $build = [string]$metadata.build_job_id
    $tag = "auto-garmin-$($metadata.version)-p$($Context.PipelineIid)-b$build"
    $base = $Context.ProjectUrl.TrimEnd("/")
    foreach ($file in $files) {
        $file | Add-Member NoteProperty Url "https://github.com/aegorsuch/weartak-garmin/releases/download/$tag/$($file.Name)"
        $file | Add-Member NoteProperty Label $file.Name
    }
    $lines = @(
        "<!-- weartak-garmin-auto:v1 project=$($Context.ProjectId) pipeline=$($Context.PipelineId) build=$build -->",
        "Production-key-signed Garmin Connect IQ build from the protected default branch. Automated development channel, not a Garmin Connect IQ Store publication.",
        "",
        "The .iq bundle is for Garmin distribution tooling, not copying directly to a watch.",
        "**Simulator tests:** NOT RUN (headless Linux; interactive desktop required).",
        "**Products:** $($Products -join ', ')",
        "",
        "**Source:** [$($Context.Sha)]($base/-/commit/$($Context.Sha))",
        "**Pipeline:** [#$($Context.PipelineId)]($base/-/pipelines/$($Context.PipelineId))",
        "**Build job:** [#$build]($base/-/jobs/$build)",
        "**Publisher job:** [#$($Context.JobId)]($base/-/jobs/$($Context.JobId))",
        "",
        "## Downloads"
    )
    $lines += @($files | Where-Object { $_.Name -ne "SHA256SUMS.txt" } | ForEach-Object { "- [$($_.Label)]($($_.Url))" })
    $lines += @("", "## SHA-256", "", '```text')
    $lines += @($files | ForEach-Object { "$($_.Hash)  $($_.Name)" })
    $lines += '```'
    return [pscustomobject]@{
        Context = $Context; Tag = $tag; Files = $files
        Release = @{name = "TAK.gov Forge CI/CD Pipeline Release ($($metadata.version)-p$($Context.PipelineIid))"
            tag_name = $tag; target_commitish = $Context.Sha; body = ($lines -join "`n")
            draft = $true; prerelease = $true; make_latest = "false"}
    }
}

function Invoke-GarminPublication {
    param($Plan, [scriptblock]$Request)
    function Assert-CurrentHead {
        $branch = [uri]::EscapeDataString("^$([regex]::Escape($Plan.Context.DefaultBranch))$")
        $branches = @(& $Request @{Method = "GET"; Target = "gitlab"; Path = "/repository/branches?search=$branch&per_page=100"})
        $current = @($branches | Where-Object { $_.name -ceq $Plan.Context.DefaultBranch })
        if ($current.Count -ne 1 -or $current[0].commit.id -cne $Plan.Context.Sha) {
            throw "Stale pipeline: default-branch head no longer matches the built source."
        }
        $mirror = & $Request @{Method = "GET"; Path = "/git/ref/heads/main"}
        if ($mirror.object.type -cne "commit" -or $mirror.object.sha -cne $Plan.Context.Sha) {
            throw "GitHub main does not mirror the exact canonical build SHA."
        }
    }
    Assert-CurrentHead
    $source = & $Request @{Method = "GET"; Path = "/commits/$($Plan.Context.Sha)"}
    if ($source.sha -cne $Plan.Context.Sha) { throw "Exact canonical build commit is not available on GitHub." }
    $existing = & $Request @{Method = "GET"; Path = "/releases/tags/$($Plan.Tag)"; AllowMissing = $true}
    if ($null -ne $existing) { throw "Release already exists; refusing to overwrite notes or assets." }
    $tag = & $Request @{Method = "GET"; Path = "/git/ref/tags/$($Plan.Tag)"; AllowMissing = $true}
    if ($null -ne $tag) { throw "Tag already exists; refusing to claim an existing tag." }
    # List drafts too: GitHub's tag lookup does not reliably find an unpublished draft.
    for ($page = 1; ; $page++) {
        $releases = @(& $Request @{Method = "GET"; Path = "/releases?per_page=100&page=$page"})
        if (@($releases | Where-Object { $_.tag_name -ceq $Plan.Tag }).Count) {
            throw "Draft or release already exists; refusing to overwrite notes or assets."
        }
        if ($releases.Count -lt 100) { break }
    }
    Assert-CurrentHead
    $created = & $Request @{Method = "POST"; Path = "/releases"; Body = $Plan.Release}
    if ([string]$created.id -notmatch '^[1-9][0-9]*$' -or $created.tag_name -cne $Plan.Tag -or
        -not $created.draft -or $created.target_commitish -cne $Plan.Context.Sha) {
        throw "Draft creation response did not match the requested source/tag; inspect before retrying."
    }
    $releaseId = [string]$created.id
    foreach ($file in $Plan.Files) {
        $download = Join-Path ([IO.Path]::GetTempPath()) ("garmin-verify-" + [guid]::NewGuid())
        try {
            Assert-CurrentHead
            $uploadPath = "/releases/$releaseId/assets?name=$([uri]::EscapeDataString($file.Name))&label=$([uri]::EscapeDataString($file.Label))"
            $asset = & $Request @{Method = "POST"; Target = "upload"; Path = $uploadPath; InFile = $file.Path}
            if ([string]$asset.id -notmatch '^[1-9][0-9]*$' -or $asset.name -cne $file.Name) {
                throw "Uploaded asset identity mismatch; draft remains unpublished."
            }
            $file | Add-Member NoteProperty UploadedId ([string]$asset.id) -Force
            $null = & $Request @{Method = "GET"; Path = "/releases/assets/$($asset.id)"; OutFile = $download}
            if ((Get-FileHash $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.Hash) {
                throw "Remote checksum mismatch; draft remains unpublished: $($file.Name)"
            }
        } finally {
            if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
        }
    }
    $remoteAssets = @(& $Request @{Method = "GET"; Path = "/releases/$releaseId/assets?per_page=100"})
    if ($remoteAssets.Count -ne $Plan.Files.Count) { throw "Draft asset count mismatch." }
    foreach ($file in $Plan.Files) {
        $matches = @($remoteAssets | Where-Object {
            $_.name -ceq $file.Name -and $_.label -ceq $file.Label -and [string]$_.id -ceq $file.UploadedId
        })
        if ($matches.Count -ne 1) { throw "Draft asset inventory mismatch." }
    }
    Assert-CurrentHead
    $draft = & $Request @{Method = "GET"; Path = "/releases/$releaseId"}
    if (-not $draft.draft -or -not $draft.prerelease -or $draft.name -cne $Plan.Release.name -or
        $draft.body -cne $Plan.Release.body -or $draft.tag_name -cne $Plan.Tag -or
        $draft.target_commitish -cne $Plan.Context.Sha) { throw "Draft changed concurrently; refusing to publish." }
    $published = & $Request @{Method = "PATCH"; Path = "/releases/$releaseId"; Body = @{draft = $false; make_latest = "false"}}
    $tag = & $Request @{Method = "GET"; Path = "/git/ref/tags/$($Plan.Tag)"}
    if ($published.draft -or -not $published.prerelease -or $published.tag_name -cne $Plan.Tag -or
        $tag.object.type -cne "commit" -or $tag.object.sha -cne $Plan.Context.Sha) {
        throw "Published release verification failed; inspect before retrying. Nothing will be deleted."
    }
    Write-Output "Created verified Garmin GitHub prerelease $($Plan.Tag). No releases, tags or assets were deleted."
}

Export-ModuleMember -Function New-GarminReleasePlan, Invoke-GarminPublication
