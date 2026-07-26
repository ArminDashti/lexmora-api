# Redirect to .armin/docker-scripts (see run-on-docker-server.yaml for settings).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '.armin\docker-scripts\run-on-docker-server.ps1')
exit $LASTEXITCODE
