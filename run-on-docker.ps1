<#
.SYNOPSIS
    Local/remote engine stub — prefer run-on-docker-server.ps1 for remote deploy.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Use .\run-on-docker-server.ps1 --ssh-string=<alias> for remote deploy of lexmora.' -ForegroundColor Cyan
Write-Host 'Local: docker network create t3-net 2>$null; docker compose -p lexmora up -d --build' -ForegroundColor Cyan
