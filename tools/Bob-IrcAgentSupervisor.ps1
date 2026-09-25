# FR #328: singleton supervisor for bob-{machine} irc_agent (scripts only; no live restart from CI).
# Ensures exactly one irc_agent.py --nick bob-{machine} for the bobiverse home; graceful restart
# via agent.quit.request; clears stale quit files before start (agentic_irc#201).
#Requires -Version 5.1

function Get-BobIrcAgentHome {
    param([string]$IrcHome)
    if ($IrcHome) { return [IO.Path]::GetFullPath($IrcHome) }
    return [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.agentic-irc-bobiverse'))
}

function Clear-BobIrcStaleQuitRequest {
    param([Parameter(Mandatory)][string]$IrcHome)
    $h = Get-BobIrcAgentHome -IrcHome $IrcHome
    $removed = @()
    foreach ($leaf in @('agent.quit.request', 'quit.req')) {
        $p = Join-Path $h $leaf
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $p)) { $removed += $leaf }
        }
    }
    return $removed
}

function Select-BobIrcAgentRows {
    param(
        [Parameter(Mandatory)][string]$Nick,
        [object[]]$Processes
    )
    $n = [regex]::Escape($Nick)
    $rows = @()
    foreach ($p in @($Processes)) {
        $cl = [string]$p.CommandLine
        if (-not $cl) { continue }
        if ($cl -notmatch 'irc_agent\.py') { continue }
        if ($cl -notmatch ("--nick\s+{0}\b" -f $n) -and $cl -notmatch ("--nick={0}\b" -f $n)) { continue }
        $rows += $p
    }
    return @($rows | Sort-Object { [int]$_.ProcessId })
}

function Select-BobIrcAgentKeepPid {
    param([object[]]$Agents)
    $a = @($Agents)
    if ($a.Count -eq 0) { return 0 }
    # Keep the oldest (lowest PID) as the singleton survivor.
    return [int]$a[0].ProcessId
}

function Get-BobIrcAgentHealth {
    param(
        [Parameter(Mandatory)][string]$Nick,
        [Parameter(Mandatory)][string]$IrcHome,
        [object[]]$Processes,
        [string]$IrcRoot = '',
        [string]$Revision = ''
    )
    $rows = Select-BobIrcAgentRows -Nick $Nick -Processes $Processes
    $keep = Select-BobIrcAgentKeepPid -Agents $rows
    $start = $null
    if ($keep -gt 0) {
        try {
            $proc = Get-Process -Id $keep -ErrorAction SilentlyContinue
            if ($proc) { $start = $proc.StartTime.ToString('o') }
        }
        catch { }
    }
    if (-not $Revision -and $IrcRoot) {
        $revFile = Join-Path $IrcRoot 'scripts\irc_agent.py'
        if (Test-Path -LiteralPath $revFile) {
            try {
                $Revision = (Get-FileHash -LiteralPath $revFile -Algorithm SHA256).Hash.Substring(0, 12)
            }
            catch { $Revision = '' }
        }
    }
    return [pscustomobject]@{
        Nick       = $Nick
        IrcHomePath = (Get-BobIrcAgentHome -IrcHome $IrcHome)
        Count      = $rows.Count
        KeepPid    = $keep
        ExtraPids  = @($rows | Where-Object { [int]$_.ProcessId -ne $keep } | ForEach-Object { [int]$_.ProcessId })
        StartTime  = $start
        Revision   = $Revision
        Healthy    = ($rows.Count -eq 1)
    }
}

function Write-BobIrcAgentQuitRequest {
    param([Parameter(Mandatory)][string]$IrcHome)
    $h = Get-BobIrcAgentHome -IrcHome $IrcHome
    New-Item -ItemType Directory -Force -Path $h | Out-Null
    $p = Join-Path $h 'agent.quit.request'
    [System.IO.File]::WriteAllText($p, "supervisor restart`n", [System.Text.UTF8Encoding]::new($false))
    return $p
}

function Invoke-BobIrcAgentEnsure {
    <#
    Singleton ensure. Inject process list + start/stop for tests.
    Returns: started | unchanged | culled | started_after_cull
    #>
    param(
        [Parameter(Mandatory)][string]$Nick,
        [Parameter(Mandatory)][string]$IrcHome,
        [Parameter(Mandatory)][string]$Python,
        [Parameter(Mandatory)][string]$AgentPath,
        [Parameter(Mandatory)][string]$IrcRoot,
        [Parameter(Mandatory)][string]$IrcHost,
        [int]$IrcPort = 6697,
        [string]$Channels = '#bobiverse',
        [string]$Hello = 'builder',
        [object[]]$Processes,
        [scriptblock]$StartFn,
        [scriptblock]$StopFn,
        [switch]$SkipClearQuit
    )
    if (-not $SkipClearQuit) {
        [void](Clear-BobIrcStaleQuitRequest -IrcHome $IrcHome)
    }
    # Only auto-scan CIM when Processes was omitted ($null). Empty @() means "none" (tests).
    if ($null -eq $Processes) {
        $Processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })
    }
    $rows = Select-BobIrcAgentRows -Nick $Nick -Processes $Processes
    $keep = Select-BobIrcAgentKeepPid -Agents $rows
    $result = 'unchanged'
    if ($rows.Count -gt 1) {
        foreach ($r in $rows) {
            $procId = [int]$r.ProcessId
            if ($procId -eq $keep) { continue }
            if ($StopFn) { & $StopFn $procId }
            else { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue }
        }
        $result = 'culled'
        # refresh
        if (-not $StartFn) {
            Start-Sleep -Milliseconds 200
            $Processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })
            $rows = Select-BobIrcAgentRows -Nick $Nick -Processes $Processes
            $keep = Select-BobIrcAgentKeepPid -Agents $rows
        }
        else {
            $rows = @($rows | Where-Object { [int]$_.ProcessId -eq $keep })
        }
    }
    if ($rows.Count -eq 0) {
        $argList = @(
            '-u', $AgentPath,
            '--host', $IrcHost,
            '--port', "$IrcPort",
            '--nick', $Nick,
            '--channel', $Channels,
            '--home', (Get-BobIrcAgentHome -IrcHome $IrcHome),
            '--announce-key',
            '--hello', $Hello
        )
        if ($StartFn) {
            & $StartFn $Python $argList $IrcRoot
        }
        else {
            Start-Process -FilePath $Python -ArgumentList $argList -WorkingDirectory $IrcRoot -WindowStyle Hidden | Out-Null
        }
        if ($result -eq 'culled') { return 'started_after_cull' }
        return 'started'
    }
    return $result
}

function Invoke-BobIrcAgentRestart {
    <#
    Graceful restart: quit request -> wait for exit -> ensure start. Never two at once.
    #>
    param(
        [Parameter(Mandatory)][string]$Nick,
        [Parameter(Mandatory)][string]$IrcHome,
        [Parameter(Mandatory)][string]$Python,
        [Parameter(Mandatory)][string]$AgentPath,
        [Parameter(Mandatory)][string]$IrcRoot,
        [Parameter(Mandatory)][string]$IrcHost,
        [int]$IrcPort = 6697,
        [string]$Channels = '#bobiverse',
        [string]$Hello = 'builder',
        [object[]]$Processes,
        [scriptblock]$StartFn,
        [scriptblock]$StopFn,
        [scriptblock]$WaitFn,
        [int]$WaitSeconds = 25
    )
    if ($null -eq $Processes) {
        $Processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })
    }
    $rows = Select-BobIrcAgentRows -Nick $Nick -Processes $Processes
    $oldPids = @($rows | ForEach-Object { [int]$_.ProcessId })
    if ($oldPids.Count -gt 0) {
        [void](Write-BobIrcAgentQuitRequest -IrcHome $IrcHome)
        $deadline = [datetime]::UtcNow.AddSeconds([Math]::Max(5, $WaitSeconds))
        while ([datetime]::UtcNow -lt $deadline) {
            if ($WaitFn) {
                $still = & $WaitFn $oldPids
            }
            else {
                $still = @($oldPids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
            }
            if (@($still).Count -eq 0) { break }
            Start-Sleep -Milliseconds 400
        }
        # force leftovers
        foreach ($op in $oldPids) {
            $alive = $false
            if ($WaitFn) { $alive = @(& $WaitFn @($op)).Count -gt 0 }
            else { $alive = [bool](Get-Process -Id $op -ErrorAction SilentlyContinue) }
            if ($alive) {
                if ($StopFn) { & $StopFn $op }
                else { Stop-Process -Id $op -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    [void](Clear-BobIrcStaleQuitRequest -IrcHome $IrcHome)
    # empty process list after restart for ensure start
    return Invoke-BobIrcAgentEnsure -Nick $Nick -IrcHome $IrcHome -Python $Python -AgentPath $AgentPath `
        -IrcRoot $IrcRoot -IrcHost $IrcHost -IrcPort $IrcPort -Channels $Channels -Hello $Hello `
        -Processes @() -StartFn $StartFn -StopFn $StopFn -SkipClearQuit
}

function Write-BobIrcAgentHealthLine {
    param($Health)
    $h = $Health
    $homePath = $h.IrcHomePath
    if (-not $homePath) { $homePath = $h.Home }
    $line = "bob-irc-agent nick=$($h.Nick) pid=$($h.KeepPid) count=$($h.Count) start=$($h.StartTime) rev=$($h.Revision) home=$homePath"
    return $line
}
