# Redirect to .deploy/docker (see run-on-docker-local.yaml for settings).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '.deploy\docker\run-on-docker-local.ps1')
exit $LASTEXITCODE
