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
    $tag = "TAK.gov-Forge-CI-CD-Pipeline-Release"
    $base = $Context.ProjectUrl.TrimEnd("/")
    foreach ($file in $files) {
        $file | Add-Member NoteProperty Url "https://github.com/aegorsuch/weartak-garmin/releases/download/$tag/$($file.Name)"
        $file | Add-Member NoteProperty Label $file.Name
    }
    $state = [ordered]@{
        project = "6783"; pipeline = $Context.PipelineId; iid = $Context.PipelineIid
        build = $build; version = $metadata.version; sha = $Context.Sha
        asset = "0"; filename = $assetName; hash = $files[0].Hash
    }
    return [pscustomobject]@{
        Context = $Context; Tag = $tag; Files = $files; State = $state
        BackupDirectory = (Join-Path $Directory "publication-backup")
        Release = @{name = "TAK.gov Forge CI/CD Pipeline Release ($($metadata.version)-p$($Context.PipelineIid))"
            tag_name = $tag; target_commitish = $Context.Sha; body = (Get-GarminRollingBody $state)
            draft = $true; prerelease = $false; make_latest = "false"}
    }
}

function Get-GarminRollingBody {
    param($State)
    $base = "https://git.tak.gov/core/weartak-core/weartak-garmin"
    return (@(
        "Automatically published stable Garmin main-channel build.",
        "",
        "- IQ version: **$($State.version)**",
        "- Build: GitLab pipeline **$($State.pipeline)** (project pipeline **$($State.iid)**)",
        "- Pipeline: $base/-/pipelines/$($State.pipeline)",
        ('- Source commit: `{0}` on TAK.gov `main`' -f $State.sha),
        ('- SHA256: `{0}`' -f $State.hash),
        "",
        'Use the IQ bundle above with Garmin distribution tooling; do not copy it directly to a watch. GitHub''s "Source code" archives come from the fixed release anchor tag, not from this build; the source commit above is authoritative and may not yet be mirrored to GitHub.',
        "",
        "<!-- weartak-garmin-rolling:v1 $($State | ConvertTo-Json -Compress) -->"
    ) -join "`n")
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
    $file = $Plan.Files[0]
    $existing = & $Request @{Method = "GET"; Path = "/releases/tags/$($Plan.Tag)"; AllowMissing = $true}
    $tag = & $Request @{Method = "GET"; Path = "/git/ref/tags/$($Plan.Tag)"; AllowMissing = $true}
    $matches = @()
    for ($page = 1; ; $page++) {
        $releases = @(& $Request @{Method = "GET"; Path = "/releases?per_page=100&page=$page"})
        $matches += @($releases | Where-Object { $_.tag_name -ceq $Plan.Tag })
        if ($releases.Count -lt 100) { break }
    }
    if (($null -eq $existing -and ($matches.Count -ne 0 -or $null -ne $tag)) -or
        ($null -ne $existing -and ($matches.Count -ne 1 -or $matches[0].id -ne $existing.id))) {
        throw "Anchor tag/draft collision; refusing to claim unknown release state."
    }
    $previous = $null
    $oldState = $null
    function Read-Assets([string]$Id) {
        $all = @()
        for ($page = 1; ; $page++) {
            $batch = @(& $Request @{Method = "GET"; Path = "/releases/$Id/assets?per_page=100&page=$page"})
            $all += $batch
            if ($batch.Count -lt 100) { break }
        }
        return $all
    }
    function Verify-Download($Asset, [string]$Hash, [string]$Path) {
        $null = & $Request @{Method = "GET"; Path = "/releases/assets/$($Asset.id)"; OutFile = $Path}
        if ((Get-Item -LiteralPath $Path).Length -ne $Asset.size -or
            (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Hash) {
            throw "Remote checksum/size mismatch; no previous assets will be deleted."
        }
    }
    function Snapshot($Release) {
        return (@($Release.id, $Release.tag_name, $Release.name, $Release.body,
            $Release.target_commitish, $Release.draft, $Release.prerelease) | ConvertTo-Json -Compress)
    }
    if ($null -ne $existing) {
        if ($existing.draft -or $existing.prerelease -or $null -eq $tag -or $tag.object.type -cne "commit") {
            throw "Existing rolling release is not a published managed stable release."
        }
        $marker = [regex]::Match($existing.body, '(?m)^<!-- weartak-garmin-rolling:v1 (\{[^\r\n]+\}) -->$')
        if (-not $marker.Success) { throw "Unknown release notes; refusing to overwrite." }
        $oldState = $marker.Groups[1].Value | ConvertFrom-Json
        foreach ($key in @("pipeline", "iid", "build", "asset")) {
            if ([string]$oldState.$key -notmatch '^[1-9][0-9]*$') { throw "Invalid managed release identity." }
        }
        if ($oldState.project -cne "6783" -or $oldState.sha -cnotmatch '^[0-9a-f]{40}$' -or
            $oldState.hash -cnotmatch '^[0-9a-f]{64}$' -or
            $oldState.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9a-f]+)?$' -or
            $oldState.filename -cne "WearTAK-Garmin-$($oldState.version)-p$($oldState.iid).iq" -or
            $existing.name -cne "TAK.gov Forge CI/CD Pipeline Release ($($oldState.version)-p$($oldState.iid))" -or
            $existing.body -cne (Get-GarminRollingBody $oldState)) {
            throw "Unknown or edited managed release notes; refusing to overwrite."
        }
        if ([long]$oldState.pipeline -ge [long]$Plan.Context.PipelineId -or
            [long]$oldState.iid -ge [long]$Plan.Context.PipelineIid) {
            throw "Existing rolling release is newer or the same pipeline; refusing replay."
        }
        $inventory = @(Read-Assets $existing.id)
        if ($inventory.Count -ne 1 -or [string]$inventory[0].id -cne [string]$oldState.asset -or
            $inventory[0].name -cne $oldState.filename -or $inventory[0].label -cne $oldState.filename) {
            throw "Unknown asset inventory; refusing to modify."
        }
        $previous = $inventory[0]
    }
    if (Test-Path -LiteralPath $Plan.BackupDirectory) { throw "Publication backup already exists; inspect before retrying." }
    $null = New-Item -ItemType Directory -Path $Plan.BackupDirectory
    @{release = $existing; tag = $tag; assets = $previous; next = $Plan.Release} |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $Plan.BackupDirectory "before.json") -Encoding UTF8
    if ($null -ne $previous) {
        Verify-Download $previous $oldState.hash (Join-Path $Plan.BackupDirectory $oldState.filename)
    }
    Assert-CurrentHead
    if ($null -eq $existing) {
        $existing = & $Request @{Method = "POST"; Path = "/releases"; Body = $Plan.Release}
        if ([string]$existing.id -notmatch '^[1-9][0-9]*$' -or $existing.tag_name -cne $Plan.Tag -or
            -not $existing.draft -or $existing.target_commitish -cne $Plan.Context.Sha) {
            throw "Draft creation response mismatch; inspect before retrying."
        }
    }
    $releaseId = [string]$existing.id
    $baseline = Snapshot $existing
    $expectedAnchor = if ($null -eq $tag) { $null } else { $tag.object.sha }
    function Assert-Unchanged([string]$Expected) {
        Assert-CurrentHead
        $live = & $Request @{Method = "GET"; Path = "/releases/$releaseId"}
        if ((Snapshot $live) -cne $Expected) { throw "Release changed concurrently; refusing mutation." }
        $liveAnchor = & $Request @{Method = "GET"; Path = "/git/ref/tags/$($Plan.Tag)"; AllowMissing = $true}
        if (($null -eq $expectedAnchor -and $null -ne $liveAnchor) -or
            ($null -ne $expectedAnchor -and ($null -eq $liveAnchor -or
                $liveAnchor.object.type -cne "commit" -or $liveAnchor.object.sha -cne $expectedAnchor))) {
            throw "Fixed anchor changed concurrently; refusing mutation."
        }
    }
    Assert-Unchanged $baseline
    $uploadPath = "/releases/$releaseId/assets?name=$([uri]::EscapeDataString($file.Name))&label=$([uri]::EscapeDataString($file.Label))"
    $asset = & $Request @{Method = "POST"; Target = "upload"; Path = $uploadPath; InFile = $file.Path}
    if ([string]$asset.id -notmatch '^[1-9][0-9]*$' -or $asset.name -cne $file.Name -or
        $asset.label -cne $file.Label -or $asset.size -ne (Get-Item $file.Path).Length) {
        throw "Uploaded asset identity mismatch; no previous assets will be deleted."
    }
    $download = Join-Path $Plan.BackupDirectory ("verified-" + $file.Name)
    Verify-Download $asset $file.Hash $download
    function Assert-Inventory([switch]$Final) {
        $inventory = @(Read-Assets $releaseId)
        $expectedIds = @([string]$asset.id)
        if ($null -ne $previous -and -not $Final) { $expectedIds += [string]$previous.id }
        if ($inventory.Count -ne $expectedIds.Count -or
            (Compare-Object ($expectedIds | Sort-Object) (@($inventory | ForEach-Object { [string]$_.id }) | Sort-Object))) {
            throw "Concurrent or unknown asset inventory; refusing mutation."
        }
        $current = @($inventory | Where-Object { [string]$_.id -ceq [string]$asset.id })
        if ($current.Count -ne 1 -or $current[0].name -cne $file.Name -or $current[0].label -cne $file.Label -or
            $current[0].size -ne $asset.size) { throw "New asset inventory mismatch." }
        if ($null -ne $previous -and -not $Final) {
            $old = @($inventory | Where-Object { [string]$_.id -ceq [string]$previous.id })
            if ($old[0].name -cne $previous.name -or $old[0].label -cne $previous.label -or
                $old[0].size -ne $previous.size) { throw "Previous asset changed concurrently." }
        }
    }
    Assert-Inventory
    Assert-Unchanged $baseline
    $Plan.State.asset = [string]$asset.id
    $body = Get-GarminRollingBody $Plan.State
    $published = & $Request @{Method = "PATCH"; Path = "/releases/$releaseId"; Body = @{
        name = $Plan.Release.name; body = $body; draft = $false; prerelease = $false; make_latest = "false"
    }}
    if ($published.draft -or $published.prerelease -or $published.tag_name -cne $Plan.Tag -or
        $published.name -cne $Plan.Release.name -or $published.body -cne $body) {
        throw "Published release verification failed; no previous assets will be deleted."
    }
    $anchor = & $Request @{Method = "GET"; Path = "/git/ref/tags/$($Plan.Tag)"}
    $anchorSha = if ($null -eq $tag) { $Plan.Context.Sha } else { $tag.object.sha }
    if ($anchor.object.type -cne "commit" -or $anchor.object.sha -cne $anchorSha) {
        throw "Fixed anchor verification failed; no previous assets will be deleted."
    }
    $expectedAnchor = $anchorSha
    $publishedSnapshot = Snapshot $published
    Assert-Unchanged $publishedSnapshot
    Verify-Download $asset $file.Hash $download
    Assert-Inventory
    if ($null -ne $previous) {
        Verify-Download $previous $oldState.hash (Join-Path $Plan.BackupDirectory ("reverified-" + $oldState.filename))
        Assert-Unchanged $publishedSnapshot
        Assert-Inventory
        # Only the backed-up, hash-verified prior managed asset ID is eligible.
        $null = & $Request @{Method = "DELETE"; Path = "/releases/assets/$($previous.id)"}
    }
    Assert-Unchanged $publishedSnapshot
    Assert-Inventory -Final
    $published | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $Plan.BackupDirectory "after.json") -Encoding UTF8
    Write-Output "Verified rolling Garmin release $($Plan.Tag), asset $($asset.id). Historical releases and tags were untouched."
}

Export-ModuleMember -Function New-GarminReleasePlan, Invoke-GarminPublication
