<#
.SYNOPSIS
    Build and run the lexmora API stack on the local Docker daemon.

.DESCRIPTION
    Reads settings from run-on-docker-local.yaml. Uses Dockerfile and
    docker-compose.yml in this folder (build context is the repo root).

.EXAMPLE
    .\run-on-docker-local.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $deployDir = $PSScriptRoot
    $projectRoot = (Resolve-Path (Join-Path $deployDir '..\..')).Path
    $config = ConvertFrom-SimpleYaml -Path (Join-Path $deployDir 'run-on-docker-local.yaml')

    $stackName = Get-ConfigString -Config $config -Key 'stack_name'
    $imageTag = Get-ConfigString -Config $config -Key 'image_tag'
    $composeFileName = Get-ConfigString -Config $config -Key 'compose_file' -Default 'docker-compose.yml'
    $dockerNetwork = Get-ConfigString -Config $config -Key 'docker_network'
    $publishPort = Get-ConfigString -Config $config -Key 'api_publish_port' -Default '8080'
    $removeVolumes = Test-Truthy -Value (Get-ConfigString -Config $config -Key 'delete_volume' -Default 'no')
    $removeImages = Test-Truthy -Value (Get-ConfigString -Config $config -Key 'delete_image' -Default 'no')

    if ([string]::IsNullOrWhiteSpace($stackName)) { throw 'stack_name is required in run-on-docker-local.yaml.' }
    if ([string]::IsNullOrWhiteSpace($imageTag)) { throw 'image_tag is required in run-on-docker-local.yaml.' }
    if ([string]::IsNullOrWhiteSpace($dockerNetwork)) { throw 'docker_network is required in run-on-docker-local.yaml.' }

    $composeFile = Join-Path $deployDir $composeFileName
    $publishComposeFile = Join-Path $deployDir 'docker-compose.publish.yml'
    $dockerfile = Join-Path $deployDir 'Dockerfile'
    if (-not (Test-Path -LiteralPath $composeFile)) { throw "Compose file not found: $composeFile" }
    if (-not (Test-Path -LiteralPath $dockerfile)) { throw "Dockerfile not found: $dockerfile" }
    $usePublishOverlay = -not [string]::IsNullOrWhiteSpace($publishPort)
    if ($usePublishOverlay -and -not (Test-Path -LiteralPath $publishComposeFile)) {
        throw "Publish compose file not found: $publishComposeFile"
    }

    Write-Host "Running local Docker stack '$stackName' (image: $imageTag)..." -ForegroundColor Cyan
    Write-Host "  deploy:  $deployDir" -ForegroundColor DarkGray
    Write-Host "  network: $dockerNetwork" -ForegroundColor DarkGray
    Write-Host "  publish: $publishPort" -ForegroundColor DarkGray
    Write-Host "  delete-volume=$removeVolumes  delete-image=$removeImages" -ForegroundColor DarkGray

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI is not available. Start Docker Desktop / daemon.'
    }

    Ensure-DockerNetwork -Name $dockerNetwork

    $env:DOCKER_NETWORK = $dockerNetwork
    $env:API_IMAGE_TAG = $imageTag
    $env:API_PUBLISH_PORT = $publishPort
    $jwt = Get-ConfigString -Config $config -Key 'jwt_secret'
    $cors = Get-ConfigString -Config $config -Key 'cors_origins'
    $user = Get-ConfigString -Config $config -Key 'default_username'
    $pass = Get-ConfigString -Config $config -Key 'default_password'
    if ($jwt) { $env:JWT_SECRET = $jwt }
    if ($cors) { $env:CORS_ORIGINS = $cors }
    if ($user) { $env:DEFAULT_USERNAME = $user }
    if ($pass) { $env:DEFAULT_PASSWORD = $pass }

    Push-Location $projectRoot
    try {
        $composeArgs = @('-p', $stackName, '-f', $composeFile)
        if ($usePublishOverlay) { $composeArgs += @('-f', $publishComposeFile) }
        $downArgs = @('compose') + $composeArgs + @('down', '--remove-orphans')
        if ($removeVolumes) { $downArgs += '-v' }
        & docker @downArgs 2>$null | Out-Null

        if ($removeImages) {
            Write-Host "Removing image $imageTag..." -ForegroundColor Yellow
            & docker rmi $imageTag 2>$null | Out-Null
        }

        Build-LocalDockerImage -ProjectRoot $projectRoot -DeployDir $deployDir -ImageTag $imageTag

        Write-Host 'Starting stack...' -ForegroundColor Cyan
        & docker compose @composeArgs up -d
        if ($LASTEXITCODE -ne 0) { throw "docker compose up failed (exit $LASTEXITCODE)" }
    }
    finally {
        Pop-Location
    }

    Write-Host "Stack is running on http://localhost:$publishPort" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
