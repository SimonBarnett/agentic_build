# Register this Windows logon as a fleet machine. No SCM service.
# Copies .grok/skills/*/SKILL.md into ~/.grok/skills so Grok Bot / grok.exe on this box can load them.
# Safe to re-run on a live box (see tools\BobInstallHelpers.ps1):
# - never starts a second tray or ear (single-instance rule from #318: keep oldest)
# - GrokTalk / IrcTsr / CursorIrc watcher tasks only when meant for this machine
#   (tools\_Watch-<Name>-<machine>.ps1 exists) or opted in with -Watchers <Name>
# - non-secret User env only; an existing different value is kept unless -UpdateUserEnv;
#   secrets are never persisted (session-only rule). Prints each env var before/after.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MachineId,
    [string]$RepoRoot,
    [string[]]$CwdRoots,
    [string]$BridgeHome,
    [ValidateSet('GrokTalk', 'IrcTsr', 'CursorIrc')]
    [string[]]$Watchers = @(),
    [switch]$UpdateUserEnv
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
. (Join-Path $RepoRoot 'tools\BobInstallHelpers.ps1')

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
    [void](Set-BobInstallUserEnv -Name 'BOB_GROK_EXE' -Value $grok -Update:$UpdateUserEnv)
}
[void](Set-BobInstallUserEnv -Name 'BOB_BRIDGE_HOME' -Value $BridgeHome -Update:$UpdateUserEnv)
[void](Set-BobInstallUserEnv -Name 'BOB_MACHINE_ID' -Value $rec.id -Update:$UpdateUserEnv)

$copied = @()
$skillDstRoot = Join-Path $env:USERPROFILE '.grok\skills'
try {
    Import-Module (Join-Path $RepoRoot 'src\BobBridge.psd1') -Force
    $copied = @(Copy-BobProjectSkills)
}
catch {
    $skillRoot = Join-Path $RepoRoot '.grok\skills'
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
$trayRegNote = ''
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
}
catch {
    # e.g. Access is denied from a non-elevated shell: report it, do not pretend the task exists.
    $trayRegNote = ('task NOT registered ({0}); ' -f ([string]$_.Exception.Message).Trim())
}
# ONE tray: a running tray (task, wrapper or hand-started) is reused, never doubled.
$tray = Start-BobInstallTray -TaskName $taskName
$started = $trayRegNote + $tray.Status

$taskArgs = @{ MachineId = $rec.id; RepoRoot = $RepoRoot; Trigger = $trigger; Settings = $settings; Principal = $principal; PsExe = $ps }

# Ear: every fleet machine (generic wrapper is fine). If the tray was just started it starts / reuses
# the ear itself (#318), so only register the logon task here (starting both raced into two ears).
$bvTask = "_Watch-Bobiverse-$($rec.id)"
$bv = Install-BobWatcherTask -Name 'Bobiverse' -TaskName $bvTask -AllMachines -NoStart:($tray.Started) @taskArgs

# Opt-in watchers: only with a machine wrapper tools\_Watch-<Name>-<id>.ps1 or -Watchers <Name>.
$gtTask = "_Watch-GrokTalk-$($rec.id)"
$gt = Install-BobWatcherTask -Name 'GrokTalk' -TaskName $gtTask -OptIn:($Watchers -contains 'GrokTalk') @taskArgs
$tsTask = "_Watch-IrcTsr-$($rec.id)"
$ts = Install-BobWatcherTask -Name 'IrcTsr' -TaskName $tsTask -OptIn:($Watchers -contains 'IrcTsr') @taskArgs
$ciTask = "_Watch-CursorIrc-$($rec.id)"
$ci = Install-BobWatcherTask -Name 'CursorIrc' -TaskName $ciTask -OptIn:($Watchers -contains 'CursorIrc') @taskArgs

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
Write-Host "Bobiverse:   $bvTask -> $($bv.File) ($($bv.Status))"
Write-Host "Grok-talk:   $gtTask -> $($gt.File) ($($gt.Status))"
Write-Host "IRC TSR:     $tsTask -> $($ts.File) ($($ts.Status))"
Write-Host "Cursor IRC:  $ciTask -> $($ci.File) ($($ci.Status))"
Write-Host "Once:        powershell -NoProfile -File `"$(Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1')`" -Once"
Write-Host "Tray:        hidden NotifyIcon (flashes on ACTION_REQUIRED)"
Write-Host "Watch seat:  $watchDeployed (only way to create a build-worker seat)"
# FR #346: Desktop + Start Menu shortcuts to reopen systray (single instance)
$shortcutNote = 'skipped'
try {
    $re = Join-Path $RepoRoot 'tools\Invoke-BobFleetReinstall.ps1'
    if (Test-Path -LiteralPath $re) {
        $null = & (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File $re `
            -RepoRoot $RepoRoot -WhatIf:$false -SkipTools -SkipSkills -SkipRestart 2>&1
        # Install shortcuts only via helper function path
        . (Join-Path $RepoRoot 'tools\BobInstallHelpers.ps1') -ErrorAction SilentlyContinue
    }
    $instShort = Join-Path $RepoRoot 'tools\Install-BobFleetTrayShortcut.ps1'
    if (Test-Path -LiteralPath $instShort) {
        & $instShort -RepoRoot $RepoRoot | Out-Null
        $shortcutNote = 'Bob Fleet.lnk (Desktop + Start Menu)'
    }
    else {
        # inline minimal shortcut install
        $launcher = Join-Path $RepoRoot 'tools\Start-BobFleetTray.ps1'
        if (Test-Path -LiteralPath $launcher) {
            $desk = [Environment]::GetFolderPath('Desktop')
            $sm = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\Bob Fleet'
            New-Item -ItemType Directory -Force -Path $sm | Out-Null
            $psExe = (Get-Command powershell.exe).Source
            $w = New-Object -ComObject WScript.Shell
            foreach ($dir in @($desk, $sm)) {
                $lnk = Join-Path $dir 'Bob Fleet.lnk'
                $s = $w.CreateShortcut($lnk)
                $s.TargetPath = $psExe
                $s.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$launcher`""
                $s.WorkingDirectory = $RepoRoot
                $s.WindowStyle = 7
                $s.Description = 'Bob Fleet systray (single instance)'
                $s.Save()
            }
            $shortcutNote = 'Bob Fleet.lnk (Desktop + Start Menu)'
        }
    }
}
catch {
    $shortcutNote = 'shortcut install failed: ' + $_.Exception.Message
}
Write-Host "Shortcut:    $shortcutNote"
Write-BobInstallEnvReport 'Install-BobFleet'
$ircInst = Join-Path $RepoRoot 'tools\Install-BobIrc.ps1'
if (Test-Path $ircInst) {
    try {
        & $ircInst -MachineId $MachineId -RepoRoot $RepoRoot -UpdateUserEnv:$UpdateUserEnv
    }
    catch {
        Write-Host "Bobiverse:  skipped ($($_.Exception.Message))"
    }
}
