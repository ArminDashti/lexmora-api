<#
.SYNOPSIS
    Build locally and deploy the stack to a remote Docker host over SSH.

.DESCRIPTION
    Reads settings from run-on-docker-server.yaml (no CLI flags).
    YAML "ssh" must be "ssh <alias>" or "server-address@username@password".
    YAML "ssh_key" is required for alias mode (path to private key).

.EXAMPLE
    .\run-on-docker-server.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $deployDir = $PSScriptRoot
    $projectRoot = (Resolve-Path (Join-Path $deployDir '..\..')).Path
    $config = ConvertFrom-SimpleYaml -Path (Join-Path $deployDir 'run-on-docker-server.yaml')

    $stackName = Get-ConfigString -Config $config -Key 'stack_name'
    $imageTag = Get-ConfigString -Config $config -Key 'image_tag'
    $composeFileName = Get-ConfigString -Config $config -Key 'compose_file' -Default 'docker-compose.yml'
    $dockerNetwork = Get-ConfigString -Config $config -Key 'docker_network'
    $workDir = Get-ConfigString -Config $config -Key 'remote_work_dir'
    $sshValue = Get-ConfigString -Config $config -Key 'ssh'
    $sshKey = Get-ConfigString -Config $config -Key 'ssh_key'
    $publishPort = Get-ConfigString -Config $config -Key 'api_publish_port' -Default ''
    if ($null -eq $publishPort) { $publishPort = '' }
    $removeVolumes = Test-Truthy -Value (Get-ConfigString -Config $config -Key 'delete_volume' -Default 'no')
    $removeImages = Test-Truthy -Value (Get-ConfigString -Config $config -Key 'delete_image' -Default 'no')

    if ($config.ContainsKey('sync_items') -and $config['sync_items']) {
        $syncItems = @($config['sync_items'])
    }
    else {
        $syncItems = @('Dockerfile', 'docker-compose.yml')
    }

    $connection = Resolve-SshConnection -Ssh $sshValue -SshKey $sshKey

    if ([string]::IsNullOrWhiteSpace($stackName)) { throw 'stack_name is required in run-on-docker-server.yaml.' }
    if ([string]::IsNullOrWhiteSpace($imageTag)) { throw 'image_tag is required in run-on-docker-server.yaml.' }
    if ([string]::IsNullOrWhiteSpace($dockerNetwork)) { throw 'docker_network is required in run-on-docker-server.yaml.' }
    if ([string]::IsNullOrWhiteSpace($workDir)) { throw 'remote_work_dir is required in run-on-docker-server.yaml.' }

    $composeFile = Join-Path $deployDir $composeFileName
    $publishComposeFile = Join-Path $deployDir 'docker-compose.publish.yml'
    $dockerfile = Join-Path $deployDir 'Dockerfile'
    if (-not (Test-Path -LiteralPath $composeFile)) { throw "Compose file not found: $composeFile" }
    if (-not (Test-Path -LiteralPath $dockerfile)) { throw "Dockerfile not found: $dockerfile" }
    $usePublishOverlay = -not [string]::IsNullOrWhiteSpace($publishPort)
    if ($usePublishOverlay -and -not (Test-Path -LiteralPath $publishComposeFile)) {
        throw "Publish compose file not found: $publishComposeFile"
    }

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI is not available. Start Docker Desktop / daemon.'
    }
    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        throw 'SSH client is not available.'
    }
    if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
        throw 'SCP client is not available.'
    }

    Write-Host "Running remote Docker stack '$stackName' via $($connection.Display)..." -ForegroundColor Cyan
    Write-Host "  deploy:  $deployDir" -ForegroundColor DarkGray
    if ($connection.SshKey) {
        Write-Host "  ssh_key: $($connection.SshKey)" -ForegroundColor DarkGray
    }
    Write-Host "  workdir: $workDir" -ForegroundColor DarkGray
    Write-Host "  network: $dockerNetwork" -ForegroundColor DarkGray
    Write-Host "  image:   $imageTag" -ForegroundColor DarkGray
    Write-Host "  publish: $(if ($publishPort -eq '') { '(none)' } else { $publishPort })" -ForegroundColor DarkGray
    Write-Host "  delete-volume=$removeVolumes  delete-image=$removeImages" -ForegroundColor DarkGray

    Invoke-RemoteShell -Connection $connection -Command 'docker version --format "{{.Server.Version}}" >/dev/null'

    Transfer-DockerImageToRemote -Connection $connection -ProjectRoot $projectRoot `
        -DeployDir $deployDir -ImageTag $imageTag -StackName $stackName

    Write-Host "Syncing compose files to $workDir..." -ForegroundColor Cyan
    Sync-ItemsToRemote -Connection $connection -LocalRoot $deployDir -RemotePath $workDir -Items $syncItems

    $downFlag = if ($removeVolumes) { ' -v' } else { '' }
    $rmiCmd = if ($removeImages) {
        "docker rmi $imageTag 2>/dev/null || true"
    }
    else {
        'true'
    }

    $jwt = Get-ConfigString -Config $config -Key 'jwt_secret' -Default 'change-me-docker-dev-only'
    $cors = Get-ConfigString -Config $config -Key 'cors_origins' -Default ''
    $user = Get-ConfigString -Config $config -Key 'default_username' -Default ''
    $pass = Get-ConfigString -Config $config -Key 'default_password' -Default ''

    $publishComposeFileName = 'docker-compose.publish.yml'
    $composeFilesArg = if ($usePublishOverlay) {
        "-f $composeFileName -f $publishComposeFileName"
    }
    else {
        "-f $composeFileName"
    }

    $remoteScript = @"
set -e
cd '$workDir'
export DOCKER_NETWORK='$dockerNetwork'
export API_IMAGE_TAG='$imageTag'
export API_PUBLISH_PORT='$publishPort'
export JWT_SECRET='$jwt'
export CORS_ORIGINS='$cors'
export DEFAULT_USERNAME='$user'
export DEFAULT_PASSWORD='$pass'
docker network inspect '$dockerNetwork' >/dev/null 2>&1 || docker network create '$dockerNetwork'
docker compose -p $stackName $composeFilesArg down --remove-orphans$downFlag 2>/dev/null || true
$rmiCmd
docker compose -p $stackName $composeFilesArg up -d
echo REMOTE_OK
"@

    $remoteScript = $remoteScript -replace "`r`n", "`n"
    Write-Host 'Starting compose on remote host...' -ForegroundColor Cyan
    $exitCode = Invoke-SshProcess -Connection $connection -Binary 'ssh' -Arguments @('bash', '-s') -StdIn $remoteScript
    if ($exitCode -ne 0) { throw "Remote deploy failed (exit $exitCode)" }

    Write-Host "Stack is running on remote host at $workDir" -ForegroundColor Green
    Write-Host ("Image was built locally and deployed to {0} without a remote build." -f $connection.Display) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
