param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$basePath = Join-Path $ProjectRoot "resources\resources.xml"

function Get-StringIds([string]$Path) {
    [xml]$document = Get-Content -Raw -Encoding UTF8 $Path
    return @($document.resources.string | ForEach-Object { $_.id })
}

$baseIds = Get-StringIds $basePath
$baseSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$baseIds | ForEach-Object { [void]$baseSet.Add($_) }

$failed = $false
$localeDirectories = Get-ChildItem -Path $ProjectRoot -Directory -Filter "resources-*" | Sort-Object Name

foreach ($directory in $localeDirectories) {
    $path = Join-Path $directory.FullName "resources.xml"
    if (-not (Test-Path $path)) {
        Write-Error "$($directory.Name): missing resources.xml"
        $failed = $true
        continue
    }

    try {
        $localeIds = Get-StringIds $path
    } catch {
        Write-Error "$($directory.Name): invalid XML - $($_.Exception.Message)"
        $failed = $true
        continue
    }

    $localeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $localeIds | ForEach-Object { [void]$localeSet.Add($_) }
    $missing = @($baseSet | Where-Object { -not $localeSet.Contains($_) } | Sort-Object)
    $extra = @($localeSet | Where-Object { -not $baseSet.Contains($_) } | Sort-Object)

    if ($missing.Count -eq 0 -and $extra.Count -eq 0) {
        Write-Host "$($directory.Name): OK ($($localeIds.Count) keys)"
        continue
    }

    $failed = $true
    Write-Host "$($directory.Name): $($localeIds.Count) keys" -ForegroundColor Yellow
    if ($missing.Count -gt 0) {
        Write-Host "  Missing: $($missing -join ', ')" -ForegroundColor Red
    }
    if ($extra.Count -gt 0) {
        Write-Host "  Extra: $($extra -join ', ')" -ForegroundColor Yellow
    }
}

if ($failed) {
    exit 1
}

Write-Host "All localized resource files match the English key set." -ForegroundColor Green
