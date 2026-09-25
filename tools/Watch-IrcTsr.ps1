# Keep IRC TSR alive. Poll; restart if the runner died, listen child is gone,
# runner age exceeds RestartAfterSec, or the wake heartbeat is stale.
# Does NOT start Watch-CursorIrc or cursor-<id> extras. Silence gate uses
# irc-tsr-*-wake.jsonl only (idle #bobiverse must not trip recycle).
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [int]$RestartAfterSec = 600,
    [int]$SilenceSec = 60,
    [string]$MachineId,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Irc-Tsr-Health.ps1')
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
if (-not $MachineId) { $MachineId = $env:BOB_MACHINE_ID }
if (-not $MachineId) { throw 'MachineId required (set BOB_MACHINE_ID or pass -MachineId)' }

$ircHome = Join-Path $env:USERPROFILE '.agentic-irc-cursor'
if ($env:AGENTIC_IRC_CURSOR_HOME -and $env:AGENTIC_IRC_CURSOR_HOME.Trim()) {
    $ircHome = $env:AGENTIC_IRC_CURSOR_HOME.Trim()
}
$pidPath = Join-Path $ircHome 'coordinator.pid'
try { $coord = [int](Get-Content $pidPath -Raw).Trim() } catch { $coord = 0 }
$nick = if ($coord -gt 0) { '{0}-{1}' -f $MachineId, $coord } else { '{0}-coord' -f $MachineId }

$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir "watch-irc-tsr-$nick.log"
$tsrPidFile = Join-Path $logDir "irc-tsr-$nick.pid"
$wakePath = Join-Path $logDir "irc-tsr-$nick-wake.jsonl"
$startScript = Join-Path $RepoRoot 'tools\Start-IrcTsr.ps1'

function Write-TsrWatchLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

function Get-TsrRunnerPid {
    if (-not (Test-Path $tsrPidFile)) { return 0 }
    try { return [int](Get-Content $tsrPidFile -Raw).Trim() } catch { return 0 }
}

function Test-TsrHealthy {
    $rid = Get-TsrRunnerPid
    $proc = $null
    if ($rid -gt 0) { $proc = Get-Process -Id $rid -ErrorAction SilentlyContinue }
    # Only a listen whose parent IS the live runner counts; orphans from old
    # runners used to satisfy this and hide the leak.
    $procs = Get-IrcTsrProcessList
    $listenUp = Test-IrcTsrListenChildOf -Processes $procs -IrcHome $ircHome -RunnerPid $rid
    if ($proc) {
        $reaped = Stop-IrcTsrStaleListens -IrcHome $ircHome -KeepRunnerPid $rid -Processes $procs
        if ($reaped -gt 0) { Write-TsrWatchLog "reaped $reaped orphan irc_listen (runner $rid)" }
    }
    $age = 0
    if ($proc -and $proc.StartTime) {
        $age = [int]((Get-Date) - $proc.StartTime).TotalSeconds
    }
    $wakeStale = Test-IrcTsrWakeSilenceStale -WakePath $wakePath -SilenceSec $SilenceSec
    return (Test-IrcTsrRunnerHealthyCore `
            -RunnerAlive ($null -ne $proc) `
            -ListenChildUp $listenUp `
            -RunnerAgeSec $age `
            -RestartAfterSec $RestartAfterSec `
            -WakeSilenceStale $wakeStale)
}

Write-TsrWatchLog "watch start poll=${PollSec}s silence=${SilenceSec}s restartAfter=${RestartAfterSec}s nick=$nick"
while ($true) {
    try {
        if (-not (Test-TsrHealthy)) {
            Write-TsrWatchLog 'TSR down or stale; Start-IrcTsr'
            & $startScript -MachineId $MachineId -IrcHome $ircHome 2>&1 | Out-Null
        }
    }
    catch {
        Write-TsrWatchLog ('tick error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
