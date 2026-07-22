# Redirect to .deploy/docker (see run-on-docker-server.yaml for settings).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '.deploy\docker\run-on-docker-server.ps1')
exit $LASTEXITCODE
