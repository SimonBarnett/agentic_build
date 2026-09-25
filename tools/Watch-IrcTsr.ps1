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
. (Join-Path $PSScriptRoot 'Irc-Tsr-Coordinator.ps1')
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
if (-not $MachineId) { $MachineId = $env:BOB_MACHINE_ID }
if (-not $MachineId) { throw 'MachineId required (set BOB_MACHINE_ID or pass -MachineId)' }

$ircHome = Join-Path $env:USERPROFILE '.agentic-irc-cursor'
if ($env:AGENTIC_IRC_CURSOR_HOME -and $env:AGENTIC_IRC_CURSOR_HOME.Trim()) {
    $ircHome = $env:AGENTIC_IRC_CURSOR_HOME.Trim()
}
$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$startScript = Join-Path $RepoRoot 'tools\Start-IrcTsr.ps1'

function Update-TsrWatchPaths {
    # Same nick as Start-IrcTsr (shared parser), re-read every tick: Start-IrcTsr may create
    # coordinator.pid after this watcher started, and a talk seat may rewrite it (key=value).
    $script:nick = Get-IrcTsrCoordinatorNick -MachineId $MachineId -IrcHome $ircHome
    $script:logPath = Join-Path $logDir "watch-irc-tsr-$($script:nick).log"
    $script:tsrPidFile = Join-Path $logDir "irc-tsr-$($script:nick).pid"
    $script:wakePath = Join-Path $logDir "irc-tsr-$($script:nick)-wake.jsonl"
}
Update-TsrWatchPaths
$consecutiveRestarts = 0
$nextStartAt = [datetime]::MinValue

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
        Update-TsrWatchPaths
        if (Test-TsrHealthy) {
            $consecutiveRestarts = 0
        }
        elseif ([datetime]::Now -lt $nextStartAt) {
            Write-TsrWatchLog ('TSR down; backoff until {0:o} ({1} restarts in a row)' -f $nextStartAt, $consecutiveRestarts)
        }
        else {
            Write-TsrWatchLog 'TSR down or stale; Start-IrcTsr'
            & $startScript -MachineId $MachineId -IrcHome $ircHome 2>&1 | Out-Null
            $consecutiveRestarts++
            # A restart that never turns healthy must not spawn a runner + listen every PollSec.
            $delay = Get-IrcTsrRestartDelaySec -ConsecutiveRestarts $consecutiveRestarts -BaseSec $PollSec -MaxSec 600
            $nextStartAt = [datetime]::Now.AddSeconds($delay)
        }
    }
    catch {
        Write-TsrWatchLog ('tick error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
