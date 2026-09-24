# Register this Windows logon as a fleet machine. No SCM service.
# Copies .grok/skills/*/SKILL.md into ~/.grok/skills so Grok Bot / grok.exe on this box can load them.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MachineId,
    [string]$RepoRoot,
    [string[]]$CwdRoots,
    [string]$BridgeHome
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

if (-not $BridgeHome) {
    if ($env:BOB_BRIDGE_HOME) { $BridgeHome = $env:BOB_BRIDGE_HOME }
    else { $BridgeHome = Join-Path $env:USERPROFILE '.grok\bob-bridge' }
}
$env:BOB_BRIDGE_HOME = $BridgeHome
$env:BOB_MACHINE_ID = $MachineId.ToLowerInvariant()

$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
Import-Module $psd1 -Force

if (-not $CwdRoots) { $CwdRoots = @($RepoRoot) }
$rec = Register-BobMachine -Id $MachineId -CwdRoots $CwdRoots

$grok = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
if (-not $env:BOB_GROK_EXE -and (Test-Path $grok)) {
    [Environment]::SetEnvironmentVariable('BOB_GROK_EXE', $grok, 'User')
    $env:BOB_GROK_EXE = $grok
}
[Environment]::SetEnvironmentVariable('BOB_BRIDGE_HOME', $BridgeHome, 'User')
[Environment]::SetEnvironmentVariable('BOB_MACHINE_ID', $rec.id, 'User')

$copied = @()
try {
    Import-Module (Join-Path $RepoRoot 'src\BobBridge.psd1') -Force
    $copied = @(Copy-BobProjectSkills)
}
catch {
    $skillRoot = Join-Path $RepoRoot '.grok\skills'
    $skillDstRoot = Join-Path $env:USERPROFILE '.grok\skills'
    if (Test-Path $skillRoot) {
        foreach ($dir in @(Get-ChildItem $skillRoot -Directory)) {
            $src = Join-Path $dir.FullName 'SKILL.md'
            if (-not (Test-Path $src)) { continue }
            $dstDir = Join-Path $skillDstRoot $dir.Name
            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
            Copy-Item $src (Join-Path $dstDir 'SKILL.md') -Force
            $copied += $dir.Name
        }
    }
}

$watch = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
$ps = (Get-Command powershell.exe).Source
$arg = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watch`""
$action = New-ScheduledTaskAction -Execute $ps -Argument $arg -WorkingDirectory $RepoRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
$taskName = "BobFleet-$($rec.id)"
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
try {
    Start-ScheduledTask -TaskName $taskName
    $started = 'started now'
}
catch {
    $started = "register-only (start failed: $($_.Exception.Message))"
}

$bvWrapId = Join-Path $RepoRoot ("tools\_Watch-Bobiverse-{0}.ps1" -f $rec.id)
$bvWrap = Join-Path $RepoRoot 'tools\_Watch-Bobiverse.ps1'
$bvInner = Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1'
$bvFile = $null
if (Test-Path $bvWrapId) { $bvFile = $bvWrapId }
elseif (Test-Path $bvWrap) { $bvFile = $bvWrap }
elseif (Test-Path $bvInner) { $bvFile = $bvInner }
$bvTask = "_Watch-Bobiverse-$($rec.id)"
$bvStarted = 'skipped (no wrapper script)'
if ($bvFile) {
    $bvArg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$bvFile`""
    $bvAction = New-ScheduledTaskAction -Execute $ps -Argument $bvArg -WorkingDirectory $RepoRoot
    Register-ScheduledTask -TaskName $bvTask -Action $bvAction -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    $ircAlready = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            ($_.CommandLine -match 'Watch-Bobiverse\.ps1' -or $_.CommandLine -match '_Watch-Bobiverse')
        })
    if ($ircAlready.Count -gt 0) {
        $bvStarted = 'already running (not started again)'
    }
    else {
        try {
            Start-ScheduledTask -TaskName $bvTask
            $bvStarted = 'started now'
        }
        catch {
            $bvStarted = "register-only (start failed: $($_.Exception.Message))"
        }
    }
}

$gtWrapId = Join-Path $RepoRoot ("tools\_Watch-GrokTalk-{0}.ps1" -f $rec.id)
$gtWrap = Join-Path $RepoRoot 'tools\_Watch-GrokTalk.ps1'
$gtInner = Join-Path $RepoRoot 'tools\Watch-GrokTalk.ps1'
$gtFile = $null
if (Test-Path $gtWrapId) { $gtFile = $gtWrapId }
elseif (Test-Path $gtWrap) { $gtFile = $gtWrap }
elseif (Test-Path $gtInner) { $gtFile = $gtInner }
$gtTask = "_Watch-GrokTalk-$($rec.id)"
$gtStarted = 'skipped (no wrapper script)'
if ($gtFile) {
    $gtArg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$gtFile`""
    $gtAction = New-ScheduledTaskAction -Execute $ps -Argument $gtArg -WorkingDirectory $RepoRoot
    Register-ScheduledTask -TaskName $gtTask -Action $gtAction -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    $gtAlready = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            ($_.CommandLine -match 'Watch-GrokTalk\.ps1' -or $_.CommandLine -match '_Watch-GrokTalk')
        })
    if ($gtAlready.Count -gt 0) {
        $gtStarted = 'already running (not started again)'
    }
    else {
        try {
            Start-ScheduledTask -TaskName $gtTask
            $gtStarted = 'started now'
        }
        catch {
            $gtStarted = "register-only (start failed: $($_.Exception.Message))"
        }
    }
}

$tsWrapId = Join-Path $RepoRoot ("tools\_Watch-IrcTsr-{0}.ps1" -f $rec.id)
$tsWrap = Join-Path $RepoRoot 'tools\_Watch-IrcTsr.ps1'
$tsInner = Join-Path $RepoRoot 'tools\Watch-IrcTsr.ps1'
$tsFile = $null
if (Test-Path $tsWrapId) { $tsFile = $tsWrapId }
elseif (Test-Path $tsWrap) { $tsFile = $tsWrap }
elseif (Test-Path $tsInner) { $tsFile = $tsInner }
$tsTask = "_Watch-IrcTsr-$($rec.id)"
$tsStarted = 'skipped (no wrapper script)'
if ($tsFile) {
    $tsArg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tsFile`""
    $tsAction = New-ScheduledTaskAction -Execute $ps -Argument $tsArg -WorkingDirectory $RepoRoot
    Register-ScheduledTask -TaskName $tsTask -Action $tsAction -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    $tsAlready = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            ($_.CommandLine -match 'Watch-IrcTsr\.ps1' -or $_.CommandLine -match '_Watch-IrcTsr')
        })
    if ($tsAlready.Count -gt 0) {
        $tsStarted = 'already running (not started again)'
    }
    else {
        try {
            Start-ScheduledTask -TaskName $tsTask
            $tsStarted = 'started now'
        }
        catch {
            $tsStarted = "register-only (start failed: $($_.Exception.Message))"
        }
    }
}

$ciWrapId = Join-Path $RepoRoot ("tools\_Watch-CursorIrc-{0}.ps1" -f $rec.id)
$ciWrap = Join-Path $RepoRoot 'tools\_Watch-CursorIrc.ps1'
$ciInner = Join-Path $RepoRoot 'tools\Watch-CursorIrc.ps1'
$ciFile = $null
if (Test-Path $ciWrapId) { $ciFile = $ciWrapId }
elseif (Test-Path $ciWrap) { $ciFile = $ciWrap }
elseif (Test-Path $ciInner) { $ciFile = $ciInner }
$ciTask = "_Watch-CursorIrc-$($rec.id)"
$ciStarted = 'skipped (no wrapper script)'
if ($ciFile) {
    $ciArg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ciFile`""
    $ciAction = New-ScheduledTaskAction -Execute $ps -Argument $ciArg -WorkingDirectory $RepoRoot
    Register-ScheduledTask -TaskName $ciTask -Action $ciAction -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    $ciAlready = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            ($_.CommandLine -match 'Watch-CursorIrc\.ps1' -or $_.CommandLine -match '_Watch-CursorIrc')
        })
    if ($ciAlready.Count -gt 0) {
        $ciStarted = 'already running (not started again)'
    }
    else {
        try {
            Start-ScheduledTask -TaskName $ciTask
            $ciStarted = 'started now'
        }
        catch {
            $ciStarted = "register-only (start failed: $($_.Exception.Message))"
        }
    }
}

$watchSrc = Join-Path $RepoRoot 'tools\Watch-AgentHealth'
$watchDst = Join-Path $env:USERPROFILE 'Desktop\Watch-AgentHealth'
$watchDeployed = 'skipped (no tools/Watch-AgentHealth)'
# Canonical watch seat = SimonBarnett/AgentMonitor clone (Install-AgentMonitor: fetch + reset).
# Never copy the fleet copy over that git clone: it pinned Desktop\Watch-AgentHealth to a stale
# fork without Ensure-WatchIrcSeat, so tray Agents > Grok/Cursor seats never joined IRC.
$amInstaller = Join-Path $RepoRoot 'tools\Install-AgentMonitor.ps1'
$amDeployed = $false
if (Test-Path -LiteralPath $amInstaller) {
    try {
        & $amInstaller -Agent both -DesktopDir (Split-Path -Parent $watchDst) | Out-Null
        $amDeployed = $true
        $watchDeployed = "$watchDst (AgentMonitor clone)"
    }
    catch {
        Write-Host "AgentMonitor: install failed ($($_.Exception.Message)); trying fleet copy"
    }
}
if (-not $amDeployed -and (Test-Path -LiteralPath $watchSrc) -and -not (Test-Path -LiteralPath (Join-Path $watchDst '.git'))) {
    New-Item -ItemType Directory -Force -Path $watchDst | Out-Null
    Copy-Item -Path (Join-Path $watchSrc '*') -Destination $watchDst -Recurse -Force
    $watchDeployed = "$watchDst (fleet copy)"
}

Write-Host "Machine:     $($rec.id) ($($rec.hostname) $($rec.windowsUser))"
Write-Host "MSSQL:       integrated (this Windows logon)"
Write-Host "Bridge home: $BridgeHome"
Write-Host "Skills:      $skillDstRoot ($($copied -join ', '))"
Write-Host "Task:        $taskName (AtLogOn + demand start, not a Windows service; $started)"
Write-Host "Bobiverse:   $bvTask -> $bvFile ($bvStarted)"
Write-Host "Grok-talk:   $gtTask -> $gtFile ($gtStarted)"
Write-Host "IRC TSR:     $tsTask -> $tsFile ($tsStarted)"
Write-Host "Cursor IRC:  $ciTask -> $ciFile ($ciStarted)"
Write-Host "Once:        powershell -NoProfile -File `"$(Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1')`" -Once"
Write-Host "Tray:        hidden NotifyIcon (flashes on ACTION_REQUIRED)"
Write-Host "Watch seat:  $watchDeployed (only way to create a build-worker seat)"
$ircInst = Join-Path $RepoRoot 'tools\Install-BobIrc.ps1'
if (Test-Path $ircInst) {
    try {
        & $ircInst -MachineId $MachineId -RepoRoot $RepoRoot
    }
    catch {
        Write-Host "Bobiverse:  skipped ($($_.Exception.Message))"
    }
}
