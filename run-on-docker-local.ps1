# Redirect to .armin/docker-scripts (see run-on-docker-local.yaml for settings).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '.armin\docker-scripts\run-on-docker-local.ps1')
exit $LASTEXITCODE
