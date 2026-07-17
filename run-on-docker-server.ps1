<#
.SYNOPSIS
    Deploy lexmora (API + postgres) on a remote Docker host over SSH.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$ComposeFileName = 'docker-compose.yml'
$ImageName = 'lexmora-api'
$ImageTag = 'latest'
$StackName = 'lexmora'
$NetworkNameDefault = 't3-net'
$RemoteProjectDir = '/cloud-admin/docker/lexmora'

function Write-Color([string]$Message, [string]$Color = 'White') {
    Write-Host $Message -ForegroundColor $Color
}

function Show-Help {
    @"
run-on-docker-server.ps1 - deploy $StackName on remote Docker over SSH

USAGE:
  .\run-on-docker-server.ps1 --ssh-string=<alias> [flags]

FLAGS:
  --ssh-string=<alias>       SSH config alias (required)
  --delete-image=<no|yes>    Remove built images during teardown (default: no)
  --delete-volume=<no|yes>   Remove volumes before recreate (default: no)
  --network-name=<name>      Docker network (default: t3-net)
  --help                     Show this help

EXAMPLES:
  .\run-on-docker-server.ps1 --ssh-string=t3
"@ | Write-Host
}

function Get-FlagValue {
    param([string[]]$ArgList, [string]$Name)
    foreach ($a in $ArgList) {
        if ($a -match "^--$Name=(.*)$") { return $Matches[1] }
    }
    return $null
}

function Test-Truthy([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return @('yes', 'true', '1', 'y', 'on') -contains $Value.ToLowerInvariant()
}

function Invoke-Remote {
    param([string]$Alias, [string]$RemoteCommand)
    & ssh $Alias $RemoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Remote command failed on $Alias (exit $LASTEXITCODE): $RemoteCommand"
    }
}

if ($args -match '^(--help|-h|/\?)$') { Show-Help; exit 0 }

try {
    $SshString = Get-FlagValue -ArgList $args -Name 'ssh-string'
    $DeleteImage = Get-FlagValue -ArgList $args -Name 'delete-image'
    $DeleteVolume = Get-FlagValue -ArgList $args -Name 'delete-volume'
    $NetworkName = Get-FlagValue -ArgList $args -Name 'network-name'

    if ([string]::IsNullOrWhiteSpace($SshString)) {
        throw '--ssh-string is required.'
    }
    if ($SshString -match '^\s*ssh\s+') {
        throw '--ssh-string must be an SSH config alias only.'
    }

    $doDeleteImage = Test-Truthy $DeleteImage
    $doDeleteVolume = Test-Truthy $DeleteVolume
    if ([string]::IsNullOrWhiteSpace($NetworkName)) { $NetworkName = $NetworkNameDefault }

    Write-Color "==> Remote deploy: $StackName via SSH alias '$SshString'" 'Cyan'
    Write-Color "    network: $NetworkName" 'DarkGray'

    Invoke-Remote -Alias $SshString -RemoteCommand 'docker version --format "{{.Server.Version}}" >/dev/null'
    Invoke-Remote -Alias $SshString -RemoteCommand "sudo mkdir -p '$RemoteProjectDir' '$RemoteProjectDir/.docker' && sudo chown -R `$(whoami):`$(whoami) '$RemoteProjectDir'"

    foreach ($item in @('Dockerfile', 'docker-compose.yml', 'go.mod', 'go.sum', 'cmd', 'internal', 'migrations', '.docker')) {
        $src = Join-Path $ScriptDir $item
        if (Test-Path -LiteralPath $src) {
            & scp -r $src "${SshString}:${RemoteProjectDir}/"
            if ($LASTEXITCODE -ne 0) { throw "scp failed for $item" }
        }
    }

    # Also copy source tree pieces required for build
    foreach ($item in @('cmd', 'internal', 'migrations')) {
        $src = Join-Path $ScriptDir $item
        if (Test-Path -LiteralPath $src) {
            & scp -r $src "${SshString}:${RemoteProjectDir}/"
        }
    }

    $deleteImageCmd = if ($doDeleteImage) { "docker rmi ${ImageName}:${ImageTag} 2>/dev/null || true" } else { 'true' }
    $deleteVolumeCmd = if ($doDeleteVolume) {
        "docker volume rm lexmora-pgsql-vol lexmora-api-vol 2>/dev/null || true"
    } else { 'true' }

    $remoteScript = @"
set -e
cd '$RemoteProjectDir'
export DOCKER_NETWORK='$NetworkName'
export API_IMAGE_TAG='${ImageName}:${ImageTag}'
export API_PUBLISH_PORT=''
docker network inspect '$NetworkName' >/dev/null 2>&1 || docker network create '$NetworkName'
docker compose -p $StackName -f $ComposeFileName down --remove-orphans 2>/dev/null || true
$deleteImageCmd
$deleteVolumeCmd
docker build -t ${ImageName}:${ImageTag} -f Dockerfile .
docker compose -p $StackName -f $ComposeFileName up -d
echo REMOTE_OK
"@

    $remoteScript = $remoteScript -replace "`r`n", "`n"
    Write-Color '==> Building and starting on remote' 'Cyan'
    $remoteScript | & ssh $SshString 'bash -s'
    if ($LASTEXITCODE -ne 0) { throw "Remote deploy failed (exit $LASTEXITCODE)" }

    Write-Color '==> Deploy complete' 'Green'
    Write-Color "    Stack:   $StackName" 'Green'
    Write-Color "    Network: $NetworkName" 'Green'
    Write-Color "    Remote:  $RemoteProjectDir" 'Green'
    exit 0
}
catch {
    Write-Color "ERROR: $($_.Exception.Message)" 'Red'
    Show-Help
    exit 1
}
