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

# --- irc_listen leak guard (ionos 25/09: 148 orphaned irc_listen.py) ---
# Stop-Process on the runner does NOT kill its python child on Windows, so every
# RestartAfterSec recycle orphaned one irc_listen.py. Pure functions take a
# process list (ProcessId, ParentProcessId, CommandLine) so they test off-DEV.

function Get-IrcTsrProcessList {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Select-Object ProcessId, ParentProcessId, CommandLine)
}

function Select-IrcTsrListenProcesses {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes,
        [Parameter(Mandatory)][string]$IrcHome
    )
    $homeRe = '(?i)--home(?:=|\s+)["'']?' + [regex]::Escape($IrcHome.TrimEnd('\')) + '\\?["'']?(\s|$)'
    @($Processes | Where-Object {
            $c = [string]$_.CommandLine
            $c -and $c -match 'irc_listen\.py' -and $c -match $homeRe
        })
}

function Test-IrcTsrListenChildOf {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes,
        [Parameter(Mandatory)][string]$IrcHome,
        [int]$RunnerPid
    )
    if ($RunnerPid -le 0) { return $false }
    $mine = @(Select-IrcTsrListenProcesses -Processes $Processes -IrcHome $IrcHome |
            Where-Object { [int]$_.ParentProcessId -eq $RunnerPid })
    return ($mine.Count -gt 0)
}

function Select-IrcTsrStaleListens {
    # Every listen for this home that is NOT a child of KeepRunnerPid (0 = keep none).
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes,
        [Parameter(Mandatory)][string]$IrcHome,
        [int]$KeepRunnerPid = 0
    )
    @(Select-IrcTsrListenProcesses -Processes $Processes -IrcHome $IrcHome |
            Where-Object { $KeepRunnerPid -le 0 -or [int]$_.ParentProcessId -ne $KeepRunnerPid })
}

function Stop-IrcTsrStaleListens {
    param(
        [Parameter(Mandatory)][string]$IrcHome,
        [int]$KeepRunnerPid = 0,
        [object[]]$Processes
    )
    if ($null -eq $Processes) { $Processes = Get-IrcTsrProcessList }
    $stale = @(Select-IrcTsrStaleListens -Processes $Processes -IrcHome $IrcHome -KeepRunnerPid $KeepRunnerPid)
    foreach ($p in $stale) {
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
    }
    return $stale.Count
}
