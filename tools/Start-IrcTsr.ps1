# IRC TSR: irc_listen.py + AGENT_LOOP_WAKE_irc-tsr for Cursor notify_on_output.
[CmdletBinding()]
param(
    [string]$MachineId,
    [string]$IrcHome,
    [string]$IrcRoot
)

$ErrorActionPreference = 'Continue'
if (-not $MachineId) { $MachineId = $env:BOB_MACHINE_ID }
if (-not $MachineId) { throw 'MachineId required (set BOB_MACHINE_ID or pass -MachineId)' }
if (-not $IrcHome) {
    $IrcHome = Join-Path $env:USERPROFILE '.agentic-irc-cursor'
    if ($env:AGENTIC_IRC_CURSOR_HOME) { $IrcHome = $env:AGENTIC_IRC_CURSOR_HOME.Trim() }
}
if (-not $IrcRoot) {
    foreach ($c in @('C:\ai\agentic_irc', 'D:\ai\agentic_irc', 'C:\src\agentic_irc')) {
        if (Test-Path (Join-Path $c 'scripts\irc_listen.py')) { $IrcRoot = $c; break }
    }
}
if (-not $IrcRoot) { throw 'agentic_irc checkout not found' }

. (Join-Path $PSScriptRoot 'Irc-Tsr-Health.ps1')
. (Join-Path $PSScriptRoot 'Irc-Tsr-Coordinator.ps1')
# Shared parser: coordinator.pid may be a bare pid OR talk-seat key=value lines. Never fall back
# to this process's $PID (that made the runner nick differ from Watch-IrcTsr's -> restart loop).
[void](Initialize-IrcTsrCoordinatorPid -IrcHome $IrcHome -CoordinatorId $PID)
$nick = Get-IrcTsrCoordinatorNick -MachineId $MachineId -IrcHome $IrcHome

$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$pidFile = Join-Path $logDir "irc-tsr-$nick.pid"
$runner = Join-Path $PSScriptRoot 'Irc-Tsr-Runner.ps1'

if (Test-Path $pidFile) {
    try {
        $old = [int](Get-Content $pidFile -Raw).Trim()
        Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
    }
    catch { }
}
# Killing the runner leaves its irc_listen.py child alive (Windows has no
# process-group kill). Reap every listen for this home before the new runner.
$reaped = Stop-IrcTsrStaleListens -IrcHome $IrcHome -KeepRunnerPid 0
if ($reaped -gt 0) { Write-Output "IRC TSR: reaped $reaped stale irc_listen for $IrcHome" }

$p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner,
    '-IrcHome', $IrcHome, '-IrcRoot', $IrcRoot, '-Nick', $nick
)
Set-Content -Path $pidFile -Value $p.Id -NoNewline
Write-Output "IRC TSR: nick=$nick pid=$($p.Id) home=$IrcHome"
