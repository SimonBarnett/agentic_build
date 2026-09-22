# Off-DEV testable TSR watchdog health (wake heartbeat only — not irc.log chat mtime).

function Test-IrcTsrWakeSilenceStale {
    param(
        [Parameter(Mandatory)][string]$WakePath,
        [int]$SilenceSec,
        [datetime]$Now = [datetime]::Now
    )
    if ($SilenceSec -le 0) { return $false }
    # Missing wake is not chat silence — runner must write PROCESS_HEARTBEAT first; do not recycle on absent file alone.
    if (-not (Test-Path -LiteralPath $WakePath)) { return $false }
    $stamp = (Get-Item -LiteralPath $WakePath).LastWriteTime
    $quiet = [int](($Now - $stamp).TotalSeconds)
    return ($quiet -ge $SilenceSec)
}

function Test-IrcTsrRunnerHealthyCore {
    param(
        [bool]$RunnerAlive,
        [bool]$ListenChildUp,
        [int]$RunnerAgeSec,
        [int]$RestartAfterSec,
        [bool]$WakeSilenceStale
    )
    if (-not $RunnerAlive) { return $false }
    if (-not $ListenChildUp) { return $false }
    if ($RestartAfterSec -gt 0 -and $RunnerAgeSec -ge $RestartAfterSec) { return $false }
    if ($WakeSilenceStale) { return $false }
    return $true
}
