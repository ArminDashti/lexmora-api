# Shared helpers for run-on-docker-local.ps1 / run-on-docker-server.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-SurroundingQuotes {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }

    $Value = $Value.Trim()
    if (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or ($Value.StartsWith("'") -and $Value.EndsWith("'"))) {
        return $Value.Substring(1, $Value.Length - 2).Trim()
    }
    return $Value
}

function ConvertFrom-SimpleYaml {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    $config = @{}
    $listKey = $null
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }

        if ($line -match '^\s+-\s+(?<item>.+)$') {
            if (-not $listKey) { throw "Orphan list item in YAML: $rawLine" }
            if ($null -eq $config[$listKey]) { $config[$listKey] = @() }
            $item = Remove-SurroundingQuotes -Value $Matches['item'].Trim()
            $config[$listKey] = @($config[$listKey]) + @($item)
            continue
        }

        if ($line -match '^(?<key>[\w-]+)\s*:\s*(?<value>.*)$') {
            $key = ($Matches['key'] -replace '-', '_').ToLowerInvariant()
            $value = $Matches['value'].Trim()
            if ($value -eq '' -or $value -eq '|' -or $value -eq '>') {
                $config[$key] = @()
                $listKey = $key
                continue
            }
            $listKey = $null
            $value = Remove-SurroundingQuotes -Value $value
            if ($value -eq '~' -or $value -eq 'null') { $value = $null }
            $config[$key] = $value
            continue
        }

        throw "Unsupported YAML line: $rawLine"
    }

    return $config
}

function Get-ConfigString {
    param(
        [hashtable]$Config,
        [string]$Key,
        [string]$Default = $null
    )

    if ($Config.ContainsKey($Key) -and $null -ne $Config[$Key] -and "$($Config[$Key])" -ne '') {
        return [string]$Config[$Key]
    }
    return $Default
}

function Test-Truthy {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    switch ($Value.ToLowerInvariant()) {
        { $_ -in @('yes', 'true', '1', 'y', 'on') } { return $true }
        default { return $false }
    }
}

function Ensure-DockerNetwork {
    param([string]$Name)

    $exists = & docker network ls --format '{{.Name}}' | Where-Object { $_ -eq $Name }
    if (-not $exists) {
        Write-Host "Creating Docker network '$Name'..." -ForegroundColor Cyan
        & docker network create $Name | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to create network '$Name'." }
    }
}

function Test-IsPlaceholder {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    if ($Value -match '[<>]') { return $true }
    if ($Value -match '(?i)^(change.?me|todo|fix\.me|your-.+|<.*>)$') { return $true }
    return $false
}

function Resolve-SshConnection {
    param(
        [string]$Ssh,
        [string]$SshKey
    )

    if (Test-IsPlaceholder -Value $Ssh) {
        throw 'YAML key "ssh" is a placeholder. Set it to "ssh <alias>" (real alias) or "server-address@username@password".'
    }

    $value = Remove-SurroundingQuotes -Value $Ssh.Trim()
    $keyPath = $null
    if (-not [string]::IsNullOrWhiteSpace($SshKey) -and -not (Test-IsPlaceholder -Value $SshKey)) {
        if (-not (Test-Path -LiteralPath $SshKey)) {
            throw "SSH key file not found: $SshKey"
        }
        $keyPath = (Resolve-Path -LiteralPath $SshKey).Path
    }

    if ($value -match '^(?i)ssh(?:\s+-p\s*(?<port1>\d+))?\s+(?<alias>\S+)(?:\s+-p\s*(?<port2>\d+))?$') {
        $alias = $Matches['alias']
        $port = $null
        if ($Matches['port1']) { $port = $Matches['port1'] }
        if ($Matches['port2']) { $port = $Matches['port2'] }
        if (Test-IsPlaceholder -Value $alias) {
            throw 'YAML key "ssh" still uses a placeholder alias. Replace <alias> with your SSH config Host name.'
        }
        if ([string]::IsNullOrWhiteSpace($keyPath)) {
            throw 'YAML key "ssh_key" is required for "ssh <alias>" mode. Set it to your private key path.'
        }
        $display = if ($port) { "ssh $alias -p $port" } else { "ssh $alias" }
        return [pscustomobject]@{
            Mode      = 'Alias'
            Display   = $display
            SshTarget = $alias
            Port      = $port
            Password  = $null
            SshKey    = $keyPath
        }
    }

    if ($value -match '^(?<host>[^@]+)@(?<user>[^@]+)@(?<password>.+)$') {
        $hostName = $Matches['host'].Trim()
        $userName = $Matches['user'].Trim()
        $password = $Matches['password']
        if (
            (Test-IsPlaceholder -Value $hostName) -or
            (Test-IsPlaceholder -Value $userName) -or
            (Test-IsPlaceholder -Value $password) -or
            [string]::IsNullOrWhiteSpace($hostName) -or
            [string]::IsNullOrWhiteSpace($userName) -or
            [string]::IsNullOrWhiteSpace($password)
        ) {
            throw 'Invalid ssh password form. Use server-address@username@password with real values (no placeholders).'
        }
        return [pscustomobject]@{
            Mode      = 'Password'
            Display   = "${userName}@${hostName}"
            SshTarget = "${userName}@${hostName}"
            Port      = $null
            Password  = $password
            SshKey    = $keyPath
        }
    }

    throw 'Invalid ssh value. Use "ssh <alias> [-p <port>]" or "server-address@username@password".'
}

function New-SshAskPassFile {
    param([string]$Password)

    $id = [guid]::NewGuid().ToString('N')
    $ps1Path = Join-Path $env:TEMP ("docker-deploy-askpass-{0}.ps1" -f $id)
    $cmdPath = Join-Path $env:TEMP ("docker-deploy-askpass-{0}.cmd" -f $id)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Password))

    $ps1 = @'
$b64 = '{0}'
[Console]::Out.Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)))
'@ -f $encoded
    Set-Content -LiteralPath $ps1Path -Value $ps1 -Encoding UTF8

    $cmd = '@echo off' + "`r`n" + 'powershell -NoProfile -File "' + $ps1Path + '"'
    Set-Content -LiteralPath $cmdPath -Value $cmd -Encoding ASCII

    return [pscustomobject]@{
        CmdPath = $cmdPath
        Ps1Path = $ps1Path
    }
}

function Invoke-SshProcess {
    param(
        [pscustomobject]$Connection,
        [string]$Binary,
        [string[]]$Arguments,
        [string]$StdIn = $null
    )

    $commonOpts = @('-o', 'StrictHostKeyChecking=accept-new')
    $askPassFiles = $null
    $prevAskPass = $env:SSH_ASKPASS
    $prevAskPassRequire = $env:SSH_ASKPASS_REQUIRE
    $prevDisplay = $env:DISPLAY

    try {
        if ($Connection.Mode -eq 'Alias') {
            $identityArgs = @()
            if ($Connection.SshKey) {
                $identityArgs = @('-i', $Connection.SshKey, '-o', 'IdentitiesOnly=yes')
            }
            $portArgs = @()
            if (-not [string]::IsNullOrWhiteSpace([string]$Connection.Port)) {
                if ($Binary -eq 'scp') {
                    $portArgs = @('-P', [string]$Connection.Port)
                }
                else {
                    $portArgs = @('-p', [string]$Connection.Port)
                }
            }
            $allArgs = $commonOpts + $identityArgs + $portArgs + @($Connection.SshTarget) + $Arguments
            if ($null -ne $StdIn) {
                $StdIn | & $Binary @allArgs
            }
            else {
                & $Binary @allArgs
            }
        }
        elseif ($Connection.Mode -eq 'Password') {
            if (Get-Command sshpass -ErrorAction SilentlyContinue) {
                $allArgs = @('-p', $Connection.Password, $Binary) + $commonOpts + @(
                    '-o', 'PreferredAuthentications=password',
                    '-o', 'PubkeyAuthentication=no',
                    $Connection.SshTarget
                ) + $Arguments
                if ($null -ne $StdIn) {
                    $StdIn | & sshpass @allArgs
                }
                else {
                    & sshpass @allArgs
                }
            }
            else {
                $askPassFiles = New-SshAskPassFile -Password $Connection.Password
                $env:SSH_ASKPASS = $askPassFiles.CmdPath
                $env:SSH_ASKPASS_REQUIRE = 'force'
                if ([string]::IsNullOrWhiteSpace($env:DISPLAY)) { $env:DISPLAY = '1' }
                $allArgs = $commonOpts + @(
                    '-o', 'PreferredAuthentications=password',
                    '-o', 'PubkeyAuthentication=no',
                    '-o', 'NumberOfPasswordPrompts=1',
                    $Connection.SshTarget
                ) + $Arguments
                if ($null -ne $StdIn) {
                    $StdIn | & $Binary @allArgs
                }
                else {
                    & $Binary @allArgs
                }
            }
        }
        else {
            throw "Unknown SSH mode: $($Connection.Mode)"
        }

        return $LASTEXITCODE
    }
    finally {
        if ($null -ne $prevAskPass) { $env:SSH_ASKPASS = $prevAskPass } else { Remove-Item Env:SSH_ASKPASS -ErrorAction SilentlyContinue }
        if ($null -ne $prevAskPassRequire) { $env:SSH_ASKPASS_REQUIRE = $prevAskPassRequire } else { Remove-Item Env:SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue }
        if ($null -ne $prevDisplay) { $env:DISPLAY = $prevDisplay } else { Remove-Item Env:DISPLAY -ErrorAction SilentlyContinue }
        if ($askPassFiles) {
            foreach ($p in @($askPassFiles.CmdPath, $askPassFiles.Ps1Path)) {
                if ($p -and (Test-Path -LiteralPath $p)) {
                    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

function Invoke-RemoteShell {
    param(
        [pscustomobject]$Connection,
        [string]$Command
    )

    $exitCode = Invoke-SshProcess -Connection $Connection -Binary 'ssh' -Arguments @($Command)
    if ($exitCode -ne 0) { throw "Remote command failed (exit $exitCode): $Command" }
}

function Sync-ItemsToRemote {
    param(
        [pscustomobject]$Connection,
        [string]$LocalRoot,
        [string]$RemotePath,
        [string[]]$Items
    )

    $exitCode = Invoke-SshProcess -Connection $Connection -Binary 'ssh' -Arguments @("mkdir -p '$RemotePath'")
    if ($exitCode -ne 0) { throw "Failed to create remote directory: $RemotePath" }

    foreach ($item in @($Items)) {
        $src = Join-Path $LocalRoot $item
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "Skipping missing sync item: $item" -ForegroundColor DarkYellow
            continue
        }
        $exitCode = Invoke-SshProcess -Connection $Connection -Binary 'scp' -Arguments @(
            '-r', $src, "$($Connection.SshTarget):$RemotePath/"
        )
        if ($exitCode -ne 0) { throw "Failed to copy '$item'." }
    }
}

function Build-LocalDockerImage {
    param(
        [string]$ProjectRoot,
        [string]$DeployDir,
        [string]$ImageTag
    )

    $dockerfile = Join-Path $DeployDir 'Dockerfile'
    if (-not (Test-Path -LiteralPath $dockerfile)) {
        throw "Dockerfile not found: $dockerfile"
    }

    Write-Host "Building image '$ImageTag' on this machine..." -ForegroundColor Cyan
    & docker build -f $dockerfile -t $ImageTag $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw "docker build failed (exit $LASTEXITCODE)" }
    Write-Host 'Image build complete.' -ForegroundColor Green
}

function Transfer-DockerImageToRemote {
    param(
        [pscustomobject]$Connection,
        [string]$ProjectRoot,
        [string]$DeployDir,
        [string]$ImageTag,
        [string]$StackName
    )

    $localTar = Join-Path $env:TEMP "$StackName-docker-image.tar"
    $remoteTar = "/tmp/$StackName-docker-image.tar"

    try {
        Build-LocalDockerImage -ProjectRoot $ProjectRoot -DeployDir $DeployDir -ImageTag $ImageTag

        Write-Host 'Saving image to tarball...' -ForegroundColor Cyan
        if (Test-Path -LiteralPath $localTar) { Remove-Item -LiteralPath $localTar -Force }
        & docker save -o $localTar $ImageTag
        if ($LASTEXITCODE -ne 0) { throw "docker save failed (exit $LASTEXITCODE)" }

        $tarSizeMb = [math]::Round((Get-Item -LiteralPath $localTar).Length / 1MB, 1)
        Write-Host "Transferring image ($tarSizeMb MB) to remote host..." -ForegroundColor Cyan
        $exitCode = Invoke-SshProcess -Connection $Connection -Binary 'scp' -Arguments @(
            $localTar, "$($Connection.SshTarget):$remoteTar"
        )
        if ($exitCode -ne 0) { throw 'Failed to copy image tarball to remote.' }

        Write-Host 'Loading image on remote host...' -ForegroundColor Cyan
        Invoke-RemoteShell -Connection $Connection -Command "docker load -i '$remoteTar' && rm -f '$remoteTar'"
        Write-Host 'Image loaded on remote host.' -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $localTar) {
            Remove-Item -LiteralPath $localTar -Force -ErrorAction SilentlyContinue
        }
    }
}
