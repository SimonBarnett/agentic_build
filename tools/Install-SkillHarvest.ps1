# Hourly logon-user task: enqueue harvest-agent-skills. Not a Windows service.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ReplyChannel = 'Bob'
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

$harvest = Join-Path $RepoRoot 'tools\Harvest-AgentSkills.ps1'
if (-not (Test-Path $harvest)) { throw "missing $harvest" }

$mid = $env:BOB_MACHINE_ID
if (-not $mid) {
    $mj = Join-Path $env:USERPROFILE '.grok\bob-bridge\machine.json'
    if (Test-Path $mj) { $mid = [string]((Get-Content $mj -Raw | ConvertFrom-Json).id) }
}
if (-not $mid) { $mid = 'ionos' }

$ps = (Get-Command powershell.exe).Source
$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$harvest`" -RepoRoot `"$RepoRoot`" -ReplyChannel `"$ReplyChannel`""
$action = New-ScheduledTaskAction -Execute $ps -Argument $arg -WorkingDirectory $RepoRoot
$start = (Get-Date).Date.AddHours((Get-Date).Hour + 1)
$trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::FromDays(3650))
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
$taskName = "BobSkillHarvest-$mid"
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Task:    $taskName (hourly from $start, not a Windows service)"
Write-Host "Once:    powershell -NoProfile -File `"$harvest`" -RepoRoot `"$RepoRoot`""
