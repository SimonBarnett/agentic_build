# FR #328: scheduled task keepalive for bob-{machine} irc_agent (user logon, like chair).
# Does NOT start live agents when -WhatIf. Operator runs without -WhatIf on the box.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MachineId,
    [string]$RepoRoot,
    [string]$TaskName,
    [switch]$StartNow,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$cfgPath = Join-Path $RepoRoot 'config\bobiverse.json'
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$nick = [string]$cfg.nicks.$MachineId
if (-not $nick) { $nick = 'bob-' + $MachineId }
if (-not $TaskName) { $TaskName = "BobIrcAgent-$MachineId" }

$ensure = Join-Path $RepoRoot 'tools\Ensure-BobIrcAgent.ps1'
if (-not (Test-Path -LiteralPath $ensure)) { throw "missing $ensure" }

$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("bob-irc-agent-{0}.log" -f $MachineId)

$ps = (Get-Command powershell.exe).Source
$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$ensure`" -MachineId $MachineId -RepoRoot `"$RepoRoot`" *>> `"$log`""

if ($WhatIf) {
    Write-Output "would register task $TaskName -> $ensure"
    exit 0
}

$action = New-ScheduledTaskAction -Execute $ps -Argument $arg
$trigger = @(
    (New-ScheduledTaskTrigger -AtLogOn),
    (New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 9999))
)
$user = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Output "registered $TaskName for $nick"
if ($StartNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Output "started $TaskName"
}
