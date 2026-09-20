param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$basePath = Join-Path $ProjectRoot "resources\resources.xml"

function Get-StringElements([string]$Path) {
    $document = [xml](Get-Content -Raw -Encoding UTF8 $Path)
    $elements = @{}
    foreach ($element in @($document.resources.string)) {
        $elements[$element.id] = $element.OuterXml
    }
    return $elements
}

$baseElements = Get-StringElements $basePath
$updated = 0

foreach ($directory in Get-ChildItem -Path $ProjectRoot -Directory -Filter "resources-*" | Sort-Object Name) {
    $path = Join-Path $directory.FullName "resources.xml"
    if (-not (Test-Path $path)) {
        continue
    }

    $localeElements = Get-StringElements $path
    $missing = @($baseElements.Keys | Where-Object { -not $localeElements.ContainsKey($_) } | Sort-Object)
    if ($missing.Count -eq 0) {
        Write-Host "$($directory.Name): complete"
        continue
    }

    $content = [System.IO.File]::ReadAllText($path)
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $fallbacks = ($missing | ForEach-Object { "    $($baseElements[$_])" }) -join $newline
    $content = $content -replace "\s*</resources>\s*$", "$newline$fallbacks$newline</resources>"
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
    $updated++
    Write-Host "$($directory.Name): added $($missing.Count) English fallback keys"
}

Write-Host "Updated $updated locale files."
