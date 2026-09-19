# Register this Windows logon as a fleet machine. No SCM service.
# Copies the grok-build-fleet skill into ~/.grok/skills so Grok Bot / grok.exe on this box can load it.
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

$skillSrc = Join-Path $RepoRoot '.grok\skills\grok-build-fleet\SKILL.md'
$skillDstDir = Join-Path $env:USERPROFILE '.grok\skills\grok-build-fleet'
if (Test-Path $skillSrc) {
    New-Item -ItemType Directory -Force -Path $skillDstDir | Out-Null
    Copy-Item $skillSrc (Join-Path $skillDstDir 'SKILL.md') -Force
}

$watch = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
$ps = (Get-Command powershell.exe).Source
$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$watch`""
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

Write-Host "Machine:     $($rec.id) ($($rec.hostname) $($rec.windowsUser))"
Write-Host "MSSQL:       integrated (this Windows logon)"
Write-Host "Bridge home: $BridgeHome"
Write-Host "Skill:       $skillDstDir"
Write-Host "Task:        $taskName (AtLogOn + demand start, not a Windows service; $started)"
Write-Host "Once:        powershell -NoProfile -File `"$watch`" -Once"
