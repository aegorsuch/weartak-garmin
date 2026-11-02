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
    if ($metadata.schema -ne 3 -or $metadata.signing -cne "production-key-fingerprint-verified" -or
        $metadata.tests -cne "not-run-headless-linux" -or $metadata.sdk -cne "9.2.0" -or
        $metadata.export -cne "monkeyc-e" -or
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
    $devices = @($metadata.devices)
    if ($metadata.hardware_variants -ne $devices.Count -or $devices.Count -lt $Products.Count) {
        throw "Build provenance does not enumerate every hardware variant."
    }
    $deviceArtifacts = @()
    foreach ($device in $devices) {
        if ($device.product -notin $Products -or
            $device.part_number -notmatch '^006-B[0-9]{4}-[0-9]{2}$' -or
            $device.model -notmatch '\S') {
            throw "Invalid target or hardware mapping in build provenance."
        }
        $name = "WearTAK-Garmin-$($metadata.version)-p$($Context.PipelineIid)-$($device.product)-$($device.part_number).prg"
        if ($device.artifact -cne $name -or $device.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Invalid device artifact provenance: $name"
        }
        if (@($deviceArtifacts | Where-Object { $_.Name -ceq $name -or $_.PartNumber -ceq $device.part_number }).Count) {
            throw "Duplicate hardware variant in build provenance: $name"
        }
        $deviceArtifacts += [pscustomobject]@{
            Name = $name; Product = [string]$device.product
            PartNumber = [string]$device.part_number; Model = [string]$device.model
            Hash = [string]$device.sha256
        }
    }
    if (Compare-Object ($Products | Sort-Object -Unique) (@($deviceArtifacts | ForEach-Object { $_.Product } | Sort-Object -Unique))) {
        throw "Build provenance does not cover every manifest target."
    }
    $expectedDistributables = @($assetName) + @($deviceArtifacts | ForEach-Object { $_.Name })
    $expected = @($expectedDistributables) + @("SHA256SUMS.txt")
    if (@($expected | Select-Object -Unique).Count -ne $expected.Count) {
        throw "Duplicate distributable filename."
    }
    $recorded = @($metadata.artifacts | ForEach-Object { $_.name })
    if ($recorded.Count -ne $expected.Count -or
        (Compare-Object ($expected | Sort-Object) ($recorded | Sort-Object) -CaseSensitive)) {
        throw "Build artifacts do not match the complete manifest distribution set."
    }
    $files = @()
    foreach ($name in $expectedDistributables) {
        $file = Get-Item -LiteralPath (Join-Path $Directory $name)
        if ($file.PSIsContainer -or $file.Length -le 0 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Invalid release file: $name"
        }
        $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry = @($metadata.artifacts | Where-Object { $_.name -ceq $name })
        if ($entry.Count -ne 1 -or $entry[0].sha256 -cne $hash) { throw "Build checksum mismatch: $name" }
        $device = @($deviceArtifacts | Where-Object { $_.Name -ceq $name })
        $files += [pscustomobject]@{
            Name = $name; Path = $file.FullName; Hash = $hash
            Product = if ($device.Count) { $device[0].Product } else { "IQ distribution bundle" }
            PartNumber = if ($device.Count) { $device[0].PartNumber } else { "" }
            Model = if ($device.Count) { $device[0].Model } else { "All validated targets" }
        }
    }
    $checksumPath = Join-Path $Directory "SHA256SUMS.txt"
    $checksumFile = Get-Item -LiteralPath $checksumPath
    if ($checksumFile.PSIsContainer -or $checksumFile.Length -le 0 -or
        ($checksumFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Invalid release file: SHA256SUMS.txt"
    }
    $checksumHash = (Get-FileHash $checksumPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumEntry = @($metadata.artifacts | Where-Object { $_.name -ceq "SHA256SUMS.txt" })
    if ($checksumEntry.Count -ne 1 -or $checksumEntry[0].sha256 -cne $checksumHash) {
        throw "Build checksum mismatch: SHA256SUMS.txt"
    }
    $checksumLines = @(Get-Content $checksumPath)
    $wantedLines = @($files | ForEach-Object { "$($_.Hash)  $($_.Name)" })
    if ($checksumLines.Count -ne $wantedLines.Count -or
        (Compare-Object ($checksumLines | Sort-Object) ($wantedLines | Sort-Object) -CaseSensitive)) {
        throw "SHA256SUMS.txt does not cover exactly the distributables."
    }
    $header = [IO.File]::ReadAllBytes((Join-Path $Directory $assetName))
    if ($header.Length -lt 32 -or [BitConverter]::ToString($header[0..5]) -cne "37-7A-BC-AF-27-1C") {
        throw "Release asset is not a Connect IQ 7z export."
    }
    $tag = "TAK.gov-Forge-CI-CD-Pipeline-Release"
    $base = $Context.ProjectUrl.TrimEnd("/")
    $stateAssets = @()
    foreach ($file in $files) {
        $file | Add-Member NoteProperty Url "https://github.com/aegorsuch/weartak-garmin/releases/download/$tag/$($file.Name)"
        $file | Add-Member NoteProperty Label $file.Name
        $stateAssets += [ordered]@{
            id = "0"; filename = $file.Name; hash = $file.Hash
            product = $file.Product; part_number = $file.PartNumber; model = $file.Model
        }
    }
    $state = [ordered]@{
        project = "6783"; pipeline = $Context.PipelineId; iid = $Context.PipelineIid
        build = [string]$metadata.build_job_id; version = $metadata.version; sha = $Context.Sha
        products = @($metadata.products)
        assets = @($stateAssets)
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
    $lines = @(
        "Automatically published stable Garmin main-channel build.",
        "",
        "- IQ version: **$($State.version)**",
        "- Build: GitLab pipeline **$($State.pipeline)** (project pipeline **$($State.iid)**)",
        "- Pipeline: $base/-/pipelines/$($State.pipeline)",
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

function Get-GarminRollingBodyV1 {
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
        $marker = [regex]::Match($existing.body, '(?m)^<!-- weartak-garmin-rolling:v([12]) (\{[^\r\n]+\}) -->$')
        if (-not $marker.Success) { throw "Unknown release notes; refusing to overwrite." }
        $markerVersion = $marker.Groups[1].Value
        $oldState = $marker.Groups[2].Value | ConvertFrom-Json
        foreach ($key in @("pipeline", "iid", "build", "asset")) {
            if ($markerVersion -eq "1" -and [string]$oldState.$key -notmatch '^[1-9][0-9]*$') {
                throw "Invalid managed release identity."
            }
        }
        if ($oldState.project -cne "6783" -or $oldState.sha -cnotmatch '^[0-9a-f]{40}$' -or
            [string]$oldState.pipeline -notmatch '^[1-9][0-9]*$' -or
            [string]$oldState.iid -notmatch '^[1-9][0-9]*$' -or
            [string]$oldState.build -notmatch '^[1-9][0-9]*$' -or
            $oldState.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9a-f]+)?$' -or
            $existing.name -cne "TAK.gov Forge CI/CD Pipeline Release ($($oldState.version)-p$($oldState.iid))") {
            throw "Unknown or edited managed release notes; refusing to overwrite."
        }
        $previousSpecs = @()
        if ($markerVersion -eq "1") {
            if ($oldState.hash -cnotmatch '^[0-9a-f]{64}$' -or
                $oldState.filename -cne "WearTAK-Garmin-$($oldState.version)-p$($oldState.iid).iq" -or
                $existing.body -cne (Get-GarminRollingBodyV1 $oldState)) {
                throw "Unknown or edited managed release notes; refusing to overwrite."
            }
            $previousSpecs = @([pscustomobject]@{
                Id = [string]$oldState.asset; Name = [string]$oldState.filename
                Hash = [string]$oldState.hash; Product = "IQ distribution bundle"
                PartNumber = ""; Model = "All validated targets"
            })
        } else {
            if ($existing.body -cne (Get-GarminRollingBody $oldState)) {
                throw "Unknown or edited managed release notes; refusing to overwrite."
            }
            $oldAssets = @($oldState.assets)
            $oldIqName = "WearTAK-Garmin-$($oldState.version)-p$($oldState.iid).iq"
            if ($oldAssets.Count -lt 2 -or
                @($oldAssets | Where-Object { $_.filename -ceq $oldIqName }).Count -ne 1) {
                throw "Invalid managed release asset list."
            }
            $oldProducts = @($oldState.products)
            if (-not $oldProducts.Count -or
                @($oldProducts | Where-Object { $_ -notmatch '^[a-z0-9]+$' }).Count -or
                @($oldProducts | Select-Object -Unique).Count -ne $oldProducts.Count) {
                throw "Invalid managed release target list."
            }
            foreach ($oldAsset in $oldAssets) {
                if ([string]$oldAsset.id -notmatch '^[1-9][0-9]*$' -or
                    $oldAsset.hash -cnotmatch '^[0-9a-f]{64}$' -or
                    ($oldAsset.filename -cne $oldIqName -and
                     $oldAsset.filename -notmatch ("^WearTAK-Garmin-" + [regex]::Escape([string]$oldState.version) +
                        "-p" + [regex]::Escape([string]$oldState.iid) + "-[a-z0-9]+-006-B[0-9]{4}-[0-9]{2}\.prg$"))) {
                    throw "Invalid managed release asset entry."
                }
                if ($oldAsset.filename -ceq $oldIqName) {
                    if ($oldAsset.product -cne "IQ distribution bundle" -or $oldAsset.part_number -or
                        $oldAsset.model -cne "All validated targets") {
                        throw "Invalid managed IQ asset mapping."
                    }
                } elseif ($oldAsset.product -notin $oldProducts -or
                    $oldAsset.part_number -notmatch '^006-B[0-9]{4}-[0-9]{2}$' -or
                    $oldAsset.filename -cne ("WearTAK-Garmin-$($oldState.version)-p$($oldState.iid)-" +
                        "$($oldAsset.product)-$($oldAsset.part_number).prg") -or
                    $oldAsset.model -notmatch '^[A-Za-z0-9 ()/+.-]+$') {
                    throw "Invalid managed PRG target mapping."
                }
                $previousSpecs += [pscustomobject]@{
                    Id = [string]$oldAsset.id; Name = [string]$oldAsset.filename
                    Hash = [string]$oldAsset.hash; Product = [string]$oldAsset.product
                    PartNumber = [string]$oldAsset.part_number; Model = [string]$oldAsset.model
                }
            }
            $oldPrgs = @($previousSpecs | Where-Object { $_.Name -like "*.prg" })
            $expectedHardware = @($plan.Files | Where-Object { $_.Name -like "*.prg" } |
                ForEach-Object { "$($_.Product)|$($_.PartNumber)" } | Sort-Object)
            $previousHardware = @($oldPrgs |
                ForEach-Object { "$($_.Product)|$($_.PartNumber)" } | Sort-Object)
            if ($oldPrgs.Count -ne ($oldAssets.Count - 1) -or
                (Compare-Object ($oldProducts | Sort-Object) (@($oldPrgs | ForEach-Object { $_.Product } | Sort-Object -Unique))) -or
                @($oldPrgs | Select-Object -ExpandProperty PartNumber -Unique).Count -ne $oldPrgs.Count -or
                (Compare-Object $expectedHardware $previousHardware -CaseSensitive)) {
                throw "Managed release does not cover its complete target/part inventory."
            }
            if (@($previousSpecs | Select-Object -ExpandProperty Id -Unique).Count -ne $previousSpecs.Count -or
                @($previousSpecs | Select-Object -ExpandProperty Name -Unique).Count -ne $previousSpecs.Count) {
                throw "Duplicate managed release asset entry."
            }
        }
        if ([long]$oldState.pipeline -ge [long]$Plan.Context.PipelineId -or
            [long]$oldState.iid -ge [long]$Plan.Context.PipelineIid) {
            throw "Existing rolling release is newer or the same pipeline; refusing replay."
        }
        $inventory = @(Read-Assets $existing.id)
        if ($inventory.Count -ne $previousSpecs.Count) {
            throw "Unknown asset inventory; refusing to modify."
        }
        $previous = @()
        foreach ($spec in $previousSpecs) {
            $asset = @($inventory | Where-Object { [string]$_.id -ceq $spec.Id })
            if ($asset.Count -ne 1 -or $asset[0].name -cne $spec.Name -or
                $asset[0].label -cne $spec.Name -or $asset[0].size -le 0) {
                throw "Unknown asset inventory; refusing to modify."
            }
            $previous += [pscustomobject]@{
                Asset = $asset[0]; Hash = $spec.Hash; Name = $spec.Name; File = $null
            }
        }
    } else {
        $previous = @()
    }
    if (Test-Path -LiteralPath $Plan.BackupDirectory) { throw "Publication backup already exists; inspect before retrying." }
    $null = New-Item -ItemType Directory -Path $Plan.BackupDirectory
    @{release = $existing; tag = $tag; assets = @($previous); next = $Plan.Release} |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $Plan.BackupDirectory "before.json") -Encoding UTF8
    foreach ($old in $previous) {
        Verify-Download $old.Asset $old.Hash (Join-Path $Plan.BackupDirectory $old.Name)
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
    $uploaded = @()
    function Assert-Inventory([switch]$Final) {
        $inventory = @(Read-Assets $releaseId)
        $expectedAssets = @($uploaded)
        if (-not $Final) { $expectedAssets = @($previous) + $expectedAssets }
        $expectedIds = @($expectedAssets | ForEach-Object { [string]$_.Asset.id })
        if ($inventory.Count -ne $expectedIds.Count -or
            (Compare-Object ($expectedIds | Sort-Object) (@($inventory | ForEach-Object { [string]$_.id }) | Sort-Object) -CaseSensitive)) {
            throw "Concurrent or unknown asset inventory; refusing mutation."
        }
        foreach ($expectedAsset in $expectedAssets) {
            $asset = $expectedAsset.Asset
            $name = $expectedAsset.Name
            $size = if ($null -ne $expectedAsset.File) {
                (Get-Item -LiteralPath $expectedAsset.File.Path).Length
            } else { $asset.size }
            $current = @($inventory | Where-Object { [string]$_.id -ceq [string]$asset.id })
            if ($current.Count -ne 1 -or $current[0].name -cne $name -or
                $current[0].label -cne $name -or $current[0].size -ne $size) {
                $actual = if ($current.Count -eq 1) {
                    "id=$($current[0].id), name=$($current[0].name), label=$($current[0].label), size=$($current[0].size)"
                } else { "matches=$($current.Count)" }
                throw "Release asset inventory mismatch: $name (expected id=$($asset.id), size=$size; $actual)"
            }
        }
    }
    foreach ($file in $Plan.Files) {
        Assert-Unchanged $baseline
        $uploadPath = "/releases/$releaseId/assets?name=$([uri]::EscapeDataString($file.Name))&label=$([uri]::EscapeDataString($file.Label))"
        $asset = & $Request @{Method = "POST"; Target = "upload"; Path = $uploadPath; InFile = $file.Path}
        if ([string]$asset.id -notmatch '^[1-9][0-9]*$' -or $asset.name -cne $file.Name -or
            $asset.label -cne $file.Label -or $asset.size -ne (Get-Item $file.Path).Length) {
            throw "Uploaded asset identity mismatch; no previous assets will be deleted."
        }
        Verify-Download $asset $file.Hash (Join-Path $Plan.BackupDirectory ("verified-" + $file.Name))
        $uploaded += [pscustomobject]@{Asset = $asset; File = $file; Hash = $file.Hash; Name = $file.Name}
        $stateAsset = @($Plan.State.assets | Where-Object { $_.filename -ceq $file.Name })
        if ($stateAsset.Count -ne 1) { throw "Missing release asset state: $($file.Name)" }
        $stateAsset[0].id = [string]$asset.id
        Assert-Inventory
    }
    Assert-Inventory
    Assert-Unchanged $baseline
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
    foreach ($new in $uploaded) {
        Verify-Download $new.Asset $new.Hash `
            (Join-Path $Plan.BackupDirectory ("verified-published-" + $new.Name))
    }
    Assert-Inventory
    foreach ($old in $previous) {
        Verify-Download $old.Asset $old.Hash (Join-Path $Plan.BackupDirectory ("reverified-" + $old.Name))
        Assert-Unchanged $publishedSnapshot
        Assert-Inventory
        # Delete only backed-up, hash-verified assets from the prior managed inventory.
        $null = & $Request @{Method = "DELETE"; Path = "/releases/assets/$($old.Asset.id)"}
        $previous = @($previous | Where-Object {
            [string]$_.Asset.id -cne [string]$old.Asset.id
        })
        Assert-Inventory
    }
    Assert-Unchanged $publishedSnapshot
    Assert-Inventory -Final
    $published | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $Plan.BackupDirectory "after.json") -Encoding UTF8
    Write-Output "Verified rolling Garmin release $($Plan.Tag), $($uploaded.Count) assets. Historical releases and tags were untouched."
}

Export-ModuleMember -Function New-GarminReleasePlan, Invoke-GarminPublication
