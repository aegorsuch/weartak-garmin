[CmdletBinding()]
param([string]$Directory = (Join-Path (Split-Path -Parent $PSScriptRoot) "bin/ci"))

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "GarminRelease.psm1") -Force
if ($env:GITLAB_CI -ne "true" -or -not $env:CI_JOB_TOKEN) { throw "Publishing runs only in GitLab CI with its ephemeral job token." }
if (-not $env:GARMIN_GITHUB_RELEASE_TOKEN) { throw "Missing protected GARMIN_GITHUB_RELEASE_TOKEN; publishing is blocked." }
$context = @{
    Enabled = $env:GARMIN_PUBLISH_ENABLED; Protected = $env:CI_COMMIT_REF_PROTECTED
    Source = $env:CI_PIPELINE_SOURCE; Branch = $env:CI_COMMIT_BRANCH; DefaultBranch = $env:CI_DEFAULT_BRANCH
    ProjectId = $env:CI_PROJECT_ID; PipelineId = $env:CI_PIPELINE_ID; PipelineIid = $env:CI_PIPELINE_IID; JobId = $env:CI_JOB_ID
    ProjectUrl = $env:CI_PROJECT_URL; ApiUrl = $env:CI_API_V4_URL; Sha = $env:CI_COMMIT_SHA
}
if ($context.ProjectId -ne "6783" -or $context.ProjectUrl -cne "https://git.tak.gov/core/weartak-core/weartak-garmin" -or
    $context.ApiUrl -cne "https://git.tak.gov/api/v4") { throw "Publisher is restricted to the canonical Garmin project." }
[xml]$manifest = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) "manifest.xml")
$plan = New-GarminReleasePlan -Directory $Directory -Context $context -Products @($manifest.manifest.application.products.product | ForEach-Object { $_.id })
$request = {
    param($operation)
    $base = "https://api.github.com/repos/aegorsuch/weartak-garmin"
    $headers = @{Authorization = "Bearer $env:GARMIN_GITHUB_RELEASE_TOKEN"; Accept = "application/vnd.github+json"; "X-GitHub-Api-Version" = "2022-11-28"}
    if ($operation.ContainsKey("Target") -and $operation.Target -eq "gitlab") {
        $base = "$($context.ApiUrl)/projects/$($context.ProjectId)"
        $headers = @{"JOB-TOKEN" = $env:CI_JOB_TOKEN}
    } elseif ($operation.ContainsKey("Target") -and $operation.Target -eq "upload") {
        $base = "https://uploads.github.com/repos/aegorsuch/weartak-garmin"
    }
    if ($operation.ContainsKey("OutFile")) { $headers.Accept = "application/octet-stream" }
    $parameters = @{
        Uri = "$base$($operation.Path)"
        Method = $operation.Method; Headers = $headers
        UseBasicParsing = $true; MaximumRedirection = 0; ErrorAction = "Stop"; TimeoutSec = 120
    }
    if ($operation.ContainsKey("InFile")) { $parameters.InFile = $operation.InFile; $parameters.ContentType = "application/octet-stream" }
    if ($operation.ContainsKey("OutFile")) { $parameters.OutFile = $operation.OutFile; $parameters.PassThru = $true }
    if ($operation.ContainsKey("Body")) {
        $parameters.Body = [Text.Encoding]::UTF8.GetBytes(($operation.Body | ConvertTo-Json -Depth 10))
        $parameters.ContentType = "application/json"
    }
    try {
        $response = Invoke-WebRequest @parameters
    } catch {
        if ($operation.ContainsKey("AllowMissing") -and $operation.AllowMissing -and
            $_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }
        if ($operation.ContainsKey("OutFile") -and $_.Exception.Response -and
            [int]$_.Exception.Response.StatusCode -in 301, 302, 307) {
            $location = [uri]$_.Exception.Response.Headers.Location
            if ($location.Scheme -cne "https" -or $location.Host -notin @("release-assets.githubusercontent.com", "objects.githubusercontent.com") -or
                $location.UserInfo -or -not $location.IsDefaultPort) { throw "Untrusted asset download redirect." }
            # Signed asset redirects are followed without either service's credential.
            Invoke-WebRequest -Uri $location.AbsoluteUri -OutFile $operation.OutFile -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 120 -ErrorAction Stop
            return $true
        }
        throw
    }
    if ($operation.ContainsKey("OutFile") -or $operation.Method -in "PUT", "DELETE") { return $true }
    return ($response.Content | ConvertFrom-Json)
}
Invoke-GarminPublication -Plan $plan -Request $request
