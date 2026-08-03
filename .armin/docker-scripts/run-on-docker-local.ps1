#Requires -Version 5.1
<#
.SYNOPSIS
  Deploy stack to the local host over Docker daemon using sibling YAML only.

.DESCRIPTION
  Local deploy script for .armin/docker-scripts/run-on-docker-local.yaml
  - No CLI arguments
  - Copies nothing; builds image locally and runs `docker compose up -d`

.CONFIG
  Sibling file: run-on-docker-local.yaml

  stack_name
  image_tag
  compose_file        Compose path relative to .armin/docker-scripts
  dockerfile          Dockerfile path relative to .armin/docker-scripts
  docker_network      External Docker network name
  internal_port       Optional (kept for compatibility; unused by this repo's compose)
  delete_volume       yes/true/1/y/on → remove volumes before up
  delete_image        yes/true/1/y/on → remove image during teardown

  This script sets env vars expected by your `docker-compose.yml`:
    - IMAGE_TAG
    - DOCKER_NETWORK
    - INTERNAL_PORT (when set)
    - PUBLISH_PORT (when publish_port is set; uses docker-compose.publish.yml)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DeployDir = $PSScriptRoot
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $DeployDir '../..'))
$ConfigPath = Join-Path $DeployDir 'run-on-docker-local.yaml'

function Write-Step([string]$Message) {
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "OK  $Message" -ForegroundColor Green
}

function Write-Fail([string]$Message) {
    Write-Host "ERR $Message" -ForegroundColor Red
}

function Show-Help {
    Write-Host @"
run-on-docker-local.ps1 — local Docker deploy (YAML-only)

USAGE:
  .\.armin\docker-scripts\run-on-docker-local.ps1

CONFIG:
  Sibling file: run-on-docker-local.yaml

  stack_name
  image_tag
  compose_file
  dockerfile
  docker_network
  publish_port        Host bind port; requires docker-compose.publish.yml
  internal_port       Optional (kept for compatibility)
  delete_volume
  delete_image

NOTES:
  - No CLI -- flags. Edit run-on-docker-local.yaml instead.
  - Sets IMAGE_TAG, DOCKER_NETWORK, INTERNAL_PORT, PUBLISH_PORT for docker-compose.
"@ -ForegroundColor Cyan
}

function Test-Truthy([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value.Trim().ToLowerInvariant() -in @('yes', 'true', '1', 'y', 'on')
}

function Test-Placeholder([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return $Value -match '<[^>]+>'
}

function Read-FlatYaml([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing config: $Path"
    }

    $map = @{}
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -match '^\s*-') { continue }
        if ($line -notmatch '^(?<key>[^:#]+):\s*(?<val>.*)$') { continue }
        $key = $Matches['key'].Trim()
        $val = $Matches['val'].Trim()
        if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $map[$key] = $val
    }
    return $map
}

function Require-Key($Map, [string]$Key) {
    if (-not $Map.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace([string]$Map[$Key])) {
        throw "YAML missing required key: $Key"
    }
    return [string]$Map[$Key]
}

function Resolve-DeployPath([string]$RelativePath) {
    $candidate = Join-Path $DeployDir $RelativePath
    $fullPath = [System.IO.Path]::GetFullPath($candidate)
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Path not found: $fullPath"
    }
    return $fullPath
}

function Ensure-Docker {
    docker version *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Docker CLI is not available. Start Docker Desktop / daemon.' }
}

function Ensure-Network([string]$NetworkName) {
    # docker writes "network not found" to stderr; suppress it so we can fallback to create.
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & docker network inspect $NetworkName *> $null
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Step "Creating network $NetworkName"
        & docker network create $NetworkName *> $null
        if ($LASTEXITCODE -ne 0) { throw "Failed to create network $NetworkName" }
    }
}

if ($args.Count -gt 0) {
    Write-Fail 'This script accepts no CLI arguments. Edit run-on-docker-local.yaml instead.'
    Show-Help
    exit 1
}

try {
    $cfg = Read-FlatYaml $ConfigPath

    $stackName = Require-Key $cfg 'stack_name'
    $imageTag = Require-Key $cfg 'image_tag'
    $composeFileRel = Require-Key $cfg 'compose_file'
    $dockerfileRel = Require-Key $cfg 'dockerfile'
    $network = Require-Key $cfg 'docker_network'

    $internalPort = if ($cfg.ContainsKey('internal_port')) { [string]$cfg['internal_port'] } else { '' }
    $publishPort = if ($cfg.ContainsKey('publish_port')) { [string]$cfg['publish_port'] } else { '' }
    $deleteVolume = Test-Truthy ($(if ($cfg.ContainsKey('delete_volume')) { [string]$cfg['delete_volume'] } else { 'no' }))
    $deleteImage = Test-Truthy ($(if ($cfg.ContainsKey('delete_image')) { [string]$cfg['delete_image'] } else { 'no' }))

    if (Test-Placeholder $composeFileRel) { throw 'compose_file is still a placeholder.' }
    if (Test-Placeholder $dockerfileRel) { throw 'dockerfile is still a placeholder.' }
    if (Test-Placeholder $stackName) { throw 'stack_name is still a placeholder.' }
    if (Test-Placeholder $imageTag) { throw 'image_tag is still a placeholder.' }

    $composePath = Resolve-DeployPath $composeFileRel
    $dockerfile = Resolve-DeployPath $dockerfileRel
    $composeDir = Split-Path -Parent $composePath
    $publishComposePath = Join-Path $composeDir 'docker-compose.publish.yml'
    $usePublishOverlay = -not [string]::IsNullOrWhiteSpace($publishPort)
    if ($usePublishOverlay -and -not (Test-Path -LiteralPath $publishComposePath)) {
        throw "publish_port is set but overlay missing: $publishComposePath"
    }

    Write-Step "Stack=$stackName image=$imageTag network=$network publish_port='$publishPort' internal_port='$internalPort' delete_volume=$deleteVolume delete_image=$deleteImage"

    Ensure-Docker
    Ensure-Network $network

    $composeArgs = @('-p', $stackName, '-f', $composePath)
    if ($usePublishOverlay) {
        $composeArgs += @('-f', $publishComposePath)
    }
    $composeArgs += @('--project-directory', $RepoRoot)

    if ($deleteVolume -or $deleteImage) {
        Write-Step 'Stopping existing stack'
        if ($deleteVolume) {
            docker compose @composeArgs down -v
        }
        else {
            docker compose @composeArgs down
        }
    }

    if ($deleteImage) {
        Write-Step "Removing local image $imageTag"
        $oldEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            docker image rm -f $imageTag *> $null
        }
        finally {
            $ErrorActionPreference = $oldEap
        }
    }

    Write-Step "Building image $imageTag"
    docker build -f $dockerfile -t $imageTag $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }

    Write-Step 'Starting stack'
    $oldImageTag = $env:IMAGE_TAG
    $oldDockerNetwork = $env:DOCKER_NETWORK
    $oldInternalPort = $env:INTERNAL_PORT
    $oldPublishPort = $env:PUBLISH_PORT
    $env:IMAGE_TAG = $imageTag
    $env:DOCKER_NETWORK = $network
    if (-not [string]::IsNullOrWhiteSpace($internalPort)) { $env:INTERNAL_PORT = $internalPort }
    if ($usePublishOverlay) {
        $env:PUBLISH_PORT = $publishPort
    }
    else {
        Remove-Item Env:PUBLISH_PORT -ErrorAction SilentlyContinue
    }
    try {
        docker compose @composeArgs up -d
        if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed' }
    }
    finally {
        if ($null -ne $oldImageTag) { $env:IMAGE_TAG = $oldImageTag } else { Remove-Item Env:IMAGE_TAG -ErrorAction SilentlyContinue }
        if ($null -ne $oldDockerNetwork) { $env:DOCKER_NETWORK = $oldDockerNetwork } else { Remove-Item Env:DOCKER_NETWORK -ErrorAction SilentlyContinue }
        if ($null -ne $oldInternalPort) { $env:INTERNAL_PORT = $oldInternalPort } else { Remove-Item Env:INTERNAL_PORT -ErrorAction SilentlyContinue }
        if ($null -ne $oldPublishPort) { $env:PUBLISH_PORT = $oldPublishPort } else { Remove-Item Env:PUBLISH_PORT -ErrorAction SilentlyContinue }
    }

    Write-Ok 'Deploy complete'
    if ($usePublishOverlay) {
        Write-Host "URL: http://localhost:$publishPort" -ForegroundColor Green
    }
    else {
        Write-Host 'URL: (no host publish; use Docker network DNS)' -ForegroundColor Green
    }
}
catch {
    Write-Fail $_.Exception.Message
    Show-Help
    exit 1
}

