# IRC TSR: irc_listen.py + AGENT_LOOP_WAKE_irc-tsr for Cursor notify_on_output.
[CmdletBinding()]
param(
    [string]$MachineId,
    [string]$IrcHome,
    [string]$IrcRoot
)

$ErrorActionPreference = 'Continue'
if (-not $MachineId) { $MachineId = $env:BOB_MACHINE_ID }
if (-not $MachineId) { $MachineId = 'ionos' }
$nick = "cursor-$MachineId"
if (-not $IrcHome) {
    $IrcHome = Join-Path $env:USERPROFILE '.agentic-irc-cursor'
    if ($env:AGENTIC_IRC_CURSOR_HOME) { $IrcHome = $env:AGENTIC_IRC_CURSOR_HOME.Trim() }
}
if (-not $IrcRoot) {
    foreach ($c in @('C:\ai\agentic_irc', 'D:\ai\agentic_irc')) {
        if (Test-Path (Join-Path $c 'scripts\irc_listen.py')) { $IrcRoot = $c; break }
    }
}
if (-not $IrcRoot) { throw 'agentic_irc checkout not found' }

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

$p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner,
    '-IrcHome', $IrcHome, '-IrcRoot', $IrcRoot, '-Nick', $nick
)
Set-Content -Path $pidFile -Value $p.Id -NoNewline
Write-Output "IRC TSR: nick=$nick pid=$($p.Id) home=$IrcHome"
