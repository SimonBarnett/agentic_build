# Off-DEV testable TSR watchdog health (PROCESS_HEARTBEAT in wake jsonl — not irc.log / FROM mtime).

function Get-IrcTsrLastProcessHeartbeatTime {
    param([Parameter(Mandatory)][string]$WakePath)
    if (-not (Test-Path -LiteralPath $WakePath)) { return $null }
    $last = $null
    foreach ($line in [System.IO.File]::ReadLines($WakePath)) {
        if ($line -notmatch 'PROCESS_HEARTBEAT') { continue }
        if ($line -match '^(\d{4}-\d{2}-\d{2}T\S+)\s+PROCESS_HEARTBEAT') {
            $last = [datetime]::Parse($Matches[1], $null, [Globalization.DateTimeStyles]::RoundtripKind)
        }
    }
    return $last
}

function Test-IrcTsrWakeSilenceStale {
    param(
        [Parameter(Mandatory)][string]$WakePath,
        [int]$SilenceSec,
        [datetime]$Now = [datetime]::Now
    )
    if ($SilenceSec -le 0) { return $false }
    # Missing wake is not chat silence — runner must write PROCESS_HEARTBEAT first; do not recycle on absent file alone.
    if (-not (Test-Path -LiteralPath $WakePath)) { return $false }
    $stamp = Get-IrcTsrLastProcessHeartbeatTime -WakePath $WakePath
    # FROM lines may touch the file; silence is measured on process heartbeat only.
    if (-not $stamp) { return $false }
    $quiet = [int](($Now.ToUniversalTime() - $stamp.ToUniversalTime()).TotalSeconds)
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
