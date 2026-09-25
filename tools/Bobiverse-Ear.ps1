# Single-instance guard for the bob-<machine> ear (irc_agent.py kept alive by Watch-Bobiverse).
# ASCII only (Windows PowerShell 5.1 reads BOM-less files as ANSI). Pure functions take a process
# list (ProcessId, CommandLine, CreationDate) so they test off-DEV.
#
# flamingo 25/09 10:05 BST: the box was out of commit (1800+ leaked irc_listen). Get-CimInstance
# -ErrorAction SilentlyContinue returned nothing, Test-BobiverseIrcAgentUp read that as "no ear",
# and Watch-Bobiverse started a second bob-flamingo while pid 12176 was still connected. The
# newcomer got 433 and ran as bob-flamingo_l; both wrote the same irc.log (every line twice).

function Test-BobiverseEarCommandLine {
    param([AllowNull()][string]$CommandLine)
    if (-not $CommandLine) { return $false }
    if ($CommandLine -notmatch 'irc_agent\.py') { return $false }
    if ($CommandLine -notmatch '--nick\s+bob-') { return $false }
    return ($CommandLine -match 'irc\.ntsa\.uk' -or $CommandLine -match '127\.0\.0\.1')
}

function Get-BobiverseProcessSnapshot {
    # Ok = $false when the process query itself failed (WMI down / out of resources).
    # Callers must treat that as UNKNOWN, never as "no ear".
    try {
        $p = @(Get-CimInstance Win32_Process -ErrorAction Stop |
                Select-Object ProcessId, ParentProcessId, CommandLine, CreationDate)
        if ($p.Count -eq 0) { return [pscustomobject]@{ Ok = $false; Processes = @(); Error = 'empty process list' } }
        return [pscustomobject]@{ Ok = $true; Processes = $p; Error = $null }
    }
    catch {
        return [pscustomobject]@{ Ok = $false; Processes = @(); Error = [string]$_.Exception.Message }
    }
}

function Select-BobiverseEarProcesses {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes)
    @($Processes | Where-Object { Test-BobiverseEarCommandLine ([string]$_.CommandLine) })
}

function Get-BobiverseEarSpawnDecision {
    # 'spawn' only when the query worked AND no ear runs. 'unknown' = query failed: do not spawn.
    param(
        [bool]$QueryOk,
        [int]$EarCount
    )
    if (-not $QueryOk) { return 'unknown' }
    if ($EarCount -gt 0) { return 'up' }
    return 'spawn'
}

function Select-BobiverseEarDuplicates {
    # Keep the OLDEST ear (it holds the real nick; newer ones are nick_l / nick_), return the rest.
    # Same keep-oldest rule as the tray single-instance guard (#318).
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Processes)
    $ears = @(Select-BobiverseEarProcesses -Processes $Processes |
            Sort-Object @{ Expression = { if ($_.CreationDate) { [datetime]$_.CreationDate } else { [datetime]::MaxValue } } }, @{ Expression = { [int]$_.ProcessId } })
    if ($ears.Count -le 1) { return @() }
    return @($ears | Select-Object -Skip 1)
}
