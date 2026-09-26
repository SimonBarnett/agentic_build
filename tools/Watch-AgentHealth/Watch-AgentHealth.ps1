<#
.SYNOPSIS
  Start grok agent.exe or Cursor agent.cmd; watch the agent process; forward IRC FROM lines when the agent's listener exists.

.DESCRIPTION
  Simon #bobiverse 2026-09-22: --grok / --cursor. Persist session id (resume, no full skill reload).
  CAST IRON (Simon 2026-09-23): Ensure-WatchIrcSeat starts irc_agent + irc_listen on the watch
  home and JOINs its own #{machine} ONLY (never #bobiverse / #agentic_irc; CAST IRON 2026-09-25).
  Monitor tails $IrcHome/irc.log and forwards each PRIVMSG as FROM into the agent.
  The agent only handles messages the monitor passes; it does not run or duplicate this monitor.
  Own IRC home only (.agentic-irc-watch-*). Does not touch cursor / cursor-2 / bobiverse Watch.
  Does not stamp UAT. Does not send !bobiverse.
  The TUI agent does not probe IRC â€” it acts on monitor FROM only (skill watch-seat).

.EXAMPLE
  Desktop\Watch-AgentHealth.cmd cursor
  Desktop\Watch-AgentHealth.cmd cursor new
  Desktop\Watch-AgentHealth.cmd grok
  Desktop\Watch-AgentHealth.cmd grok new

  Direct .\Watch-AgentHealth.ps1 fails when execution policy is Restricted; use .cmd or -ExecutionPolicy Bypass.
  Visible by default (no on flag). -Windows off: hidden watch worker and hidden agent TUI; log file still receives lines. One-shot agent -p forwards stay hidden.
#>
[CmdletBinding(DefaultParameterSetName = 'none')]
param(
    [Parameter(ParameterSetName = 'grok')]
    [switch]$Grok,

    [Parameter(ParameterSetName = 'cursor')]
    [switch]$Cursor,

    [switch]$New,

    [switch]$WatchWorker,

    # FR #89: monitor-only reload. Adopts live agent tree (state.rootPid + session) and keeps
    # ircNick / seat nick when irc_agent is already up. Does not require killing agent.exe.
    # Usage: stop the old monitor process, then start with -Reload (or tray/script that passes it).
    # Do not use to force a second TUI — adoption skips Start-WatchedAgent when the tree is healthy.
    [switch]$Reload,

    # Cursor agent --model (e.g. auto). Empty = CLI default. Tray Agents always passes auto.
    [string]$Model = '',

    [ValidateSet('on', 'off')]
    [string]$Windows = 'on',

    [string]$Cwd,
    [string]$IrcHome,
    [int]$PollSeconds = 15,
    [int]$CrashBackoffSeconds = 20,
    [string]$LogPath,

    # FR #100: monitor-owned !bored (no LLM). First idle fire after this many seconds.
    [ValidateRange(60, 600)]
    [int]$BoredIdleSeconds = 120,

    # FR #100: repeat !bored while still idle (2–5 min window; default 3 min).
    [ValidateRange(120, 300)]
    [int]$BoredRepeatSeconds = 180,

    # Open ACK without DONE older than this is treated as stale (not busy).
    [ValidateRange(5, 240)]
    [int]$BoredAckStaleMinutes = 45,

    # FR #100 acceptance: DONE -> !bored within ~5s (poll loop ticks this often for Sync-WatchBored).
    [ValidateRange(1, 15)]
    [int]$BoredCheckSeconds = 5,

    # FR #105: identical FROM lines are deduped only for this many seconds (then re-forward).
    [ValidateRange(5, 600)]
    [int]$ForwardDedupeSeconds = 60,

    # FR #91: max runtime for a hidden agent -p / Cursor -p wake before kill (default 30 min).
    [ValidateRange(60, 86400)]
    [int]$WakeTimeoutSeconds = 1800,

    # FR #91: max queued FROM lines while a wake is in flight for this session.
    [ValidateRange(1, 100)]
    [int]$WakeQueueMax = 20,

    # FR #99: rotate oversized sessions before resume (default 10 MB updates.jsonl)
    [double]$SessionMaxUpdatesMb = 10,
    # FR #99: hung agent -p with no CPU progress (minutes)
    [double]$SessionHangMinutes = 3,
    # Optional override for tests
    [string]$GrokSessionsRoot = '',

    # FR #103: fleet (default) vs loop (continuous non-job agent; never !bored / ACK-Jeeves).
    [ValidateSet('fleet', 'loop')]
    [string]$SeatType = 'fleet',

    # FR #103: suppress every monitor !bored (implied by -SeatType loop).
    [switch]$NoBored,

    # FR #103: loop seat IRC channel (e.g. '#ce-priority-dev1'). Fleet ignores (own #{machine}).
    [string]$Channel = '',

    # FR #103: loop seat nick (e.g. 'dayworks-dev1'). Must NOT match {machine}-{pid} worker grammar.
    [string]$Nick = ''
)

$ErrorActionPreference = 'Stop'

$script:AgentTuiWindowStyle = $(if ($Windows -eq 'on') { 'Normal' } else { 'Hidden' })
$script:CursorModel = ([string]$Model).Trim()
$script:BoredIdleSeconds = [int]$BoredIdleSeconds
$script:BoredRepeatSeconds = [int]$BoredRepeatSeconds
$script:BoredAckStaleMinutes = [int]$BoredAckStaleMinutes
$script:BoredCheckSeconds = [int]$BoredCheckSeconds
$script:ForwardDedupeSeconds = [int]$ForwardDedupeSeconds
$script:WakeTimeoutSeconds = [int]$WakeTimeoutSeconds
$script:WakeQueueMax = [int]$WakeQueueMax
$script:SessionMaxUpdatesMb = [double]$SessionMaxUpdatesMb
$script:SessionHangMinutes = [double]$SessionHangMinutes
$script:GrokSessionsRoot = [string]$GrokSessionsRoot
$script:SeatType = ([string]$SeatType).Trim().ToLowerInvariant()
if (-not $script:SeatType) { $script:SeatType = 'fleet' }
$script:NoBored = [bool]$NoBored -or ($script:SeatType -eq 'loop')
$script:WatchChannelOverride = ([string]$Channel).Trim()
$script:WatchNickOverride = ([string]$Nick).Trim()
if ($script:SeatType -eq 'loop') {
    if (-not $script:WatchChannelOverride) {
        throw 'Loop seat (-SeatType loop) requires -Channel (e.g. -Channel ''#ce-priority-dev1'').'
    }
    if (-not $script:WatchNickOverride) {
        throw 'Loop seat (-SeatType loop) requires -Nick (non-worker nick, e.g. -Nick ''dayworks-dev1'').'
    }
    # Reject worker grammar so Jeeves/gh-Jeeves never assign or mark busy/idle (K1/K2).
    if ($script:WatchNickOverride -match '^[A-Za-z0-9_]+-\d+$') {
        throw ("Loop seat -Nick '{0}' looks like a worker {{machine}}-{{pid}} nick. Use a non-worker nick (e.g. dayworks-dev1)." -f $script:WatchNickOverride)
    }
}
function Test-WatchNoBored {
    return [bool]$script:NoBored
}

function Get-CursorModelCliArgs {
    if (-not $script:CursorModel) { return @() }
    return @('--model', $script:CursorModel)
}

function Format-CursorModelCliFragment {
    # Single-quoted PowerShell fragment for embedded launch scripts.
    if (-not $script:CursorModel) { return '' }
    $esc = $script:CursorModel.Replace("'", "''")
    return " --model '$esc'"
}

if (-not $Grok -and -not $Cursor) {
    throw 'Pass --grok (agent.exe) or --cursor (agent.cmd).'
}

function Write-WatchBootstrapLog {
    # FR #102: log before Resolve-AgentWorkspace / Write-WatchLog exist.
    param([string]$Message)
    $line = '{0:o} {1}' -f [datetime]::UtcNow, $Message
    $paths = @(
        (Join-Path $env:TEMP 'Watch-AgentHealth-start.log')
    )
    if ($script:LogFile) { $paths += $script:LogFile }
    foreach ($p in $paths) {
        try {
            $dir = Split-Path -Parent $p
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
            }
            Add-Content -LiteralPath $p -Value $line -Encoding utf8 -ErrorAction SilentlyContinue
        }
        catch { }
    }
    try { Write-Host $line } catch { }
}

function Test-WatchFixedWritableDriveRoot {
    # Physical fixed local disk (DriveType=3) that accepts create+delete of a probe file.
    param([string]$Root)
    if (-not $Root) { return $false }
    try {
        $rootPath = [IO.Path]::GetFullPath($Root)
        if ($rootPath -notmatch '^[A-Za-z]:\\$') { return $false }
        $letter = $rootPath.Substring(0, 1).ToUpperInvariant()
        $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}:'" -f $letter) -ErrorAction SilentlyContinue
        if (-not $disk) { return $false }
        if ([int]$disk.DriveType -ne 3) { return $false } # 3 = local fixed disk
        $probe = Join-Path $rootPath ('_wah_write_probe_' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe, 'ok')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        # Missing/ejected letter, ACL deny, or non-fixed — never throw into Resolve-AgentWorkspace.
        try {
            if ($probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
        }
        catch { }
        return $false
    }
}

function Get-WatchFixedDriveLetters {
    # Simon 2026-09-25: letter order C, D, E, … — fixed local disks only.
    $letters = @()
    foreach ($disk in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
        $id = [string]$disk.DeviceID
        if ($id -match '^([A-Za-z]):$') {
            $letters += $Matches[1].ToUpperInvariant()
        }
    }
    return @($letters | Sort-Object)
}

function Resolve-AgentWorkspace {
    # FR #102: fixed writable disks only; C first; never optical/network/rclone/read-only.
    param(
        [string]$Requested,
        [switch]$Explicit
    )
    if ($Explicit -and $Requested) {
        return [IO.Path]::GetFullPath($Requested)
    }
    $leaf = 'ai'
    $letters = @(Get-WatchFixedDriveLetters)
    # Existing \ai: fixed disk only (DriveType=3). Do not require root writability —
    # C:\ may deny create-in-root while C:\ai already exists and is usable.
    foreach ($letter in $letters) {
        $root = '{0}:\' -f $letter
        $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}:'" -f $letter) -ErrorAction SilentlyContinue
        if (-not $disk -or [int]$disk.DriveType -ne 3) { continue }
        $candidate = Join-Path $root $leaf
        if (Test-Path -LiteralPath $candidate) {
            Write-WatchBootstrapLog ("workspace existing {0}" -f $candidate)
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    foreach ($letter in $letters) {
        $root = '{0}:\' -f $letter
        if (-not (Test-WatchFixedWritableDriveRoot -Root $root)) {
            Write-WatchBootstrapLog ("workspace skip create on {0} (not writable fixed)" -f $root)
            continue
        }
        $candidate = Join-Path $root $leaf
        try {
            New-Item -ItemType Directory -Force -Path $candidate | Out-Null
            Write-WatchBootstrapLog ("workspace created {0}" -f $candidate)
            return [IO.Path]::GetFullPath($candidate)
        }
        catch {
            Write-WatchBootstrapLog ("workspace create failed {0}: {1}" -f $candidate, $_.Exception.Message)
        }
    }
    throw 'No writable fixed local drive found to use or create \ai (C: first; never optical/network/rclone).'
}

try {
    $CwdExplicit = $PSBoundParameters.ContainsKey('Cwd') -and $Cwd
    $Cwd = Resolve-AgentWorkspace -Requested $Cwd -Explicit:$CwdExplicit
}
catch {
    Write-WatchBootstrapLog ("fatal start: {0}" -f $_.Exception.Message)
    throw
}

$script:KindName = $(if ($Cursor) { 'cursor' } else { 'grok' })
$script:StateDir = Join-Path $env:USERPROFILE '.grok\agent-health'
$script:IrcHomeExplicit = [bool]($PSBoundParameters.ContainsKey('IrcHome') -and $IrcHome)
$script:ClientSlot = 1
$script:BoundIrcHome = $null
# Paths rebound in Bind-WatchSlot (next free .agentic-irc-watch-* / -2 / -3 â€¦).
$script:StatePath = Join-Path $script:StateDir ("state-{0}.json" -f $script:KindName)
$script:WorkerPidPath = Join-Path $script:StateDir ("watch-worker-{0}.pid" -f $script:KindName)
if (-not $IrcHome) {
    $IrcHome = Join-Path $env:USERPROFILE ('.agentic-irc-watch-{0}' -f $script:KindName)
}

function Write-WatchLog {
    param([string]$Message)
    $line = '{0:o} {1}' -f [datetime]::UtcNow, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding utf8
    Write-Host $line
}

function Get-WatchSeatTranscriptPath {
    # FR #90 Option B: operator-visible wake transcript (TUI does not reload hidden -p turns).
    if (-not $script:StateDir) { return $null }
    return (Join-Path $script:StateDir 'seat-wake-transcript.log')
}

function Write-WatchSeatTranscript {
    param([string]$Message)
    $path = Get-WatchSeatTranscriptPath
    if (-not $path) {
        Write-WatchLog $Message
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    $line = '{0:o} {1}' -f [datetime]::UtcNow, $Message
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::AppendAllText($path, $line + [Environment]::NewLine, $utf8)
    Write-WatchLog $Message
}

function Test-WatchSeatTranscriptPaneAlive {
    param([string]$TranscriptPath)
    if (-not $TranscriptPath) { return $false }
    $esc = [regex]::Escape($TranscriptPath)
    $rows = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)
    foreach ($row in $rows) {
        $cl = [string]$row.CommandLine
        if ($cl -match 'seat-wake-transcript' -and $cl -match $esc) { return $true }
    }
    return $false
}

function Ensure-WatchSeatTranscriptPane {
    # Visible console that tails seat-wake-transcript.log (Option B). No keystroke injection.
    if ($script:AgentTuiWindowStyle -eq 'Hidden') { return $false }
    $path = Get-WatchSeatTranscriptPath
    if (-not $path) { return $false }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    if (-not (Test-Path -LiteralPath $path)) {
        [IO.File]::WriteAllText($path, '', (New-Object System.Text.UTF8Encoding $false))
    }
    if (Test-WatchSeatTranscriptPaneAlive -TranscriptPath $path) { return $true }
    $title = 'Watch seat IRC wake transcript (FR #90) - hidden -p turns appear here'
    $escPath = $path.Replace("'", "''")
    $escTitle = $title.Replace("'", "''")
    $body = @(
        "`$Host.UI.RawUI.WindowTitle = '$escTitle'"
        "Write-Host 'Tailing $escPath'"
        "Write-Host 'Hidden agent -p wakes are logged here so the seat does not look idle (AgentMonitor FR #90).'"
        "Write-Host ''"
        "Get-Content -LiteralPath '$escPath' -Wait -Tail 80 -Encoding UTF8"
    ) -join [Environment]::NewLine
    $launcher = Join-Path $script:StateDir 'seat-wake-transcript-pane.ps1'
    [IO.File]::WriteAllText($launcher, $body, (New-Object System.Text.UTF8Encoding $false))
    $psExe = (Get-Command powershell.exe).Source
    Start-Process -FilePath $psExe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $launcher
    ) -WindowStyle Normal | Out-Null
    Write-WatchLog ('seat transcript pane started path={0}' -f $path)
    return $true
}

function Start-WatchForwardExitWatcher {
    # Non-blocking: wait for hidden wake PID and append end/exit to transcript + monitor log.
    param(
        [int]$ProcessId,
        [string]$SessionId,
        [string]$Kind,
        [string]$TranscriptPath,
        [string]$LogFile
    )
    if ($ProcessId -le 0) { return }
    if (-not $script:StateDir) { return }
    $psExe = (Get-Command powershell.exe).Source
    $escTrans = ([string]$TranscriptPath).Replace("'", "''")
    $escLog = ([string]$LogFile).Replace("'", "''")
    $escSid = ([string]$SessionId).Replace("'", "''")
    $escKind = ([string]$Kind).Replace("'", "''")
    $scriptBody = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$pidWake = $ProcessId
`$p = Get-Process -Id `$pidWake -ErrorAction SilentlyContinue
`$code = 'unknown'
`$ended = [datetime]::UtcNow.ToString('o')
if (`$p) {
    `$p.WaitForExit()
    try { `$code = `$p.ExitCode } catch { `$code = 'n/a' }
    `$ended = [datetime]::UtcNow.ToString('o')
} else {
    `$code = 'gone'
}
`$msg = ('wake end kind={0} session={1} pid={2} exit={3}' -f '$escKind', '$escSid', `$pidWake, `$code)
`$line = '{0} {1}' -f `$ended, `$msg
`$utf8 = New-Object System.Text.UTF8Encoding `$false
if ('$escTrans') { [IO.File]::AppendAllText('$escTrans', `$line + [Environment]::NewLine, `$utf8) }
if ('$escLog') { [IO.File]::AppendAllText('$escLog', `$line + [Environment]::NewLine, `$utf8) }
"@
    $waiter = Join-Path $script:StateDir ('forward-exit-waiter-{0}.ps1' -f $ProcessId)
    [IO.File]::WriteAllText($waiter, $scriptBody, (New-Object System.Text.UTF8Encoding $false))
    Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $waiter) -WindowStyle Hidden | Out-Null
}

function Test-WatchProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return [bool]$p
}

function Test-WatchWakeInFlight {
    # FR #91: true when state tracks a live wake PID (or OS still shows -p for session).
    param($State)
    if (-not $State) { return $false }
    $wp = 0
    if ($State.PSObject.Properties.Name -contains 'wakePid') {
        try { $wp = [int]$State.wakePid } catch { $wp = 0 }
    }
    if ($wp -gt 0 -and (Test-WatchProcessAlive -ProcessId $wp)) { return $true }
    $sid = ''
    if ($State.sessionId) { $sid = [string]$State.sessionId }
    $grokKind = ($script:KindName -eq 'grok') -or [bool]$Grok
    return (Test-WatchAgentWakeBusy -SessionId $sid -GrokKind:$grokKind)
}

function Clear-WatchWakeState {
    param($State, [string]$Reason = '')
    if (-not $State) { return $State }
    $State | Add-Member -NotePropertyName 'wakePid' -NotePropertyValue 0 -Force
    $State | Add-Member -NotePropertyName 'wakeStartedUtc' -NotePropertyValue $null -Force
    $State | Add-Member -NotePropertyName 'wakeKind' -NotePropertyValue '' -Force
    if ($Reason) { Write-WatchLog $Reason }
    return $State
}

function Add-WatchWakeQueue {
    # Queue FROM while a wake is in flight; coalesce exact duplicate pending lines.
    param($State, [string]$Line)
    if (-not $State) { return $State }
    $q = @()
    if ($State.PSObject.Properties.Name -contains 'wakeQueue' -and $State.wakeQueue) {
        $q = @($State.wakeQueue)
    }
    foreach ($existing in $q) {
        if ([string]$existing -eq [string]$Line) {
            Write-WatchLog 'forward queue coalesce (duplicate pending FROM)'
            return $State
        }
    }
    $max = [int]$script:WakeQueueMax
    if ($max -le 0) { $max = 20 }
    if ($q.Count -ge $max) {
        $q = @($q | Select-Object -Skip 1)
        Write-WatchLog ('forward queue overflow drop oldest max={0}' -f $max)
    }
    $q += ,[string]$Line
    $State | Add-Member -NotePropertyName 'wakeQueue' -NotePropertyValue $q -Force
    Write-WatchLog ('forward queued depth={0}' -f $q.Count)
    return $State
}

function Pop-WatchWakeQueue {
    param($State)
    if (-not $State) { return @{ State = $State; Line = $null } }
    $q = @()
    if ($State.PSObject.Properties.Name -contains 'wakeQueue' -and $State.wakeQueue) {
        $q = @($State.wakeQueue)
    }
    if ($q.Count -eq 0) {
        $State | Add-Member -NotePropertyName 'wakeQueue' -NotePropertyValue @() -Force
        return @{ State = $State; Line = $null }
    }
    $line = [string]$q[0]
    $rest = @()
    if ($q.Count -gt 1) { $rest = @($q | Select-Object -Skip 1) }
    $State | Add-Member -NotePropertyName 'wakeQueue' -NotePropertyValue $rest -Force
    return @{ State = $State; Line = $line }
}

function Stop-OrphanWatchWakeProcesses {
    # FR #91: on monitor start, kill orphaned -p wakes whose parent is dead.
    # Never touch interactive TUI (agent.exe / cursor-agent without -p).
    param(
        [string]$SessionId,
        [switch]$GrokKind
    )
    $sid = ([string]$SessionId).Trim()
    $killed = 0
    $rows = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    foreach ($row in $rows) {
        $cl = [string]$row.CommandLine
        $procId = [int]$row.ProcessId
        $isWake = $false
        if ($GrokKind) {
            if ([string]$row.Name -ne 'agent.exe') { continue }
            if ($cl -notmatch ' -p(\s|$)') { continue } # live TUI: keep
            if ($sid -and $cl -notmatch (' -r\s+' + [regex]::Escape($sid) + '\b')) { continue }
            $isWake = $true
        }
        else {
            if ([string]$row.Name -eq 'powershell.exe' -and $cl -match 'forward-cursor\.ps1') {
                if ($script:StateDir -and $cl -notmatch [regex]::Escape($script:StateDir)) { continue }
                $isWake = $true
            }
            elseif ($sid -and $cl -match 'cursor-agent' -and $cl -match [regex]::Escape($sid) -and $cl -match ' -p ') {
                $isWake = $true
            }
            else { continue }
        }
        if (-not $isWake) { continue }
        $ppid = 0
        try { $ppid = [int]$row.ParentProcessId } catch { $ppid = 0 }
        $parentAlive = ($ppid -gt 0) -and (Test-WatchProcessAlive -ProcessId $ppid)
        if ($parentAlive -and $ppid -eq $PID) { continue } # ours, still running
        if ($parentAlive) { continue } # another live parent owns it
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        Write-WatchLog ('wake orphan reaped pid={0} parent={1} session={2}' -f $procId, $ppid, $sid)
        $killed++
    }
    return $killed
}

function Sync-WatchWakeLifecycle {
    # FR #91: reap finished/timed-out wakes; dequeue next FROM when idle.
    # FR #99: also run no-CPU hang detection (may rotate session).
    param(
        $State,
        [datetime]$Now = $(Get-Date),
        [switch]$StartNext
    )
    if (-not $State) { return $State }
    if (Get-Command Update-WatchPendingForwardHang -ErrorAction SilentlyContinue) {
        $State = Update-WatchPendingForwardHang -State $State
        if ($State.PSObject.Properties.Name -contains 'seatUnhealthy' -and [bool]$State.seatUnhealthy) {
            return $State
        }
    }
    $wp = 0
    if ($State.PSObject.Properties.Name -contains 'wakePid') {
        try { $wp = [int]$State.wakePid } catch { $wp = 0 }
    }
    $started = $null
    if ($State.PSObject.Properties.Name -contains 'wakeStartedUtc' -and $State.wakeStartedUtc) {
        try { $started = [datetime]$State.wakeStartedUtc } catch { $started = $null }
    }
    $kind = 'wake'
    if ($State.PSObject.Properties.Name -contains 'wakeKind' -and $State.wakeKind) {
        $kind = [string]$State.wakeKind
    }
    $sid = ''
    if ($State.sessionId) { $sid = [string]$State.sessionId }

    if ($wp -gt 0) {
        $alive = Test-WatchProcessAlive -ProcessId $wp
        $timeoutSec = [int]$script:WakeTimeoutSeconds
        if ($timeoutSec -le 0) { $timeoutSec = 1800 }
        $age = 0.0
        if ($started) { $age = ($Now - $started).TotalSeconds }
        if ($alive -and $started -and $age -ge $timeoutSec) {
            Stop-Process -Id $wp -Force -ErrorAction SilentlyContinue
            $msg = ('wake timeout kind={0} session={1} pid={2} ageSec={3}' -f $kind, $sid, $wp, [int]$age)
            Write-WatchSeatTranscript $msg
            $State = Clear-WatchWakeState -State $State -Reason $msg
            $wp = 0
        }
        elseif (-not $alive) {
            $msg = ('wake cleared kind={0} session={1} pid={2} (process gone)' -f $kind, $sid, $wp)
            Write-WatchSeatTranscript $msg
            $State = Clear-WatchWakeState -State $State -Reason $msg
            $wp = 0
        }
    }

    if ($StartNext -and $wp -le 0 -and -not (Test-WatchWakeInFlight -State $State)) {
        $pop = Pop-WatchWakeQueue -State $State
        $State = $pop.State
        if ($pop.Line) {
            Write-WatchLog 'forward dequeue next FROM'
            $State = Send-IrcLineToSession -State $State -Line $pop.Line
        }
    }
    return $State
}

function Read-WatchState {
    if (-not (Test-Path -LiteralPath $script:StatePath)) { return $null }
    try {
        return (Get-Content -LiteralPath $script:StatePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch { return $null }
}

function Write-WatchState {
    param($Obj)
    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($script:StatePath, ($Obj | ConvertTo-Json -Depth 6), $utf8)
}

function Reset-WatchSessionForNew {
    param($State)
    $State.sessionId = [guid]::NewGuid().ToString()
    $State.seenSession = $false
    $State.rootPid = 0
    if ($State.PSObject.Properties['ircLogOffset']) {
        $State.PSObject.Properties.Remove('ircLogOffset')
    }
    if ($State.PSObject.Properties['listenOffset']) {
        $State.PSObject.Properties.Remove('listenOffset')
    }
    if ($State.PSObject.Properties.Name -contains 'cursorPrintOnly') {
        $State.PSObject.Properties.Remove('cursorPrintOnly')
    }
    if ($State.PSObject.Properties.Name -contains 'cursorSessionValid') {
        $State.PSObject.Properties.Remove('cursorSessionValid')
    }
    if ($State.PSObject.Properties.Name -contains 'cursorChatCreated') {
        $State.PSObject.Properties.Remove('cursorChatCreated')
    }
    return $State
}

function Get-GrokAgentPath {
    $p = Join-Path $env:USERPROFILE '.grok\bin\agent.exe'
    if (Test-Path -LiteralPath $p) { return (Resolve-Path $p).Path }
    $cmd = Get-Command agent.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'grok agent.exe not found (~/.grok/bin/agent.exe).'
}

function Get-CursorAgentCmd {
    $p = Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.cmd'
    if (Test-Path -LiteralPath $p) { return (Resolve-Path $p).Path }
    $cmd = Get-Command agent.cmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'cursor agent.cmd not found (%LOCALAPPDATA%\cursor-agent\agent.cmd).'
}

function Get-CursorAgentPs1 {
    $cmd = Get-CursorAgentCmd
    $ps1 = Join-Path ([IO.Path]::GetDirectoryName($cmd)) 'cursor-agent.ps1'
    if (Test-Path -LiteralPath $ps1) { return (Resolve-Path $ps1).Path }
    return $cmd
}

function New-CursorChatSessionId {
    param(
        [string]$AgentCmd,
        [string]$WorkDir
    )
    $outFile = Join-Path $script:StateDir 'create-chat.out.txt'
    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $valid = $false
    $sid = [guid]::NewGuid().ToString()
    try {
        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList @(
            '/c', "`"$AgentCmd`" create-chat > `"$outFile`" 2>&1"
        ) -WorkingDirectory $WorkDir -WindowStyle Hidden -Wait -PassThru
        if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $outFile)) {
            $out = Get-Content -LiteralPath $outFile -Raw -Encoding UTF8
            if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
                $sid = $Matches[1].ToLower()
                $valid = $true
            }
        }
    }
    finally { $ErrorActionPreference = $prev }
    if (-not $valid) {
        Write-WatchLog 'create-chat failed - local session id only; agent -p will not use --resume until a run succeeds'
    }
    return [pscustomobject]@{ SessionId = $sid; ServerChat = $valid }
}

function Set-CursorPrintOnlyMode {
    param($State, [switch]$Enable)
    if ($Enable) {
        $State | Add-Member -NotePropertyName 'cursorPrintOnly' -NotePropertyValue $true -Force
        $State.rootPid = 0
        Write-WatchLog 'cursor print-only mode (no TUI relaunch); IRC still forwarded with agent -p'
    }
    else {
        if ($State.PSObject.Properties.Name -contains 'cursorPrintOnly') {
            $State.PSObject.Properties.Remove('cursorPrintOnly')
        }
    }
    return $State
}

function Test-CursorPrintOnlyMode {
    param($State)
    return ($State.PSObject.Properties.Name -contains 'cursorPrintOnly') -and [bool]$State.cursorPrintOnly
}

function Test-CursorAgentForwardBusy {
    param([string]$SessionId)
    $sid = ([string]$SessionId).Trim()
    $sidPat = if ($sid) { [regex]::Escape($sid) } else { '' }
    $rows = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    foreach ($row in $rows) {
        $cl = [string]$row.CommandLine
        if ([string]$row.Name -eq 'powershell.exe' -and $cl -match 'forward-cursor\.ps1') {
            return $true
        }
        if ($sidPat -and $cl -match 'cursor-agent' -and $cl -match $sidPat -and $cl -match ' -p ') {
            return $true
        }
    }
    return $false
}

function Test-CursorAgentNodeIsProtected {
    param([string]$CommandLine)
    $cl = [string]$CommandLine
    if ($cl -match 'Git task ') { return $true }
    if ($cl -match 'long-running-background-tasks') { return $true }
    return $false
}

function Find-CursorAgentPidBySession {
    param([string]$SessionId)
    $sid = ([string]$SessionId).Trim()
    if (-not $sid) { return 0 }
    $pat = [regex]::Escape($sid)
    foreach ($procName in @('node.exe', 'Cursor.exe')) {
        $rows = @(Get-CimInstance Win32_Process -Filter "Name='$procName'" -ErrorAction SilentlyContinue)
        foreach ($row in $rows) {
            $cl = [string]$row.CommandLine
            if ($cl -match 'cursor-agent' -and $cl -match $pat) {
                return [int]$row.ProcessId
            }
        }
    }
    return 0
}

function Find-CursorInteractiveAgentUnderRoot {
    param([int]$RootPid)
    if ($RootPid -le 0) { return 0 }
    foreach ($id in (Get-DescendantPids -RootPid $RootPid)) {
        $row = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
        if (-not $row) { continue }
        $cl = [string]$row.CommandLine
        if ($cl -match 'cursor-agent' -and $cl -notmatch ' -p ') {
            return [int]$id
        }
    }
    return 0
}

function Sync-CursorSessionFromComposer {
    param(
        $State,
        [int]$ComposerPid
    )
    if ($ComposerPid -le 0) { return $State }
    $row = Get-CimInstance Win32_Process -Filter "ProcessId=$ComposerPid" -ErrorAction SilentlyContinue
    if (-not $row) { return $State }
    $cl = [string]$row.CommandLine
    if ($cl -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        $found = $Matches[1].ToLower()
        if ([string]$State.sessionId -ne $found) {
            Write-WatchLog "cursor composer session id=$found (was $($State.sessionId))"
            $State.sessionId = $found
        }
        $State | Add-Member -NotePropertyName 'cursorSessionValid' -NotePropertyValue $true -Force
    }
    return $State
}

function Get-CommitHeadroomGb {
    try {
        $cp = Get-Counter '\Memory\Committed Bytes', '\Memory\Commit Limit' -ErrorAction Stop
        $cb = $cp.CounterSamples | Where-Object { $_.Path -like '*Committed Bytes*' } | Select-Object -ExpandProperty CookedValue
        $cl = $cp.CounterSamples | Where-Object { $_.Path -like '*Commit Limit*' } | Select-Object -ExpandProperty CookedValue
        return [pscustomobject]@{
            FreeGb  = [math]::Round(($cl - $cb) / 1GB, 2)
            LimitGb = [math]::Round($cl / 1GB, 2)
        }
    }
    catch {
        return [pscustomobject]@{ FreeGb = -1; LimitGb = -1 }
    }
}

function Get-CursorTuiMissNodeWhy {
    $head = Get-CommitHeadroomGb
    if ($head.FreeGb -ge 0 -and $head.FreeGb -lt 0.5) { return 'low commit' }
    return 'launcher exited or node never appeared (not cmd.exe prompt-on-argv)'
}

function Write-CursorAgentProcessSnapshot {
    param([string]$Reason)
    $rows = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | Where-Object {
            [string]$_.CommandLine -match 'cursor-agent'
        })
    $head = Get-CommitHeadroomGb
    Write-WatchLog ("{0} commitFreeGb={1} limitGb={2} cursor-agentNodes={3}" -f $Reason, $head.FreeGb, $head.LimitGb, $rows.Count)
    foreach ($row in $rows) {
        $ws = [math]::Round($row.WorkingSetSize / 1MB, 0)
        $mode = if ([string]$row.CommandLine -match ' -p ') { '-p' } elseif ([string]$row.CommandLine -match '--resume') { 'resume' } else { 'other' }
        $sid = '?'
        if ([string]$row.CommandLine -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $sid = $Matches[1].Substring(0, 8)
        }
        Write-WatchLog ("  node pid={0} wsMb={1} mode={2} session~={3}" -f $row.ProcessId, $ws, $mode, $sid)
    }
}

function Stop-CursorAgentNodesForSession {
    param([string]$SessionId)
    $sid = ([string]$SessionId).Trim()
    if (-not $sid) { return 0 }
    $pat = [regex]::Escape($sid)
    $stopped = 0
    $rows = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | Where-Object {
            [string]$_.CommandLine -match 'cursor-agent'
        })
    foreach ($row in $rows) {
        $cl = [string]$row.CommandLine
        if ($cl -notmatch $pat) { continue }
        if (Test-CursorAgentNodeIsProtected -CommandLine $cl) {
            Write-WatchLog ("prune skip protected cursor-agent pid={0} (Git/fleet job)" -f $row.ProcessId)
            continue
        }
        Write-WatchLog ("prune watch-session cursor-agent pid={0} session={1}" -f $row.ProcessId, $sid.Substring(0, 8))
        Stop-WatchedTree -RootPid ([int]$row.ProcessId)
        $stopped++
    }
    return $stopped
}

function Stop-OrphanCursorWatchForwards {
    # Only prune hung forwards for THIS slot's StateDir. Never touch another seat's
    # forward-cursor.ps1 / live Git-task nodes.
    $stopped = 0
    $escDir = $null
    if ($script:StateDir) { $escDir = [regex]::Escape([IO.Path]::GetFullPath($script:StateDir)) }
    $rows = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    foreach ($row in $rows) {
        $cl = [string]$row.CommandLine
        if (Test-CursorAgentNodeIsProtected -CommandLine $cl) { continue }
        if ([string]$row.Name -eq 'powershell.exe' -and $cl -match 'forward-cursor') {
            if ($escDir -and $cl -notmatch $escDir) { continue }
            Write-WatchLog ("prune hung watch forward powershell pid={0}" -f $row.ProcessId)
            Stop-WatchedTree -RootPid ([int]$row.ProcessId)
            $stopped++
            continue
        }
        if ([string]$row.Name -eq 'node.exe' -and $cl -match 'cursor-agent' -and $cl -match 'worker-server') {
            $parent = Get-Process -Id ([int]$row.ParentProcessId) -ErrorAction SilentlyContinue
            if (-not $parent) {
                Write-WatchLog ("prune orphan worker-server pid={0}" -f $row.ProcessId)
                Stop-Process -Id $row.ProcessId -Force -ErrorAction SilentlyContinue
                $stopped++
            }
        }
    }
    return $stopped
}

function Get-LiveWatchWorkerRows {
    param(
        [string]$Kind,
        [string]$SeatHome,
        [int]$ExcludePid = 0
    )
    $kindFlag = if ($Kind -eq 'grok') { '-Grok' } else { '-Cursor' }
    $full = $null
    $isDefaultSlot1 = $false
    if ($seatHome) {
        $full = [IO.Path]::GetFullPath($seatHome).TrimEnd('\')
        $base = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ('.agentic-irc-watch-{0}' -f $Kind))).TrimEnd('\')
        $isDefaultSlot1 = ($full -eq $base)
    }
    $hits = @()
    foreach ($row in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
        $opid = [int]$row.ProcessId
        if ($ExcludePid -gt 0 -and $opid -eq $ExcludePid) { continue }
        $cl = [string]$row.CommandLine
        if ($cl -notmatch 'Watch-AgentHealth\.ps1') { continue }
        if ($cl -notmatch '-WatchWorker') { continue }
        if ($cl -notmatch [regex]::Escape($kindFlag)) { continue }
        if ($full) {
            $esc = [regex]::Escape($full)
            $mentionsHome = ($cl -match $esc)
            $defaultNoFlag = ($isDefaultSlot1 -and $cl -notmatch '-IrcHome')
            if (-not $mentionsHome -and -not $defaultNoFlag) { continue }
        }
        $hits += ,$row
    }
    return $hits
}

function Test-WatchHomeInUse {
    param(
        [string]$SeatHome,
        [int]$ExcludePid = 0
    )
    return (@(Get-LiveWatchWorkerRows -Kind $script:KindName -SeatHome $seatHome -ExcludePid $ExcludePid).Count -gt 0)
}

function Get-WatchSlotCandidates {
    param([string]$Kind)
    $base = Join-Path $env:USERPROFILE ('.agentic-irc-watch-{0}' -f $Kind)
    $list = @([IO.Path]::GetFullPath($base))
    for ($i = 2; $i -le 16; $i++) {
        $list += ,([IO.Path]::GetFullPath(('{0}-{1}' -f $base, $i)))
    }
    return $list
}

function Get-WatchSlotNumberFromHome {
    param([string]$SeatHome, [string]$Kind)
    $full = [IO.Path]::GetFullPath($seatHome).TrimEnd('\')
    $base = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ('.agentic-irc-watch-{0}' -f $Kind))).TrimEnd('\')
    if ($full -eq $base) { return 1 }
    if ($full -match ('^{0}-([0-9]+)$' -f [regex]::Escape($base))) {
        return [int]$Matches[1]
    }
    return 1
}

function Resolve-NextFreeWatchIrcHome {
    param(
        [string]$Kind,
        [int]$ExcludePid = 0
    )
    foreach ($h in @(Get-WatchSlotCandidates -Kind $Kind)) {
        if (-not (Test-WatchHomeInUse -SeatHome $h -ExcludePid $ExcludePid)) {
            return $h
        }
    }
    throw ("All 16 watch-{0} slots are in use (live Watch-AgentHealth workers)." -f $Kind)
}

function Get-WatchBoundIrcHome {
    # FR #97: always the seat-bound home (never a sibling slot).
    if ($script:BoundIrcHome) {
        return [IO.Path]::GetFullPath([string]$script:BoundIrcHome)
    }
    if ($script:IrcHome) {
        return [IO.Path]::GetFullPath([string]$script:IrcHome)
    }
    return $null
}

function Bind-WatchSlot {
    # Pick next free IRC home (or keep -IrcHome), isolate state/log/worker pid per slot.
    # FR #97 CAST IRON: set $script:IrcHome (not a function-local $IrcHome) so Ensure-WatchIrcSeat,
    # Initialize-WatchIrcHome, irc.log tail, outbox, and Disconnect all use THIS seat only.
    if ($script:IrcHomeExplicit) {
        $resolved = [IO.Path]::GetFullPath($IrcHome)
    }
    else {
        $resolved = Resolve-NextFreeWatchIrcHome -Kind $script:KindName -ExcludePid $PID
    }
    if (Test-ForbiddenIrcHome -ResolvedHome $resolved) {
        throw "Refusing IrcHome $resolved (talk-seat / bobiverse). Use .agentic-irc-watch-*."
    }
    $slot = Get-WatchSlotNumberFromHome -SeatHome $resolved -Kind $script:KindName
    $script:ClientSlot = $slot
    $script:BoundIrcHome = $resolved
    $script:IrcHome = $resolved
    # Keep param-scope name in sync for any leftover $IrcHome reads in this script.
    Set-Variable -Name IrcHome -Scope Script -Value $resolved
    $script:StateDir = Join-Path $env:USERPROFILE ('.grok\agent-health\watch-{0}-{1}' -f $script:KindName, $slot)
    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    New-Item -ItemType Directory -Force -Path $resolved | Out-Null
    $script:StatePath = Join-Path $script:StateDir 'state.json'
    $script:WorkerPidPath = Join-Path $script:StateDir 'watch-worker.pid'
    if (-not $LogPath) {
        $desk = Join-Path $env:USERPROFILE 'Desktop\Watch-AgentHealth'
        New-Item -ItemType Directory -Force -Path $desk | Out-Null
        if ($slot -le 1) {
            $script:LogFile = Join-Path $desk 'Watch-AgentHealth.log'
        }
        else {
            $script:LogFile = Join-Path $desk ('Watch-AgentHealth-{0}.log' -f $slot)
        }
    }
    else {
        $script:LogFile = $LogPath
    }
    # Create log only if missing — never truncate another seat's log (FR #97).
    if (-not (Test-Path -LiteralPath $script:LogFile)) {
        $parent = Split-Path -Parent $script:LogFile
        if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        New-Item -ItemType File -Path $script:LogFile -Force | Out-Null
    }
    Write-WatchLog ("bind slot={0} ircHome={1} stateDir={2} log={3}" -f $slot, $resolved, $script:StateDir, $script:LogFile)
}

function Stop-OrphanWatchPythonForHome {
    param([string]$ResolvedHome)
    if (-not $ResolvedHome) { return 0 }
    $resolved = [IO.Path]::GetFullPath($ResolvedHome).TrimEnd('\')
    if (Test-ForbiddenIrcHome -ResolvedHome $resolved) {
        Write-WatchLog 'orphan python prune skipped (forbidden home)'
        return 0
    }
    # Never kill IRC for a home another live watch worker still owns.
    $others = @(Get-LiveWatchWorkerRows -Kind $script:KindName -SeatHome $resolved -ExcludePid $PID)
    if ($others.Count -gt 0) {
        Write-WatchLog ("orphan python prune skipped - {0} live watch worker(s) own {1}" -f $others.Count, $resolved)
        return 0
    }
    $esc = [regex]::Escape($resolved)
    $stopped = 0
    $rows = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            ($cl -match 'irc_listen\.py' -or $cl -match 'irc_agent\.py') -and $cl -match $esc
        })
    foreach ($row in $rows) {
        Write-WatchLog ("prune orphan watch python pid={0} home={1}" -f $row.ProcessId, $resolved)
        Stop-Process -Id $row.ProcessId -Force -ErrorAction SilentlyContinue
        $stopped++
    }
    return $stopped
}

function Stop-OrphanCursorAgentNodesForSlot {
    # Leftover interactive/print cursor-agent nodes for THIS slot session only are
    # handled via Stop-CursorAgentNodesForSession. Also prune stray -p nodes that
    # reference this StateDir path in their command line.
    $stopped = 0
    if (-not $script:StateDir) { return 0 }
    $escDir = [regex]::Escape([IO.Path]::GetFullPath($script:StateDir))
    foreach ($row in @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue)) {
        $cl = [string]$row.CommandLine
        if ($cl -notmatch 'cursor-agent') { continue }
        if (Test-CursorAgentNodeIsProtected -CommandLine $cl) { continue }
        if ($cl -notmatch $escDir) { continue }
        Write-WatchLog ("prune orphan cursor-agent node pid={0} (slot stateDir)" -f $row.ProcessId)
        Stop-Process -Id $row.ProcessId -Force -ErrorAction SilentlyContinue
        $stopped++
    }
    return $stopped
}

function Clear-OrphanWatchProcessesOnStart {
    param([string]$ResolvedHome)
    $n = 0
    $n += Stop-OrphanCursorWatchForwards
    $n += Stop-OrphanCursorAgentNodesForSlot
    $n += Stop-OrphanWatchPythonForHome -ResolvedHome $ResolvedHome
    if ($n -gt 0) {
        Write-WatchLog "watch start pruned $n orphan python/node process(es) for this slot"
    }
    return $n
}

function Test-CursorUseResumeCli {
    param($State)
    if ($State.PSObject.Properties.Name -contains 'cursorSessionValid' -and [bool]$State.cursorSessionValid) {
        return $true
    }
    if ([bool]$State.seenSession -and -not [string]::IsNullOrWhiteSpace([string]$State.sessionId)) {
        return $true
    }
    return $false
}

function Test-CursorUseResumeForTui {
    param($State, [switch]$ResumeShortcut)
    if (Test-CursorUseResumeCli -State $State) {
        if ($ResumeShortcut -and -not (($State.PSObject.Properties.Name -contains 'cursorSessionValid') -and [bool]$State.cursorSessionValid)) {
            Write-WatchLog 'cursor Resume: TUI/agent --resume with stored session id'
        }
        return $true
    }
    if ($ResumeShortcut) {
        Write-WatchLog 'cursor Resume: no stored session; TUI starts fresh'
    }
    return $false
}

function Resolve-CursorWatchRootPid {
    param(
        [string]$SessionId,
        [int]$LauncherPid
    )
    if ($LauncherPid -gt 0) {
        $row = Get-CimInstance Win32_Process -Filter "ProcessId=$LauncherPid" -ErrorAction SilentlyContinue
        if ($row) {
            $cl = [string]$row.CommandLine
            if ($cl -match 'cursor-agent' -and $cl -notmatch ' -p ') {
                return [int]$LauncherPid
            }
        }
        $under = Find-CursorInteractiveAgentUnderRoot -RootPid $LauncherPid
        if ($under -gt 0) { return $under }
    }
    $bySession = Find-CursorAgentPidBySession -SessionId $SessionId
    if ($bySession -gt 0) { return $bySession }
    return 0
}

function Test-ForbiddenIrcHome {
    param([string]$ResolvedHome)
    $full = [IO.Path]::GetFullPath($ResolvedHome).TrimEnd('\')
    $ban = @(
        (Join-Path $env:USERPROFILE '.agentic-irc-cursor'),
        (Join-Path $env:USERPROFILE '.agentic-irc-cursor-2'),
        (Join-Path $env:USERPROFILE '.agentic-irc-bobiverse')
    ) | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
    return ($ban -contains $full)
}

function Initialize-WatchIrcHome {
    param($State)
    # FR #97: always bound home for this seat
    $home = Get-WatchBoundIrcHome
    if (-not $home) { $home = [string]$IrcHome }
    $resolved = [IO.Path]::GetFullPath($home)
    if (Test-ForbiddenIrcHome -ResolvedHome $resolved) {
        throw "Refusing IrcHome $resolved (talk-seat / Watch home). Use .agentic-irc-watch-*."
    }
    $State.ircHome = $resolved
    $State | Add-Member -NotePropertyName 'clientSlot' -NotePropertyValue $script:ClientSlot -Force
    return $State
}

function Resolve-AgenticIrcScriptsDir {
    # Prefer a complete tree (irc_agent imports bob_recycle). Skills copy can lag.
    foreach ($c in @(
            'C:\ai\agentic_irc\scripts',
            'D:\ai\agentic_irc\scripts',
            'E:\ai\agentic_irc\scripts',
            'C:\src\agentic_irc\scripts',
            (Join-Path $env:USERPROFILE '.grok\skills\agentic-irc\scripts')
        )) {
        if (-not $c) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $c 'irc_agent.py'))) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $c 'bob_recycle.py'))) { continue }
        return $c
    }
    return $null
}

function Get-WatchMachineId {
    if ($env:BOB_MACHINE_ID) { return ([string]$env:BOB_MACHINE_ID).Trim().ToLowerInvariant() }
    try {
        $cfg = Join-Path $env:USERPROFILE '.grok\bob-bridge\..\..\ai\agentic_build\config\bobiverse.json'
    } catch { }
    foreach ($p in @(
            'C:\ai\agentic_build\config\bobiverse.json',
            'D:\ai\agentic_build\config\bobiverse.json'
        )) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            $j = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.thisMachine) { return ([string]$j.thisMachine).Trim().ToLowerInvariant() }
            if ($j.machineId) { return ([string]$j.machineId).Trim().ToLowerInvariant() }
        } catch { }
    }
    # Never default to another box's id (seat would JOIN #flamingo as flamingo-<pid> from here).
    return ([string]$env:COMPUTERNAME).Trim().ToLowerInvariant()
}

function Get-WatchIrcListenRows {
    param([string]$ResolvedHome)
    $watchHome = [IO.Path]::GetFullPath($ResolvedHome).TrimEnd('\')
    $esc = [regex]::Escape($watchHome)
    return @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'irc_listen\.py' -and $cl -match $esc
        })
}

function Resolve-WatchSeatPid {
    # coordinator.pid outlives the seat that wrote it. A dead seat= pid gives the new irc_agent the
    # talk-seat nick <mid>-<deadpid>; irc_agent's seat liveness loop then QUITs ("seat ended").
    # Honour seat= only while that process is running; otherwise this watcher is the seat.
    param([string]$CoordPath, [int]$Default = $PID)
    if ($CoordPath -and (Test-Path -LiteralPath $CoordPath)) {
        foreach ($line in @(Get-Content -LiteralPath $CoordPath -ErrorAction SilentlyContinue)) {
            if ($line -match '^seat=(\d+)\s*$') {
                $s = [int]$Matches[1]
                if ($s -gt 0 -and (Get-Process -Id $s -ErrorAction SilentlyContinue)) { return $s }
                Write-WatchLog ("irc ensure ignoring stale coordinator seat={0} (not running); seat={1}" -f $s, $Default)
            }
        }
    }
    return $Default
}

function Test-WatchProcessAlive {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $false }
    return $null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)
}

function Test-WatchRootMatchesSession {
    # True when rootPid is alive and its command line contains the watch session id (FR #89 adopt).
    param(
        [int]$RootPid,
        [string]$SessionId,
        [string]$CommandLine = ''
    )
    if ($RootPid -le 0) { return $false }
    $sid = ([string]$SessionId).Trim()
    if (-not $sid) { return $false }
    if (-not (Test-WatchProcessAlive -ProcessId $RootPid)) { return $false }
    $cl = [string]$CommandLine
    if (-not $cl) {
        $row = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $RootPid) -ErrorAction SilentlyContinue
        if (-not $row) { return $false }
        $cl = [string]$row.CommandLine
    }
    if (-not $cl) { return $false }
    return $cl.IndexOf($sid, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Try-AdoptLiveWatchAgent {
    # FR #89: on monitor restart, adopt state.rootPid when it still hosts this session — no relaunch.
    param(
        $State,
        [string]$CommandLine = ''
    )
    if (-not $State) { return $null }
    $rp = 0
    try { $rp = [int]$State.rootPid } catch { $rp = 0 }
    if ($rp -le 0) { return $null }
    $sid = [string]$State.sessionId
    if (-not (Test-WatchRootMatchesSession -RootPid $rp -SessionId $sid -CommandLine $CommandLine)) {
        return $null
    }
    $kind = [string]$State.kind
    if (-not $kind) { $kind = $script:KindName }
    Write-WatchLog ("adopt live agent rootPid={0} session={1} (skip Start-WatchedAgent)" -f $rp, $sid)
    return [pscustomobject]@{
        Kind    = $kind
        Exe     = ''
        Process = $null
        RootPid = $rp
        State   = $State
    }
}

function Resolve-StableWatchIrcNick {
    # Keep seat nick across monitor PID change while irc_agent for that nick is live (FR #89).
    # FR #103: loop seats use -Nick override (non-worker grammar).
    param(
        $State,
        [string]$MachineId,
        [string]$ResolvedHome,
        [int]$DefaultSeatPid,
        [object[]]$AgentRows = @()
    )
    if ($script:WatchNickOverride) {
        return ([string]$script:WatchNickOverride).Trim()
    }
    $mid = ([string]$MachineId).Trim().ToLowerInvariant()
    $agents = @($AgentRows)
    if ($agents.Count -eq 0 -and $ResolvedHome) {
        $agents = @(Get-WatchIrcAgentRows -ResolvedHome $ResolvedHome)
    }
    foreach ($row in $agents) {
        $cl = [string]$row.CommandLine
        if ($cl -match '--nick\s+(\S+)') {
            $n = $Matches[1].Trim()
            if ($n -match ('^{0}-(\d+)$' -f [regex]::Escape($mid))) {
                return $n
            }
        }
    }
    $prev = ''
    if ($State -and $State.PSObject.Properties['ircNick']) {
        $prev = ([string]$State.ircNick).Trim()
    }
    if ($prev -match ('^{0}-(\d+)$' -f [regex]::Escape($mid))) {
        # Prefer previous nick when seatNickPid is stored (monitor hotpatch) even if agent is briefly down —
        # Ensure still reuses the same nick number so the seat identity does not flip.
        $stored = 0
        if ($State.PSObject.Properties['seatNickPid']) {
            try { $stored = [int]$State.seatNickPid } catch { $stored = 0 }
        }
        $suffix = [int]$Matches[1]
        if ($stored -gt 0 -and $stored -eq $suffix) {
            return $prev
        }
        if ($stored -gt 0) {
            return ('{0}-{1}' -f $mid, $stored)
        }
        return $prev
    }
    if ($State -and $State.PSObject.Properties['seatNickPid']) {
        try {
            $sp = [int]$State.seatNickPid
            if ($sp -gt 0) { return ('{0}-{1}' -f $mid, $sp) }
        }
        catch { }
    }
    $seatPid = $DefaultSeatPid
    if ($seatPid -le 0) { $seatPid = $PID }
    return ('{0}-{1}' -f $mid, $seatPid)
}

function Clear-WatchStaleQuitRequest {
    # Disconnect-WatchIrc leaves quit.req / agent.quit.request for the irc_agent it stops. With no
    # irc_agent live on this home they are leftovers, and agent_control.consume_quit_request has no
    # age check - the next irc_agent would QUIT right after connecting.
    param([string]$ResolvedHome)
    foreach ($leaf in @('agent.quit.request', 'quit.req')) {
        $p = Join-Path $ResolvedHome $leaf
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            Remove-Item -LiteralPath $p -Force -ErrorAction Stop
            Write-WatchLog ("irc ensure removed stale {0}" -f $leaf)
        }
        catch {
            Write-WatchLog ("irc ensure could not remove stale {0}: {1}" -f $leaf, $_.Exception.Message)
        }
    }
}

function Get-WatchSeatChannels {
    # CAST IRON (Simon 2026-09-25): fleet worker / watch seats JOIN their own #{machine} ONLY.
    # Never #bobiverse (bob-{machine} ears, Jeeves and humans only) and never #agentic_irc or extras.
    # FR #103: loop seats JOIN -Channel only (still never #bobiverse / #agentic_irc).
    param([string]$MachineId)
    if ($script:WatchChannelOverride) {
        $c = ([string]$script:WatchChannelOverride).Trim()
        if ($c -notmatch '^#') { $c = '#' + $c.TrimStart('#') }
        $c = $c.ToLowerInvariant()
        if ($c -match '(?i)^#(bobiverse|agentic_irc)$') {
            throw ("Loop/fleet seat must not JOIN {0}" -f $c)
        }
        return $c
    }
    $m = ([string]$MachineId).Trim().TrimStart('#').ToLowerInvariant()
    if (-not $m) { $m = ([string]$env:COMPUTERNAME).Trim().ToLowerInvariant() }
    return ('#' + $m)
}

function Test-WatchWorkerNickGrammar {
    # gh-Jeeves / agentic_irc treat {machine}-{pid} as a shop worker.
    param([string]$Nick)
    return ([string]$Nick -match '^[A-Za-z0-9_]+-\d+$')
}

function Ensure-WatchIrcSeat {
    # CAST IRON (Simon 2026-09-23): systray / Watch-AgentHealth launch MUST connect
    # irc_agent + irc_listen on this home and JOIN its own #{machine} ONLY
    # (CAST IRON 2026-09-25: workers never join #bobiverse / #agentic_irc). Monitor then forwards FROM.
    # FR #97: never adopt another slot's home/agent/listen.
    param($State)
    $bound = Get-WatchBoundIrcHome
    $seatHome = [string]$State.ircHome
    if ($bound) {
        # Force state onto this seat's bound home (do not keep a sibling home from stale state.json).
        if (-not $seatHome -or ([IO.Path]::GetFullPath($seatHome).TrimEnd('\') -ne $bound.TrimEnd('\'))) {
            Write-WatchLog ("irc ensure rebasing state.ircHome from {0} to bound {1}" -f $seatHome, $bound)
            $seatHome = $bound
            $State.ircHome = $bound
        }
    }
    if (-not $seatHome) { return $State }
    $resolved = [IO.Path]::GetFullPath($seatHome)
    if (Test-ForbiddenIrcHome -ResolvedHome $resolved) {
        Write-WatchLog 'irc ensure skipped (forbidden home)'
        return $State
    }
    if ($bound -and ($resolved.TrimEnd('\') -ne $bound.TrimEnd('\'))) {
        Write-WatchLog ("irc ensure refused foreign home {0} (bound={1})" -f $resolved, $bound)
        return $State
    }
    New-Item -ItemType Directory -Force -Path $resolved | Out-Null
    $agents = @(Get-WatchIrcAgentRows -ResolvedHome $resolved)
    $listens = @(Get-WatchIrcListenRows -ResolvedHome $resolved)
    if ($agents.Count -gt 1 -or $listens.Count -gt 1) {
        Write-WatchLog ("irc ensure collapsing duplicates agent={0} listen={1}" -f $agents.Count, $listens.Count)
        foreach ($row in @($agents + $listens)) {
            Stop-Process -Id $row.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 500
        $agents = @()
        $listens = @()
    }
    if ($agents.Count -gt 0 -and $listens.Count -gt 0) {
        # FR #102: only treat as live if agent/listen PIDs are still running (Get-CimInstance rows
        # can race; also rewrite coordinator.pid for this monitor seat).
        $agentAlive = Test-WatchProcessAlive -ProcessId ([int]$agents[0].ProcessId)
        $listenAlive = Test-WatchProcessAlive -ProcessId ([int]$listens[0].ProcessId)
        if ($agentAlive -and $listenAlive) {
            $nick = ''
            if ([string]$agents[0].CommandLine -match '--nick\s+(\S+)') { $nick = $Matches[1] }
            Write-WatchLog ("irc seat already up nick={0} agent={1} listen={2} home={3}" -f $nick, $agents[0].ProcessId, $listens[0].ProcessId, $resolved)
            if ($nick) {
                $State | Add-Member -NotePropertyName 'ircNick' -NotePropertyValue $nick -Force
                if ($nick -match '-(\d+)$') {
                    $State | Add-Member -NotePropertyName 'seatNickPid' -NotePropertyValue ([int]$Matches[1]) -Force
                }
            }
            $coordPath = Join-Path $resolved 'coordinator.pid'
            @(
                "nick=$nick"
                "seat=$PID"
                "listen=$($listens[0].ProcessId)"
                "agent=$($agents[0].ProcessId)"
                "home=$resolved"
                "channels=$(Get-WatchSeatChannels -MachineId (Get-WatchMachineId))"
            ) | Set-Content -LiteralPath $coordPath -Encoding utf8
            return $State
        }
        Write-WatchLog ("irc ensure stale live rows agentAlive={0} listenAlive={1} - relaunch" -f $agentAlive, $listenAlive)
        foreach ($row in @($agents + $listens)) {
            Stop-Process -Id $row.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 400
        $agents = @()
        $listens = @()
    }
    $scripts = Resolve-AgenticIrcScriptsDir
    if (-not $scripts) {
        Write-WatchLog 'irc ensure FAILED: agentic_irc scripts not found (irc_agent.py)'
        return $State
    }
    $pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
    if (-not (Test-Path -LiteralPath $pwFile)) {
        Write-WatchLog "irc ensure FAILED: missing $pwFile"
        return $State
    }
    $mid = Get-WatchMachineId
    $coordPath = Join-Path $resolved 'coordinator.pid'
    $seatPid = Resolve-WatchSeatPid -CoordPath $coordPath -Default $PID
    if ($agents.Count -eq 0) {
        Clear-WatchStaleQuitRequest -ResolvedHome $resolved
    }
    # FR #89: stable nick across monitor restart (do not flip to new monitor PID while seat is known).
    $nick = Resolve-StableWatchIrcNick -State $State -MachineId $mid -ResolvedHome $resolved -DefaultSeatPid $seatPid -AgentRows $agents
    if ($nick -match '-(\d+)$') {
        $seatPid = [int]$Matches[1]
        $State | Add-Member -NotePropertyName 'seatNickPid' -NotePropertyValue $seatPid -Force
    }
    $State | Add-Member -NotePropertyName 'ircNick' -NotePropertyValue $nick -Force
    $channels = Get-WatchSeatChannels -MachineId $mid
    $env:AGENTIC_IRC_PASSWORD = (Get-Content -LiteralPath $pwFile -Raw).Trim()
    $env:AGENTIC_IRC_DEBUG = '1'
    $env:AGENTIC_IRC_SEAT_PID = "$seatPid"
    $py = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $py) {
        Write-WatchLog 'irc ensure FAILED: python not on PATH'
        return $State
    }
    $agentPath = Join-Path $scripts 'irc_agent.py'
    $listenPath = Join-Path $scripts 'irc_listen.py'
    if ($agents.Count -eq 0) {
        Write-WatchLog ("irc ensure start agent nick={0} channels={1} home={2}" -f $nick, $channels, $resolved)
        Start-Process -FilePath $py -ArgumentList (ConvertTo-WatchProcessArgumentString -ArgumentList @(
                '-u', $agentPath,
                '--host', 'irc.ntsa.uk',
                '--port', '6697',
                '--channel', $channels,
                '--home', $resolved,
                '--nick', $nick
            )) -WindowStyle Hidden | Out-Null
        Start-Sleep -Milliseconds 900
    }
    $listens = @(Get-WatchIrcListenRows -ResolvedHome $resolved)
    if ($listens.Count -eq 0) {
        $stdoutLog = Join-Path $resolved 'listen.stdout.log'
        $stderrLog = Join-Path $resolved 'listen.stderr.log'
        Write-WatchLog ("irc ensure start listen home={0}" -f $resolved)
        Start-Process -FilePath $py -ArgumentList (ConvertTo-WatchProcessArgumentString -ArgumentList @('-u', $listenPath, '--home', $resolved)) `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog | Out-Null
        Start-Sleep -Milliseconds 400
    }
    $agents = @(Get-WatchIrcAgentRows -ResolvedHome $resolved)
    $listens = @(Get-WatchIrcListenRows -ResolvedHome $resolved)
    $agentPid = if ($agents.Count -gt 0) { $agents[0].ProcessId } else { '' }
    $listenPid = if ($listens.Count -gt 0) { $listens[0].ProcessId } else { '' }
    @(
        "nick=$nick"
        "seat=$seatPid"
        "listen=$listenPid"
        "agent=$agentPid"
        "home=$resolved"
        "channels=$channels"
    ) | Set-Content -LiteralPath $coordPath -Encoding utf8
    if ($agents.Count -eq 0 -or $listens.Count -eq 0) {
        Write-WatchLog ("irc ensure incomplete agent={0} listen={1}" -f $agentPid, $listenPid)
    }
    else {
        Write-WatchLog ("irc ensure ok nick={0} agent={1} listen={2} channels={3}" -f $nick, $agentPid, $listenPid, $channels)
    }
    $State | Add-Member -NotePropertyName 'ircNick' -NotePropertyValue $nick -Force
    $State | Add-Member -NotePropertyName 'ircChannels' -NotePropertyValue $channels -Force
    return $State
}

function Get-WatchIrcAgentRows {
    param([string]$ResolvedHome)
    $watchHome = [IO.Path]::GetFullPath($ResolvedHome).TrimEnd('\')
    $esc = [regex]::Escape($watchHome)
    return @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'irc_agent\.py' -and $cl -match $esc
        })
}

function Disconnect-WatchIrc {
    param(
        $State,
        [string]$Reason = 'tui closed'
    )
    $watchHome = [string]$State.ircHome
    if (-not $watchHome) { return }
    $resolved = [IO.Path]::GetFullPath($watchHome)
    $bound = Get-WatchBoundIrcHome
    # FR #97: never QUIT/kill another seat's IRC processes
    if ($bound -and ($resolved.TrimEnd('\') -ne $bound.TrimEnd('\'))) {
        Write-WatchLog ("irc disconnect refused foreign home {0} (bound={1})" -f $resolved, $bound)
        return
    }
    if (Test-ForbiddenIrcHome -ResolvedHome $resolved) {
        Write-WatchLog "irc disconnect skipped (forbidden home)"
        return
    }
    if (-not (Test-Path -LiteralPath $resolved)) { return }
    $why = ([string]$Reason).Replace("`r", ' ').Replace("`n", ' ').Trim()
    if (-not $why) { $why = 'tui closed' }
    if ($why.Length -gt 80) { $why = $why.Substring(0, 80) }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText((Join-Path $resolved 'quit.req'), $why, $utf8)
    Write-WatchLog ("irc graceful PART+QUIT requested ({0}) home={1}" -f $why, $resolved)
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        if ((Get-WatchIrcAgentRows -ResolvedHome $resolved).Count -eq 0) { break }
        Start-Sleep -Milliseconds 400
    }
    $left = @(Get-WatchIrcAgentRows -ResolvedHome $resolved)
    foreach ($row in $left) {
        Write-WatchLog ("irc agent still up after QUIT wait pid={0} - stopping" -f $row.ProcessId)
        Stop-Process -Id $row.ProcessId -Force -ErrorAction SilentlyContinue
    }
    $listen = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $cl = [string]$_.CommandLine
            $cl -match 'irc_listen\.py' -and $cl -match [regex]::Escape($resolved)
        })
    foreach ($row in $listen) {
        Stop-Process -Id $row.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Get-CursorSeedPrompt {
    param([string]$ResolvedIrcHome)
    if (Test-WatchNoBored) {
        $chan = if ($script:WatchChannelOverride) { $script:WatchChannelOverride } else { '#{channel}' }
        $nick = if ($script:WatchNickOverride) { $script:WatchNickOverride } else { 'loop-nick' }
        return @(
            'Loop seat online (continuous agent; not a fleet job worker).'
            "IRC home $ResolvedIrcHome. Monitor JOINed $chan as $nick only."
            'No !bored, no ACK/DONE to Jeeves, no fleet job loop. Act on monitor FROM forwards; reply on outbox. No UAT.'
        ) -join ' '
    }
    return @(
        'Watch seat online. Skills: agent-monitor, watch-seat, agentic-irc + agentic_build (harvest-agent-skills; IRC playbooks to agentic_irc).'
        "IRC home $ResolvedIrcHome. Monitor already started irc_agent+irc_listen on this home (own #{machine} channel only)."
        'Monitor posts !bored for you on start, after DONE, and while idle (own #{machine} only). Do not post busy/idle status yourself.'
        'ACK/DONE outbox lines: start with ACK or DONE (no nick: prefix); append PRIVMSG only. Skills watch-seat / bob-git-accept have the exact wire.'
        'You are NOT on IRC by reading irc.log or counting processes — you get IRC only via monitor FROM forwards. Act on those; reply on outbox. No UAT.'
    ) -join ' '
}

function Get-AgentPrompt {
    param([string]$ResolvedIrcHome)
    if (Test-WatchNoBored) {
        $chan = if ($script:WatchChannelOverride) { $script:WatchChannelOverride } else { '#{channel}' }
        $nick = if ($script:WatchNickOverride) { $script:WatchNickOverride } else { 'loop-nick' }
        return @(
            'You are a continuous loop agent on this Windows box (NOT a fleet job worker).'
            'Split: Watch-AgentHealth.ps1 is the deterministic monitor (health, irc_agent+irc_listen, tail irc.log, forward FROM). You do not run or reimplement the monitor.'
            "IRC home: $ResolvedIrcHome. You JOIN only $chan as nick $nick. Never #bobiverse. Never join the fleet shop job loop."
            'HARD RULES: never post !bored; never ACK/DONE/NACK to Jeeves; never !list; never claim busy/idle on the digest webhook.'
            'Take commands only from Simon (or the human operator). Post progress with the project prefix when required (e.g. [dayworks]). Ask Simon questions as QUESTION lines when stuck.'
            'CAST IRON: IRC arrives only as monitor-forwarded FROM lines. Prefer that wake path; do not arm in-session ^FROM TSR.'
            'On each wake: act on the payload if it is for you or Simon asked; reply on outbox to your channel. Bare ping/PING is watcher auto-pong. Then end turn.'
            'Do not stamp UAT. Bob/Simon only. No invented secrets. Do not gut cards or docs.'
        ) -join ' '
    }
    return @(
        'You are a fleet agent on this Windows box (watch seat).'
        'Split: Watch-AgentHealth.ps1 is the deterministic monitor (health, start irc_agent+irc_listen, tail irc.log, forward each IRC PRIVMSG into this session as FROM). You do not run, restart, or reimplement the monitor.'
        'CAST IRON: you are not "on IRC" by probing irc.log / processes. IRC data arrives only as monitor-forwarded FROM lines. Prefer that wake path; do not arm in-session ^FROM TSR.'
        'You are event-driven only off what the monitor forwards (a FROM line) or what Simon types here. Do not idle-wait in chat for the monitor; finish the turn after acting.'
        'Follow skills: agent-monitor + watch-seat (this repo .grok/skills), agentic-irc (no !bobiverse from this seat) and agentic_build. Harvest: harvest-agent-skills for build/fleet; IRC playbooks to SimonBarnett/agentic_irc; AgentMonitor playbooks stay in this repo.'
        "IRC home: $ResolvedIrcHome. Seat JOINs its own #{machine} ONLY (never #bobiverse or #agentic_irc; do not post there). Respond on the target channel in each FROM (outbox). Monitor tails irc.log; you do not."
        'CAST IRON !bored: the monitor posts PRIVMSG #{machine} :!bored for you on seat start, right after your DONE, and every few minutes while idle. Never while busy. Do not post !bored or busy/idle chatter yourself.'
        'Forbidden homes: ~/.agentic-irc-cursor, cursor-2, bobiverse Watch.'
        'On each wake: treat the payload as the task; reply on outbox if addressed or Simon asked the box. Bare ping/PING is auto-ponged by the watcher. Then end turn.'
        "Your IRC nick is nick= in $ResolvedIrcHome\coordinator.pid ({machine}-{monitor pid}, e.g. marchhare-34992). A wake starting FOR YOU is addressed to you - treat a Jeeves assignment (FR|MRB|UAT owner/repo#N url) like an ASSIGN."
        'CAST IRON ACK/DONE wire (Jeeves ignores anything else): each outbox chat line must START with the keyword - no nick: prefix, no prose before ACK/DONE.'
        'ACK format (exact): ACK FR|MRB|UAT owner/repo#n   Example: ACK FR SimonBarnett/gh-Jeeves#74'
        'DONE format (exact, one line, ends at URL): DONE FR|MRB|UAT owner/repo#n PASS|FAIL PR-url'
        'Nothing after the URL on a DONE line. Fix notes go on a SEPARATE outbox line. Then STOP - never post !bored (monitor-only).'
        'Outbox: APPEND only (Add-Content / AppendAllText). Never Set-Content / Out-File without -Append. Prefer: PRIVMSG #{machine} :<payload>'
        'Wrong: nick-prefixed ACK or text after DONE URL. Right: keyword first, assigned MODE, owner/repo#n, optional PASS|FAIL and URL.'
        'Do not stamp UAT. Bob/Simon only. No invented secrets. Do not gut cards or docs.'
    ) -join ' '
}

function ConvertTo-WatchProcessArgumentString {
    # Windows PowerShell 5.1 Start-Process joins -ArgumentList with spaces and does NOT
    # quote elements, so '--rules', 'Skills live at ...' and the multi-line prompt reached
    # grok agent.exe as dozens of words -> "error: unexpected argument 'at' found" and the
    # TUI exited before it was visible. Quote per CommandLineToArgvW rules instead.
    param([string[]]$ArgumentList)
    $parts = @()
    foreach ($a in @($ArgumentList)) {
        $s = [string]$a
        if ($s -eq '') { $parts += '""'; continue }
        if ($s -notmatch '[\s"]') { $parts += $s; continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('"')
        $bs = 0
        foreach ($ch in $s.ToCharArray()) {
            if ($ch -eq [char]'\') { $bs++; continue }
            if ($ch -eq [char]'"') {
                [void]$sb.Append(('\' * ($bs * 2 + 1)))
                [void]$sb.Append('"')
                $bs = 0
                continue
            }
            if ($bs -gt 0) { [void]$sb.Append(('\' * $bs)); $bs = 0 }
            [void]$sb.Append($ch)
        }
        if ($bs -gt 0) { [void]$sb.Append(('\' * ($bs * 2))) }
        [void]$sb.Append('"')
        $parts += $sb.ToString()
    }
    return ($parts -join ' ')
}

function Get-GrokRules {
    $skills = Join-Path $env:USERPROFILE '.grok\skills'
    if (Test-WatchNoBored) {
        return "Skills live at $skills. Loop seat: never !bored, never ACK/DONE to Jeeves, never fleet job loop. Monitor forwards FROM only. Harvest AgentMonitor playbooks to this repo when relevant."
    }
    return "Skills live at $skills. Follow agent-monitor, watch-seat, agentic-irc and agentic_build (including harvest-agent-skills / bob-git-accept). CAST IRON harvest AgentMonitor playbooks to this repo; fleet to agentic_build; IRC to agentic_irc. Monitor owns !bored; Jeeves assign → ACK FR|MRB|UAT owner/repo#N (line starts with ACK, no nick prefix) → work → DONE FR|MRB|UAT owner/repo#N [PASS|FAIL] <url> (nothing after URL) → STOP; append outbox only; never post !bored yourself."
}

function Get-DescendantPids {
    param([int]$RootPid)
    $bag = New-Object 'System.Collections.Generic.HashSet[int]'
    if ($RootPid -le 0) { return @() }
    [void]$bag.Add($RootPid)
    $all = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId)
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($row in $all) {
            $procId = [int]$row.ProcessId
            $parentId = [int]$row.ParentProcessId
            if ($bag.Contains($parentId) -and -not $bag.Contains($procId)) {
                [void]$bag.Add($procId)
                $changed = $true
            }
        }
    }
    return @($bag)
}

function Test-TreeHealthy {
    param([int]$RootPid)
    if ($RootPid -le 0) { return $false }
    $ids = Get-DescendantPids -RootPid $RootPid
    $alive = @()
    foreach ($id in $ids) {
        $gp = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($gp) { $alive += $gp }
    }
    if ($alive.Count -eq 0) { return $false }
    $stuck = @($alive | Where-Object { $_.Responding -eq $false })
    if ($stuck.Count -gt 0 -and $stuck.Count -eq $alive.Count) { return $false }
    return $true
}

function Stop-WatchedTree {
    param([int]$RootPid)
    if ($RootPid -le 0) { return }
    $ids = Get-DescendantPids -RootPid $RootPid
    foreach ($id in ($ids | Sort-Object -Descending)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

function Test-DropIrcLine {
    param([string]$Line)
    if ($Line -notmatch '^FROM ') { return $true }
    # Protocol tokens are UPPERCASE; -cmatch so chat words (digest, point, seal) still forward.
    if ($Line -cmatch ' POINT | DIGEST | AGPK | SEAL ') { return $true }
    # Do NOT drop chat PING here â€” Send-IrcLineToSession auto-pongs first (CAST IRON).
    if ($Line -match '(?i)is busy\.|password=|XAI_API_KEY') { return $true }
    return $false
}

function Get-IrcFromParts {
    param([string]$Line)
    $trim = $Line.Trim()
    if ($trim -notmatch '^FROM\s+(?<nick>\S+)\s+(?<target>\S+)\s+(?<text>.*)$') { return $null }
    return [pscustomobject]@{
        nick   = [string]$Matches['nick']
        target = [string]$Matches['target']
        text   = ([string]$Matches['text']).Trim()
    }
}

function Get-WatchSeatNick {
    param($State)
    if ($State -and $State.ircNick) { return ([string]$State.ircNick).Trim() }
    $seatHome = $null
    if ($State -and $State.ircHome) { $seatHome = [string]$State.ircHome }
    if (-not $seatHome) { $seatHome = Get-WatchBoundIrcHome }
    if (-not $seatHome) { $seatHome = [string]$IrcHome }
    if (-not $seatHome) { return '' }
    $coord = Join-Path $seatHome 'coordinator.pid'
    if (Test-Path -LiteralPath $coord) {
        foreach ($line in @(Get-Content -LiteralPath $coord -ErrorAction SilentlyContinue)) {
            if ($line -match '^nick=(.+)$') { return $Matches[1].Trim() }
        }
    }
    return ''
}

function Test-WatchIrcPingText {
    param(
        [string]$Text,
        [string]$OurNick = ''
    )
    # CAST IRON: any ping aimed at this seat (bare or addressed) â€” watcher pongs, never wakes agent.
    $t = ([string]$Text).Trim()
    if (-not $t) { return $false }
    if ($t -match '^(?i)ping$') { return $true }
    if ($OurNick) {
        $esc = [regex]::Escape($OurNick)
        if ($t -match ("^(?i)@?{0}\s*[:,-]?\s*ping\s*$" -f $esc)) { return $true }
        if ($t -match ("^(?i)ping\s+@?{0}\s*$" -f $esc)) { return $true }
    }
    # "nick: PING" with extra trailing junk stripped already; also CTCP-less "PING nick"
    if ($t -match '^(?i)ping\b' -and $OurNick -and $t.ToLowerInvariant().Contains($OurNick.ToLowerInvariant())) {
        return $true
    }
    return $false
}

function Send-WatchIrcPong {
    param(
        [string]$IrcHome,
        [string]$Target,
        [string]$Nick
    )
    if (-not $IrcHome -or -not $Target) { return $false }
    New-Item -ItemType Directory -Force -Path $IrcHome | Out-Null
    $outbox = Join-Path $IrcHome 'outbox.txt'
    $who = if ($Nick) { '{0}: pong' -f $Nick } else { 'pong' }
    $line = 'PRIVMSG {0} :{1}' -f $Target, $who
    [IO.File]::AppendAllText($outbox, $line + "`n", (New-Object System.Text.UTF8Encoding $false))
    Write-WatchLog ('auto-pong {0} -> {1} (watcher; no agent wake)' -f $Nick, $Target)
    return $true
}

function Set-WatchBoredActivity {
    # FR #100: reset idle clock on forward / seat activity so !bored does not fire mid-wake.
    param($State, [datetime]$Now = $(Get-Date))
    if (-not $State) { return $State }
    $State | Add-Member -NotePropertyName 'boredIdleSinceUtc' -NotePropertyValue $Now -Force
    return $State
}

function Get-WatchOutboxPayload {
    # Strip PRIVMSG prefix; return chat payload (ACK / DONE / !bored / …).
    param([string]$Line)
    $t = ([string]$Line).Trim()
    if ($t -match '^PRIVMSG\s+\S+\s+:(.*)$') { return $Matches[1].Trim() }
    return $t
}

function Get-WatchOutboxRows {
    param([string]$OutboxPath)
    if (-not $OutboxPath -or -not (Test-Path -LiteralPath $OutboxPath)) { return @() }
    return @(Get-Content -LiteralPath $OutboxPath -Encoding UTF8 -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '\S' })
}

function Test-WatchSeatOpenAck {
    # Busy when last ACK is after last DONE and outbox is younger than stale window.
    param(
        [string]$OutboxPath,
        [int]$AckStaleMinutes = 45,
        [datetime]$Now = $(Get-Date)
    )
    $rows = @(Get-WatchOutboxRows -OutboxPath $OutboxPath)
    $ackIx = -1
    $doneIx = -1
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $payload = Get-WatchOutboxPayload -Line $rows[$i]
        if ($payload -match '^(?i)ACK\b') { $ackIx = $i }
        elseif ($payload -match '^(?i)DONE\b') { $doneIx = $i }
    }
    if ($ackIx -le $doneIx) { return $false }
    if (-not (Test-Path -LiteralPath $OutboxPath)) { return $false }
    $ageMin = ($Now - (Get-Item -LiteralPath $OutboxPath).LastWriteTime).TotalMinutes
    return ($ageMin -lt [double]$AckStaleMinutes)
}

function Test-WatchAgentWakeBusy {
    # Pending / hung agent -p wake for this seat session (Cursor or Grok).
    param(
        [string]$SessionId,
        [switch]$GrokKind
    )
    $sid = ([string]$SessionId).Trim()
    if ($GrokKind) {
        if (-not $sid) { return $false }
        $pat = [regex]::Escape($sid)
        $rows = @(Get-CimInstance Win32_Process -Filter "Name='agent.exe'" -ErrorAction SilentlyContinue)
        foreach ($row in $rows) {
            $cl = [string]$row.CommandLine
            if ($cl -match (' -r\s+' + $pat + '\b') -and $cl -match ' -p(\s|$)') { return $true }
        }
        return $false
    }
    return (Test-CursorAgentForwardBusy -SessionId $sid)
}

function Test-WatchSeatBoredBusy {
    param(
        $State,
        [string]$OutboxPath,
        [datetime]$Now = $(Get-Date)
    )
    $stale = 45
    if ($script:BoredAckStaleMinutes) { $stale = [int]$script:BoredAckStaleMinutes }
    if (Test-WatchSeatOpenAck -OutboxPath $OutboxPath -AckStaleMinutes $stale -Now $Now) { return $true }
    $sid = ''
    if ($State -and $State.sessionId) { $sid = [string]$State.sessionId }
    $grokKind = $false
    if ($script:KindName -eq 'grok') { $grokKind = $true }
    elseif ($Grok) { $grokKind = $true }
    if (Test-WatchAgentWakeBusy -SessionId $sid -GrokKind:$grokKind) { return $true }
    return $false
}

function Get-WatchBoredChannel {
    # CAST IRON: !bored only in own #{machine}. Never #bobiverse / #agentic_irc / nick PRIVMSG.
    # Loop seats never call Send-WatchIrcBored (Test-WatchNoBored), but keep channel helper consistent.
    param([string]$MachineId = '')
    $mid = ([string]$MachineId).Trim()
    if (-not $mid) { $mid = Get-WatchMachineId }
    return (Get-WatchSeatChannels -MachineId $mid)
}

function Send-WatchIrcBored {
    # Deterministic outbox writer (no LLM). Always PRIVMSG #{machine} :!bored.
    param(
        [string]$IrcHome,
        [string]$Channel,
        [string]$Reason = 'idle',
        [string]$OurNick = ''
    )
    if (-not $IrcHome) { return $false }
    $chan = ([string]$Channel).Trim().ToLowerInvariant()
    if (-not $chan) { return $false }
    if ($chan -notmatch '^#[a-z0-9_-]+$') { return $false }
    if ($chan -match '(?i)^#(bobiverse|agentic_irc)$') {
        Write-WatchLog ('bored refused channel={0} (own #{{machine}} only)' -f $chan)
        return $false
    }
    if ($chan -notmatch '^#') { return $false }
    # Never PRIVMSG a nick (no leading #).
    New-Item -ItemType Directory -Force -Path $IrcHome | Out-Null
    $outbox = Join-Path $IrcHome 'outbox.txt'
    $line = 'PRIVMSG {0} :!bored' -f $chan
    $pre = ''
    if (Test-Path -LiteralPath $outbox) {
        $bytes = [IO.File]::ReadAllBytes($outbox)
        if ($bytes.Length -gt 0 -and $bytes[$bytes.Length - 1] -ne 10) { $pre = "`n" }
    }
    [IO.File]::AppendAllText($outbox, $pre + $line + "`n", (New-Object System.Text.UTF8Encoding $false))
    $who = if ($OurNick) { $OurNick } else { '?' }
    Write-WatchLog ('bored -> {0} nick={1} reason={2}' -f $chan, $who, $Reason)
    return $true
}

function Get-WatchOutboxDoneKey {
    # Stable key = DONE payload only (must not include outbox length — appending !bored
    # would change the key and re-fire reason=done every poll).
    param([string]$OutboxPath)
    $rows = @(Get-WatchOutboxRows -OutboxPath $OutboxPath)
    for ($i = $rows.Count - 1; $i -ge 0; $i--) {
        $payload = Get-WatchOutboxPayload -Line $rows[$i]
        if ($payload -match '^(?i)DONE\b') {
            return $payload
        }
    }
    return ''
}

function Sync-WatchBored {
    # FR #100: monitor emits !bored on start, after DONE, and while idle — never while busy.
    # Works with zero model tokens. Own #{machine} only.
    # FR #103: -NoBored / -SeatType loop suppresses every !bored trigger.
    param(
        $State,
        [ValidateSet('poll', 'start')]
        [string]$Mode = 'poll',
        [datetime]$Now = $(Get-Date)
    )
    if (-not $State) { return $State }
    if (Test-WatchNoBored) {
        return $State
    }
    $seatHome = [string]$State.ircHome
    if (-not $seatHome) { return $State }
    $resolved = [IO.Path]::GetFullPath($seatHome)
    if (Test-ForbiddenIrcHome -ResolvedHome $resolved) { return $State }

    $ourNick = Get-WatchSeatNick -State $State
    $mid = Get-WatchMachineId
    $channel = Get-WatchBoredChannel -MachineId $mid
    $outbox = Join-Path $resolved 'outbox.txt'

    if (-not ($State.PSObject.Properties.Name -contains 'boredLastUtc')) {
        $State | Add-Member -NotePropertyName 'boredLastUtc' -NotePropertyValue $null -Force
    }
    if (-not ($State.PSObject.Properties.Name -contains 'boredLastDoneKey')) {
        $State | Add-Member -NotePropertyName 'boredLastDoneKey' -NotePropertyValue '' -Force
    }
    if (-not ($State.PSObject.Properties.Name -contains 'boredStartSent')) {
        $State | Add-Member -NotePropertyName 'boredStartSent' -NotePropertyValue $false -Force
    }
    if (-not ($State.PSObject.Properties.Name -contains 'boredIdleSinceUtc')) {
        $State | Add-Member -NotePropertyName 'boredIdleSinceUtc' -NotePropertyValue $null -Force
    }

    $busy = Test-WatchSeatBoredBusy -State $State -OutboxPath $outbox -Now $Now
    if ($busy) {
        $State.boredIdleSinceUtc = $null
        return $State
    }

    # Activity: any new outbox line resets idle clock.
    $outLen = 0
    if (Test-Path -LiteralPath $outbox) { $outLen = [int64](Get-Item -LiteralPath $outbox).Length }
    $prevLen = 0
    if ($State.PSObject.Properties.Name -contains 'boredOutboxLen') { $prevLen = [int64]$State.boredOutboxLen }
    if ($outLen -ne $prevLen) {
        $State | Add-Member -NotePropertyName 'boredOutboxLen' -NotePropertyValue $outLen -Force
        # Growing outbox while not busy still counts as seat activity (ACK/DONE/chatter).
        if ($Mode -eq 'poll' -and $outLen -gt $prevLen) {
            $State.boredIdleSinceUtc = $Now
        }
    }
    elseif (-not $State.boredIdleSinceUtc) {
        $State.boredIdleSinceUtc = $Now
    }

    $reason = $null
    $doneKey = Get-WatchOutboxDoneKey -OutboxPath $outbox
    if ($Mode -eq 'start' -and -not [bool]$State.boredStartSent) {
        $reason = 'start'
    }
    elseif ($doneKey -and $doneKey -ne [string]$State.boredLastDoneKey) {
        $reason = 'done'
    }
    else {
        $idleSec = [int]$script:BoredIdleSeconds
        if ($idleSec -le 0) { $idleSec = 120 }
        $repSec = [int]$script:BoredRepeatSeconds
        if ($repSec -le 0) { $repSec = 180 }
        $idleSince = $State.boredIdleSinceUtc
        if (-not $idleSince) { $idleSince = $Now; $State.boredIdleSinceUtc = $Now }
        $idleFor = ($Now - [datetime]$idleSince).TotalSeconds
        $sinceBored = 999999.0
        if ($State.boredLastUtc) {
            $sinceBored = ($Now - [datetime]$State.boredLastUtc).TotalSeconds
        }
        # First idle after start/DONE uses BoredIdleSeconds; repeats use BoredRepeatSeconds.
        $threshold = $idleSec
        if (($State.PSObject.Properties.Name -contains 'boredLastReason') -and [string]$State.boredLastReason -eq 'idle') {
            $threshold = $repSec
        }
        if ($idleFor -ge $idleSec -and $sinceBored -ge $threshold) {
            $reason = 'idle'
        }
    }

    if (-not $reason) { return $State }

    # Dedupe: at most one line per second for same reason+channel (second process / re-entry).
    $dedupe = '{0}|{1}|{2}' -f $channel, $reason, $Now.ToString('yyyyMMddHHmmss')
    if (($State.PSObject.Properties.Name -contains 'boredLastDedupe') -and [string]$State.boredLastDedupe -eq $dedupe) {
        return $State
    }

    $ok = Send-WatchIrcBored -IrcHome $resolved -Channel $channel -Reason $reason -OurNick $ourNick
    if ($ok) {
        $State.boredLastUtc = $Now
        $State | Add-Member -NotePropertyName 'boredLastDedupe' -NotePropertyValue $dedupe -Force
        $State | Add-Member -NotePropertyName 'boredLastReason' -NotePropertyValue $reason -Force
        $State.boredIdleSinceUtc = $Now
        if ($reason -eq 'start') { $State.boredStartSent = $true }
        if ($reason -eq 'done') { $State.boredLastDoneKey = $doneKey }
        $State | Add-Member -NotePropertyName 'boredOutboxLen' -NotePropertyValue (
            $(if (Test-Path -LiteralPath $outbox) { [int64](Get-Item -LiteralPath $outbox).Length } else { 0 })
        ) -Force
    }
    return $State
}

function Test-WatchIrcAddressedToNick {
    param([string]$Text, [string]$OurNick)
    # "marchhare-34992: ASSIGN ..." / "@marchhare-34992, ..." / "marchhare-34992 - ..."
    $t = ([string]$Text).Trim()
    $n = ([string]$OurNick).Trim()
    if (-not $t -or -not $n) { return $false }
    $esc = [regex]::Escape($n)
    return ($t -match ("^(?i)@?{0}(\s*[:,]|\s+-\s|\s*$)" -f $esc))
}

function Get-GrokSessionsRoot {
    if ($script:GrokSessionsRoot) { return [IO.Path]::GetFullPath($script:GrokSessionsRoot) }
    if ($GrokSessionsRoot) { return [IO.Path]::GetFullPath($GrokSessionsRoot) }
    if ($env:BOB_GROK_SESSIONS_ROOT) { return [IO.Path]::GetFullPath($env:BOB_GROK_SESSIONS_ROOT) }
    return Join-Path $env:USERPROFILE '.grok\sessions'
}

function Get-GrokCwdSessionBucket {
    param([string]$WorkDir)
    $full = [IO.Path]::GetFullPath($WorkDir)
    # Grok stores sessions under URL-encoded cwd (e.g. D%3A%5Cai)
    return [uri]::EscapeDataString($full)
}

function Resolve-GrokSessionDir {
    param(
        [string]$SessionId,
        [string]$WorkDir,
        [string]$SessionsRoot = ''
    )
    $sid = ([string]$SessionId).Trim()
    if (-not $sid) { return $null }
    $root = if ($SessionsRoot) { $SessionsRoot } else { Get-GrokSessionsRoot }
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $bucket = Join-Path $root (Get-GrokCwdSessionBucket -WorkDir $WorkDir)
    $direct = Join-Path $bucket $sid
    if (Test-Path -LiteralPath $direct) { return [IO.Path]::GetFullPath($direct) }
    # Fallback: search one level under sessions root
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $cand = Join-Path $dir.FullName $sid
        if (Test-Path -LiteralPath $cand) { return [IO.Path]::GetFullPath($cand) }
    }
    return $null
}

function Get-WatchSessionSizeInfo {
    param([string]$SessionDir)
    $info = [pscustomobject]@{
        SessionDir     = $SessionDir
        UpdatesBytes   = [int64]0
        FolderBytes    = [int64]0
        UpdatesPath    = ''
        Exists         = $false
    }
    if (-not $SessionDir -or -not (Test-Path -LiteralPath $SessionDir)) { return $info }
    $info.Exists = $true
    $updates = Join-Path $SessionDir 'updates.jsonl'
    $info.UpdatesPath = $updates
    if (Test-Path -LiteralPath $updates) {
        $info.UpdatesBytes = [int64](Get-Item -LiteralPath $updates).Length
    }
    $sum = [int64]0
    foreach ($f in @(Get-ChildItem -LiteralPath $SessionDir -File -Recurse -ErrorAction SilentlyContinue)) {
        $sum += [int64]$f.Length
    }
    $info.FolderBytes = $sum
    return $info
}

function Test-WatchSessionNeedsRotation {
    param(
        $SizeInfo,
        [double]$MaxUpdatesMb = 10
    )
    if (-not $SizeInfo -or -not $SizeInfo.Exists) { return $false }
    $limit = [int64]([Math]::Max(1.0, $MaxUpdatesMb) * 1MB)
    if ([int64]$SizeInfo.UpdatesBytes -ge $limit) { return $true }
    # whole folder > 3x updates limit is also oversized
    if ([int64]$SizeInfo.FolderBytes -ge (3 * $limit)) { return $true }
    return $false
}

function Archive-WatchSessionDir {
    param(
        [string]$SessionDir,
        [string]$Reason = 'oversized'
    )
    if (-not $SessionDir -or -not (Test-Path -LiteralPath $SessionDir)) {
        return [pscustomobject]@{ ok = $false; archivePath = ''; reason = 'missing' }
    }
    $parent = Split-Path -Parent $SessionDir
    $leaf = Split-Path -Leaf $SessionDir
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $archRoot = Join-Path $parent ('_archive-{0}-{1}' -f $stamp, ($Reason -replace '[^\w\-]', ''))
    New-Item -ItemType Directory -Force -Path $archRoot | Out-Null
    $dest = Join-Path $archRoot $leaf
    # Move (never delete)
    Move-Item -LiteralPath $SessionDir -Destination $dest -Force
    return [pscustomobject]@{ ok = $true; archivePath = $dest; reason = $Reason }
}

function New-WatchSessionId {
    return [guid]::NewGuid().ToString()
}

function Write-WatchSessionHealthReport {
    param(
        [string]$Kind,
        [string]$Event,
        [hashtable]$Fields
    )
    # FR #99: digest webhook only (no IRC chatter). Best-effort; never throws.
    try {
        $payload = @{
            op        = 'merge'
            machine   = $(if ($env:BOB_MACHINE_ID) { $env:BOB_MACHINE_ID.ToLowerInvariant() } else { $env:COMPUTERNAME.ToLowerInvariant() })
            lastSeen  = (Get-Date).ToUniversalTime().ToString('o')
            working_on = ('watch-seat {0}: {1}' -f $Kind, $Event)
            status    = $(if ($Event -match 'unhealthy') { 'I am degraded' } else { 'I am online' })
            online    = $true
            watch_session = $Fields
        }
        $url = $env:BOB_REPORT_URL
        if (-not $url) { $url = 'http://127.0.0.1:19781/bob/v1/report' }
        $body = ($payload | ConvertTo-Json -Depth 6 -Compress)
        $headers = @{ 'Content-Type' = 'application/json' }
        $sec = $env:BOB_CALLBACK_SECRET
        if (-not $sec) { $sec = $env:BOB_SECRET }
        if ($sec) { $headers['X-Bob-Secret'] = $sec }
        Invoke-WebRequest -Uri $url -Method POST -Body $body -Headers $headers -UseBasicParsing -TimeoutSec 3 | Out-Null
    }
    catch { }
}

function Ensure-WatchSessionBeforeResume {
    param(
        $State,
        [string]$WorkDir,
        [string]$Kind = 'grok'
    )
    $sid = [string]$State.sessionId
    if (-not $sid) {
        $State.sessionId = New-WatchSessionId
        $State.seenSession = $false
        return $State
    }
    $dir = Resolve-GrokSessionDir -SessionId $sid -WorkDir $WorkDir
    if (-not $dir) { return $State }
    $info = Get-WatchSessionSizeInfo -SessionDir $dir
    $maxMb = if ($SessionMaxUpdatesMb -gt 0) { $SessionMaxUpdatesMb } else { 10 }
    if (-not (Test-WatchSessionNeedsRotation -SizeInfo $info -MaxUpdatesMb $maxMb)) {
        return $State
    }
    $arch = Archive-WatchSessionDir -SessionDir $dir -Reason 'oversized'
    $old = $sid
    $State.sessionId = New-WatchSessionId
    $State.seenSession = $false
    if ($State.PSObject.Properties.Name -contains 'cursorSessionValid') {
        try { $State.PSObject.Properties.Remove('cursorSessionValid') } catch { }
    }
    $State | Add-Member -NotePropertyName 'lastSessionRotate' -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
    $State | Add-Member -NotePropertyName 'lastSessionRotateReason' -NotePropertyValue 'oversized' -Force
    Write-WatchLog ("session rotate oversized old={0} new={1} updatesMb={2:N1} archive={3}" -f $old, $State.sessionId, ($info.UpdatesBytes / 1MB), $arch.archivePath)
    Write-WatchSessionHealthReport -Kind $Kind -Event 'session-rotate-oversized' -Fields @{
        old_session = $old
        new_session = $State.sessionId
        updates_mb  = [Math]::Round(($info.UpdatesBytes / 1MB), 2)
        archive     = $arch.archivePath
    }
    return $State
}

function Test-WatchForwardBusy {
    # Max one pending agent -p per seat (FR #99).
    param($State)
    if ($State.PSObject.Properties.Name -contains 'pendingForwardPid') {
        $fwdPid = 0
        try { $fwdPid = [int]$State.pendingForwardPid } catch { $fwdPid = 0 }
        if ($fwdPid -gt 0 -and (Test-WatchProcessAlive -ProcessId $fwdPid)) {
            return $true
        }
    }
    $sid = [string]$State.sessionId
    if ($sid -and (Test-CursorAgentForwardBusy -SessionId $sid)) { return $true }
    return $false
}

function Get-ProcessCpuSeconds {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $null }
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        return [double]$p.TotalProcessorTime.TotalSeconds
    }
    catch { return $null }
}

function Test-WatchQuotaFailureText {
    # FR #352 (agentic_build): quota/402/429/credits → no_tokens (not hang rotate).
    param([string]$Text)
    $t = [string]$Text
    if (-not $t) { return $false }
    if ($t -match '(?i)\b402\b') { return $true }
    if ($t -match '(?i)\b429\b') { return $true }
    if ($t -match '(?i)out of credits|out of tokens|insufficient.?quota|quota.?exceeded|rate.?limit') { return $true }
    if ($t -match '(?i)no tokens remaining|usage.?limit|payment.?required') { return $true }
    return $false
}

function Get-WatchRecentAgentOutputText {
    param($State, [int]$MaxChars = 8000)
    $chunks = @()
    try {
        $home = [string]$State.ircHome
        if ($home) {
            foreach ($name in @('agent.stderr.log', 'agent.stdout.log', 'listen.stdout.log')) {
                $p = Join-Path $home $name
                if (Test-Path -LiteralPath $p) {
                    $chunks += ,(Get-Content -LiteralPath $p -Tail 80 -ErrorAction SilentlyContinue | Out-String)
                }
            }
        }
    }
    catch { }
    try {
        $sid = [string]$State.sessionId
        $cwdFull = [IO.Path]::GetFullPath($Cwd)
        $dir = Resolve-GrokSessionDir -SessionId $sid -WorkDir $cwdFull
        if ($dir) {
            Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -gt 0 -and $_.Length -lt 2MB } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 3 |
                ForEach-Object {
                    $chunks += ,(Get-Content -LiteralPath $_.FullName -Tail 40 -ErrorAction SilentlyContinue | Out-String)
                }
        }
    }
    catch { }
    $text = ($chunks -join "`n")
    if ($text.Length -gt $MaxChars) { $text = $text.Substring($text.Length - $MaxChars) }
    return $text
}

function Set-WatchNoTokensUnhealthy {
    param($State, [string]$Detail)
    $State | Add-Member -NotePropertyName 'seatUnhealthy' -NotePropertyValue $true -Force
    $State | Add-Member -NotePropertyName 'noTokens' -NotePropertyValue $true -Force
    $State | Add-Member -NotePropertyName 'lastNoTokensUtc' -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
    Write-WatchLog ("no_tokens: {0} - stop; no retry; no session rotation" -f $Detail)
    Write-WatchSessionHealthReport -Kind $(if ($Grok) { 'grok' } else { 'cursor' }) -Event 'no_tokens' -Fields @{
        session = $State.sessionId
        detail  = $Detail
    }
    try {
        if (Get-Command Publish-BobTrayFuelMode -ErrorAction SilentlyContinue) {
            Publish-BobTrayFuelMode -FuelMode 'unknown'
        }
    }
    catch { }
    return $State
}

function Update-WatchPendingForwardHang {
    param($State)
    # FR #99: if pending -p makes no CPU progress for SessionHangMinutes, kill once, rotate, redeliver once.
    # FR #352: quota/402/429 → no_tokens (no rotate/retry).
    # Prefer pendingForwardPid; fall back to wakePid (FR #91).
    $fwdPid = 0
    if ($State.PSObject.Properties.Name -contains 'pendingForwardPid') {
        try { $fwdPid = [int]$State.pendingForwardPid } catch { $fwdPid = 0 }
    }
    if ($fwdPid -le 0 -and ($State.PSObject.Properties.Name -contains 'wakePid')) {
        try { $fwdPid = [int]$State.wakePid } catch { $fwdPid = 0 }
        if ($fwdPid -gt 0) {
            $State | Add-Member -NotePropertyName 'pendingForwardPid' -NotePropertyValue $fwdPid -Force
        }
    }
    if ($fwdPid -le 0) { return $State }
    if (-not (Test-WatchProcessAlive -ProcessId $fwdPid)) {
        $State.pendingForwardPid = 0
        if ($State.PSObject.Properties.Name -contains 'wakePid') { $State.wakePid = 0 }
        return $State
    }
    # FR #352: quota failure is not a hang — mark no_tokens and stop.
    $recent = Get-WatchRecentAgentOutputText -State $State
    if (Test-WatchQuotaFailureText -Text $recent) {
        try { Stop-Process -Id $fwdPid -Force -ErrorAction SilentlyContinue } catch { }
        $State.pendingForwardPid = 0
        if ($State.PSObject.Properties.Name -contains 'wakePid') { $State.wakePid = 0 }
        return (Set-WatchNoTokensUnhealthy -State $State -Detail 'quota/402/429 in agent output')
    }
    $cpu = Get-ProcessCpuSeconds -ProcessId $fwdPid
    $now = Get-Date
    if (-not ($State.PSObject.Properties.Name -contains 'pendingForwardCpu')) {
        $State | Add-Member -NotePropertyName 'pendingForwardCpu' -NotePropertyValue $cpu -Force
        $State | Add-Member -NotePropertyName 'pendingForwardCpuAt' -NotePropertyValue $now -Force
        return $State
    }
    $prevCpu = $State.pendingForwardCpu
    $prevAt = $State.pendingForwardCpuAt
    if ($null -eq $cpu -or $null -eq $prevCpu) { return $State }
    if ([double]$cpu -gt ([double]$prevCpu + 0.05)) {
        $State.pendingForwardCpu = $cpu
        $State.pendingForwardCpuAt = $now
        return $State
    }
    $hangMin = if ($SessionHangMinutes -gt 0) { $SessionHangMinutes } else { 3 }
    $elapsed = ($now - [datetime]$prevAt).TotalMinutes
    if ($elapsed -lt $hangMin) { return $State }

    # Hung: stop once, rotate session, redeliver pending FROM once
    Write-WatchLog ("forward hung no-cpu pid={0} elapsedMin={1:N1} - stop+rotate once" -f $fwdPid, $elapsed)
    try { Stop-Process -Id $fwdPid -Force -ErrorAction SilentlyContinue } catch { }
    $State.pendingForwardPid = 0
    if ($State.PSObject.Properties.Name -contains 'wakePid') { $State.wakePid = 0 }
    $oldSid = [string]$State.sessionId
    $cwdFull = [IO.Path]::GetFullPath($Cwd)
    $dir = Resolve-GrokSessionDir -SessionId $oldSid -WorkDir $cwdFull
    if ($dir) { [void](Archive-WatchSessionDir -SessionDir $dir -Reason 'hung') }
    $State.sessionId = New-WatchSessionId
    $State.seenSession = $false
    $State | Add-Member -NotePropertyName 'lastSessionRotateReason' -NotePropertyValue 'hung' -Force
    Write-WatchSessionHealthReport -Kind $(if ($Grok) { 'grok' } else { 'cursor' }) -Event 'session-rotate-hung' -Fields @{
        old_session = $oldSid
        new_session = $State.sessionId
        hung_pid    = $fwdPid
    }
    $pendingLine = ''
    if ($State.PSObject.Properties.Name -contains 'pendingForwardLine') {
        $pendingLine = [string]$State.pendingForwardLine
    }
    $alreadyRetried = $false
    if ($State.PSObject.Properties.Name -contains 'pendingForwardRetried' -and [bool]$State.pendingForwardRetried) {
        $alreadyRetried = $true
    }
    if ($pendingLine -and -not $alreadyRetried) {
        $State | Add-Member -NotePropertyName 'pendingForwardRetried' -NotePropertyValue $true -Force
        $State | Add-Member -NotePropertyName 'lastForwardLine' -NotePropertyValue '' -Force
        Write-WatchLog 'forward hung: re-deliver pending FROM once after rotate'
        return (Send-IrcLineToSession -State $State -Line $pendingLine)
    }
    if ($alreadyRetried) {
        $State | Add-Member -NotePropertyName 'seatUnhealthy' -NotePropertyValue $true -Force
        Write-WatchLog 'forward hung: second failure - seat unhealthy; stop queueing'
        Write-WatchSessionHealthReport -Kind $(if ($Grok) { 'grok' } else { 'cursor' }) -Event 'seat-unhealthy-hung' -Fields @{
            session = $State.sessionId
        }
    }
    return $State
}

function Format-WatchWakeText {
    # Wake payload for the headless resume (agent -r <sid> -p <text>).
    # The session never learns its IRC nick from the seed prompt, so a line addressed to
    # "marchhare-34992:" was read as "for another seat" and ignored (FR skills-visionary#19
    # ASSIGN, 2026-09-25). Addressed lines now carry an explicit FOR YOU marker + our nick.
    param([string]$Line, [string]$OurNick, [int]$MaxLen = 350)
    $text = ([string]$Line).Trim()
    if ($text.Length -gt $MaxLen) { $text = $text.Substring(0, $MaxLen) }
    $parts = Get-IrcFromParts -Line $text
    if ($parts -and $OurNick -and (Test-WatchIrcAddressedToNick -Text $parts.text -OurNick $OurNick)) {
        # FR #104: remind wire on every FOR YOU wake — agents copy nick: from the ear line otherwise.
        return ('FOR YOU (your IRC nick is {0}; this line is addressed to you - act on it and reply on outbox to {1}). Outbox ACK/DONE: line must start with ACK or DONE (no {0}: prefix); append PRIVMSG only; DONE ends at the URL: {2}' -f $OurNick, $parts.target, $text)
    }
    return $text
}

function Test-WatchForwardDedupeHit {
    # FR #105: true when $Line matches last forward and age is still within TTL.
    param(
        $State,
        [string]$Line,
        [datetime]$Now = $(Get-Date),
        [int]$TtlSeconds = 0
    )
    if (-not $State) { return $false }
    if (-not ($State.PSObject.Properties.Name -contains 'lastForwardLine')) { return $false }
    if ([string]$State.lastForwardLine -ne [string]$Line) { return $false }
    $ttl = [int]$TtlSeconds
    if ($ttl -le 0) { $ttl = [int]$script:ForwardDedupeSeconds }
    if ($ttl -le 0) { $ttl = 60 }
    $lastUtc = $null
    if ($State.PSObject.Properties.Name -contains 'lastForwardUtc' -and $State.lastForwardUtc) {
        try { $lastUtc = [datetime]$State.lastForwardUtc } catch { $lastUtc = $null }
    }
    if (-not $lastUtc) {
        # Legacy state without timestamp: treat as expired so re-offers wake again.
        return $false
    }
    $age = ($Now - $lastUtc).TotalSeconds
    return ($age -ge 0 -and $age -lt [double]$ttl)
}

function Set-WatchLastForward {
    param(
        $State,
        [string]$Line,
        [datetime]$Now = $(Get-Date)
    )
    if (-not $State) { return $State }
    $State | Add-Member -NotePropertyName 'lastForwardLine' -NotePropertyValue $Line -Force
    $State | Add-Member -NotePropertyName 'lastForwardUtc' -NotePropertyValue $Now -Force
    return $State
}

function Send-IrcLineToSession {
    param(
        $State,
        [string]$Line
    )
    try {
    if (Test-WatchForwardDedupeHit -State $State -Line $Line) {
        $age = '?'
        try {
            $age = [int]((Get-Date) - [datetime]$State.lastForwardUtc).TotalSeconds
        }
        catch { }
        Write-WatchLog ('forward skipped (duplicate within {0}s, age={1}s) {2}' -f $script:ForwardDedupeSeconds, $age, ([string]$Line).Substring(0, [Math]::Min(120, ([string]$Line).Length)))
        return $State
    }
    $trim = $Line.Trim()
    if ($trim -match '^FROM ') {
        # CAST IRON (Simon 2026-09-23): watcher ALWAYS auto-pongs PING itself â€” never forward to agent
        # (busy seats still answer so fleet knows they are responding).
        $parts = Get-IrcFromParts -Line $trim
        if ($parts) {
            $ourNick = Get-WatchSeatNick -State $State
            if (Test-WatchIrcPingText -Text $parts.text -OurNick $ourNick) {
                Write-WatchLog ('irc-in (auto-pong, no agent wake) {0}' -f $trim.Substring(0, [Math]::Min(200, $trim.Length)))
                $seatHome = [string]$State.ircHome
                if (-not $seatHome) { $seatHome = $IrcHome }
                [void](Send-WatchIrcPong -IrcHome $seatHome -Target $parts.target -Nick $parts.nick)
                $State = Set-WatchLastForward -State $State -Line $Line
                return $State
            }
        }
        if (Test-DropIrcLine -Line $trim) {
            Write-WatchLog ('irc-in (filtered) {0}' -f $trim.Substring(0, [Math]::Min(200, $trim.Length)))
            return $State
        }
        Write-WatchLog ('irc-in {0}' -f $trim.Substring(0, [Math]::Min(350, $trim.Length)))
    }
    elseif ($trim) {
        Write-WatchLog ('listen {0}' -f $trim.Substring(0, [Math]::Min(120, $trim.Length)))
    }
    if (Test-DropIrcLine -Line $Line) { return $State }
    # FR #99: hang check (no-CPU) before queueing another wake.
    $State = Update-WatchPendingForwardHang -State $State
    if ($State.PSObject.Properties.Name -contains 'seatUnhealthy' -and [bool]$State.seatUnhealthy) {
        Write-WatchLog 'forward skipped (seat unhealthy after hung wake)'
        return $State
    }
    if ($State.PSObject.Properties.Name -contains 'noTokens' -and [bool]$State.noTokens) {
        Write-WatchLog 'forward skipped (no_tokens - needs Simon: API key)'
        return $State
    }
    # FR #91: clear finished/timed-out wake before deciding to start or queue.
    $State = Sync-WatchWakeLifecycle -State $State -StartNext:$false
    if (Test-WatchWakeInFlight -State $State) {
        return (Add-WatchWakeQueue -State $State -Line $Line)
    }
    $inbox = Join-Path $script:StateDir 'agent-inbox.txt'
    Add-Content -LiteralPath $inbox -Value $Line -Encoding utf8
    $cwdFull = [IO.Path]::GetFullPath($Cwd)
    $text = Format-WatchWakeText -Line $Line -OurNick (Get-WatchSeatNick -State $State)
    # FR #99: rotate oversized session before resume (archive, never delete).
    $State = Ensure-WatchSessionBeforeResume -State $State -WorkDir $cwdFull -Kind $(if ($Grok) { 'grok' } else { 'cursor' })
    $sid = [string]$State.sessionId
    if ($Grok) {
        $exe = Get-GrokAgentPath
        $args = @('--no-auto-update', '--no-alt-screen', '--cwd', $cwdFull, '-r', $sid, '-p', $text)
        $fwdProc = Start-Process -FilePath $exe -ArgumentList (ConvertTo-WatchProcessArgumentString -ArgumentList $args) -WorkingDirectory $cwdFull -WindowStyle Hidden -PassThru
        $State = Set-WatchLastForward -State $State -Line $Line
        $State = Set-WatchBoredActivity -State $State
        $preview = $text.Substring(0, [Math]::Min(120, $text.Length))
        $pidWake = 0
        if ($fwdProc) { $pidWake = [int]$fwdProc.Id }
        $State | Add-Member -NotePropertyName 'wakePid' -NotePropertyValue $pidWake -Force
        $State | Add-Member -NotePropertyName 'wakeStartedUtc' -NotePropertyValue (Get-Date) -Force
        $State | Add-Member -NotePropertyName 'wakeKind' -NotePropertyValue 'grok' -Force
        $State | Add-Member -NotePropertyName 'pendingForwardPid' -NotePropertyValue $pidWake -Force
        $State | Add-Member -NotePropertyName 'pendingForwardLine' -NotePropertyValue $Line -Force
        $State | Add-Member -NotePropertyName 'pendingForwardCpu' -NotePropertyValue (Get-ProcessCpuSeconds -ProcessId $pidWake) -Force
        $State | Add-Member -NotePropertyName 'pendingForwardCpuAt' -NotePropertyValue (Get-Date) -Force
        $State | Add-Member -NotePropertyName 'pendingForwardRetried' -NotePropertyValue $false -Force
        Write-WatchSeatTranscript ('wake start kind=grok session={0} pid={1} text={2}' -f $sid, $pidWake, $preview)
        Start-WatchForwardExitWatcher -ProcessId $pidWake -SessionId $sid -Kind 'grok' -TranscriptPath (Get-WatchSeatTranscriptPath) -LogFile $script:LogFile
        return $State
    }
    $agentCmd = Get-CursorAgentCmd
    $fwd = Join-Path $script:StateDir 'forward-cursor.prompt.txt'
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($fwd, $text, $utf8)
    $launch = Join-Path $script:StateDir 'forward-cursor.ps1'
    $escFwd = $fwd.Replace("'", "''")
    $escCwd = $cwdFull.Replace("'", "''")
    $escAgent = $agentCmd.Replace("'", "''")
    $escSid = $sid.Replace("'", "''")
    $fwdAgent = "& '$escAgent' --trust --force$(Format-CursorModelCliFragment) --workspace '$escCwd' -p -- `$prompt"
    $fwdResume = Test-CursorUseResumeCli -State $State
    if ($fwdResume) {
        $fwdAgent = "& '$escAgent' --trust --force$(Format-CursorModelCliFragment) --resume '$escSid' --workspace '$escCwd' -p -- `$prompt"
    }
    $body = @(
        '$ErrorActionPreference = ''Stop'''
        "`$prompt = [IO.File]::ReadAllText('$escFwd')"
        "Set-Location -LiteralPath '$escCwd'"
        $fwdAgent
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($launch, $body, $utf8)
    $psExe = (Get-Command powershell.exe).Source
    $fwdProc = Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launch) -WindowStyle Hidden -PassThru
    $State = Set-WatchLastForward -State $State -Line $Line
    $State = Set-WatchBoredActivity -State $State
    $preview = $text.Substring(0, [Math]::Min(120, $text.Length))
    $pidWake = 0
    if ($fwdProc) { $pidWake = [int]$fwdProc.Id }
    $State | Add-Member -NotePropertyName 'wakePid' -NotePropertyValue $pidWake -Force
    $State | Add-Member -NotePropertyName 'wakeStartedUtc' -NotePropertyValue (Get-Date) -Force
    $State | Add-Member -NotePropertyName 'wakeKind' -NotePropertyValue 'cursor' -Force
    $State | Add-Member -NotePropertyName 'pendingForwardPid' -NotePropertyValue $pidWake -Force
    $State | Add-Member -NotePropertyName 'pendingForwardLine' -NotePropertyValue $Line -Force
    $State | Add-Member -NotePropertyName 'pendingForwardCpu' -NotePropertyValue (Get-ProcessCpuSeconds -ProcessId $pidWake) -Force
    $State | Add-Member -NotePropertyName 'pendingForwardCpuAt' -NotePropertyValue (Get-Date) -Force
    $State | Add-Member -NotePropertyName 'pendingForwardRetried' -NotePropertyValue $false -Force
    Write-WatchSeatTranscript ('wake start kind=cursor session={0} pid={1} text={2}' -f $sid, $pidWake, $preview)
    Start-WatchForwardExitWatcher -ProcessId $pidWake -SessionId $sid -Kind 'cursor' -TranscriptPath (Get-WatchSeatTranscriptPath) -LogFile $script:LogFile
    return $State
    }
    catch {
        Write-WatchLog ("forward failed: $($_.Exception.Message)")
        return $State
    }
}

function Convert-IrcRawLineToFromLine {
    param([string]$Raw)
    $line = $Raw.TrimEnd("`r", "`n").TrimStart([char]0xFEFF)
    if (-not $line) { return $null }
    if ($line -match '^PING ') { return $null }
    if ($line -match '^:\S+ \d{3} ') { return $null }
    if ($line -notmatch '^:(?<nick>[^\s!]+)![^\s]+ PRIVMSG (?<target>\S+) :(?<text>.*)$') { return $null }
    $text = $Matches['text']
    if ($text -match '^(MOOT v1 POINT|BOB DIGEST v1|AGPK v1 |MOOT v1 JOIN)') { return $null }
    if ($text -match '^\x01ACTION lost ') { return $null }
    return ('FROM {0} {1} {2}' -f $Matches['nick'], $Matches['target'], $text)
}

function Initialize-IrcLogTail {
    param($State)
    $watchIrcHome = [string]$State.ircHome
    if (-not $watchIrcHome) { return $State }
    $log = Join-Path $watchIrcHome 'irc.log'
    $hasIrcOffset = $State.PSObject.Properties.Name -contains 'ircLogOffset'
    if (-not $hasIrcOffset) {
        $startAt = 0
        if (Test-Path -LiteralPath $log) {
            $startAt = [int64](Get-Item -LiteralPath $log).Length
        }
        $State | Add-Member -NotePropertyName 'ircLogOffset' -NotePropertyValue $startAt -Force
        Write-WatchLog "irc tail init offset=$startAt (PRIVMSG from irc.log only; ignores listen-tsr)"
    }
    return $State
}

function Sync-IrcForward {
    param($State)
    $watchIrcHome = [string]$State.ircHome
    if (-not $watchIrcHome) { return $State }
    $log = Join-Path $watchIrcHome 'irc.log'
    if (-not (Test-Path -LiteralPath $log)) { return $State }
    $offset = 0
    if ($State.ircLogOffset) { $offset = [int64]$State.ircLogOffset }
    $fs = [IO.File]::Open($log, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($offset -gt $fs.Length) { $offset = 0 }
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [void]$fs.Seek($offset, [IO.SeekOrigin]::Begin)
        while ($fs.Position -lt $fs.Length) {
            $lineStart = $fs.Position
            $lineBytes = New-Object System.Collections.Generic.List[byte]
            $complete = $false
            while ($fs.Position -lt $fs.Length) {
                $b = $fs.ReadByte()
                if ($b -eq 10) {
                    $complete = $true
                    break
                }
                if ($b -eq 13) {
                    if ($fs.Position -lt $fs.Length) {
                        $next = $fs.ReadByte()
                        if ($next -eq 10) {
                            $complete = $true
                            break
                        }
                        [void]$fs.Seek(-1, [IO.SeekOrigin]::Current)
                    }
                    $lineBytes.Add([byte]13)
                    continue
                }
                $lineBytes.Add([byte]$b)
            }
            if (-not $complete) {
                [void]$fs.Seek($lineStart, [IO.SeekOrigin]::Begin)
                break
            }
            $raw = $utf8.GetString($lineBytes.ToArray())
            $from = Convert-IrcRawLineToFromLine -Raw $raw
            if ($from) {
                $State = Send-IrcLineToSession -State $State -Line $from
            }
        }
        $State.ircLogOffset = [int64]$fs.Position
    }
    finally { $fs.Dispose() }
    return $State
}

function Start-CursorInteractiveTui {
    param(
        [string]$AgentCmd,
        [string]$WorkDir,
        [string]$SessionId,
        [string]$PromptPath,
        [switch]$ResumeOnly,
        [switch]$UseResume
    )
    $agentPs1 = Get-CursorAgentPs1
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $launch = Join-Path $script:StateDir 'launch-cursor-tui.ps1'
    $escCwd = $WorkDir.Replace("'", "''")
    $escAgent = $agentPs1.Replace("'", "''")
    $escSid = $SessionId.Replace("'", "''")
    $needsPrompt = $true
    if ($ResumeOnly -and $UseResume) { $needsPrompt = $false }
    if ($ResumeOnly -and -not $UseResume) { $needsPrompt = $false }
    $lines = @(
        '$ErrorActionPreference = ''Stop'''
        "Set-Location -LiteralPath '$escCwd'"
    )
    if ($needsPrompt) {
        $escPrompt = $PromptPath.Replace("'", "''")
        $lines += "`$prompt = [IO.File]::ReadAllText('$escPrompt')"
        if ($UseResume) {
            $lines += "& '$escAgent' --trust --force$(Format-CursorModelCliFragment) --resume '$escSid' --workspace '$escCwd' -- `$prompt"
        }
        else {
            $lines += "& '$escAgent' --trust --force$(Format-CursorModelCliFragment) --workspace '$escCwd' -- `$prompt"
        }
    }
    else {
        if ($UseResume) {
            $lines += "& '$escAgent' --trust --force$(Format-CursorModelCliFragment) --resume '$escSid' --workspace '$escCwd'"
        }
        else {
            $lines += "& '$escAgent' --trust --force$(Format-CursorModelCliFragment) --workspace '$escCwd'"
        }
    }
    [IO.File]::WriteAllText($launch, ($lines -join [Environment]::NewLine), $utf8)
    $psExe = (Get-Command powershell.exe).Source
    $started = Start-Process -FilePath $psExe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $launch
    ) -WorkingDirectory $WorkDir -PassThru -WindowStyle $script:AgentTuiWindowStyle
    $launcherPid = [int]$started.Id
    Start-Sleep -Seconds 8
    $livePid = Resolve-CursorWatchRootPid -SessionId $SessionId -LauncherPid $launcherPid
    if ($livePid -le 0) {
        $why = Get-CursorTuiMissNodeWhy
        Write-WatchLog ("cursor TUI agent pid=$launcherPid but Composer node missing ($why); stopping agent launcher")
        Stop-WatchedTree -RootPid $launcherPid
        return 0
    }
    Write-WatchLog ("cursor TUI started useResume=$UseResume resumeOnly=$ResumeOnly composerPid=$livePid session=$SessionId agentLauncher=$launcherPid")
    return $livePid
}

function Invoke-CursorAgentPrint {
    param(
        [string]$AgentCmd,
        [string]$WorkDir,
        [string]$SessionId,
        [string]$PromptText,
        [string]$LogTag,
        [switch]$UseResume
    )
    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    $promptFile = Join-Path $script:StateDir 'cursor-print.prompt.txt'
    $outLog = Join-Path $script:StateDir 'cursor-print.log'
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($promptFile, $PromptText, $utf8)
    $launch = Join-Path $script:StateDir 'cursor-print.ps1'
    $escPrompt = $promptFile.Replace("'", "''")
    $escCwd = $WorkDir.Replace("'", "''")
    $escAgent = $AgentCmd.Replace("'", "''")
    $escSid = $SessionId.Replace("'", "''")
    $escOut = $outLog.Replace("'", "''")
    $agentLine = "& '$escAgent' --trust --force$(Format-CursorModelCliFragment) --workspace '$escCwd' -p -- `$prompt *>> '$escOut'"
    if ($UseResume) {
        $agentLine = "& '$escAgent' --trust --force$(Format-CursorModelCliFragment) --resume '$escSid' --workspace '$escCwd' -p -- `$prompt *>> '$escOut'"
    }
    $lines = @(
        '$ErrorActionPreference = ''Stop'''
        "`$prompt = [IO.File]::ReadAllText('$escPrompt')"
        "Set-Location -LiteralPath '$escCwd'"
        $agentLine
        'exit $LASTEXITCODE'
    )
    [IO.File]::WriteAllText($launch, ($lines -join [Environment]::NewLine), $utf8)
    $psExe = (Get-Command powershell.exe).Source
    $proc = Start-Process -FilePath $psExe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $launch
    ) -WorkingDirectory $WorkDir -PassThru -WindowStyle Hidden -Wait
    $code = if ($null -ne $proc.ExitCode) { [int]$proc.ExitCode } else { -1 }
    Write-WatchLog ("cursor {0} -p exit={1} session={2} log={3}" -f $LogTag, $code, $SessionId, $outLog)
    if ($code -ne 0 -and (Test-Path -LiteralPath $outLog)) {
        $tail = Get-Content -LiteralPath $outLog -Tail 3 -ErrorAction SilentlyContinue
        foreach ($ln in $tail) { Write-WatchLog ("cursor-print: {0}" -f $ln) }
    }
    return $code
}

function Start-WatchedAgent {
    param($State)
    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    $promptFile = Join-Path $script:StateDir 'prompt.txt'
    $resolvedHome = [string]$State.ircHome
    $prompt = Get-AgentPrompt -ResolvedIrcHome $resolvedHome
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($promptFile, $prompt, $utf8)

    $cwdFull = [IO.Path]::GetFullPath($Cwd)
    if (-not (Test-Path -LiteralPath $cwdFull)) {
        throw "Cwd not found: $cwdFull (pass -Cwd or ensure D:\ai etc. exists)"
    }

    $resume = [bool]$State.seenSession
    if ($Cursor -and -not $resume) {
        $chatDone = ($State.PSObject.Properties.Name -contains 'cursorChatCreated') -and [bool]$State.cursorChatCreated
        if (-not $chatDone) {
            $head = Get-CommitHeadroomGb
            if ($head.FreeGb -ge 0 -and $head.FreeGb -lt 0.75) {
                Write-WatchLog "low commit before create-chat ($($head.FreeGb) GB free) - pruning orphan watch forwards only"
                Stop-OrphanCursorWatchForwards | Out-Null
                Start-Sleep -Seconds 2
            }
            $agentCmdForChat = Get-CursorAgentCmd
            $chat = New-CursorChatSessionId -AgentCmd $agentCmdForChat -WorkDir $cwdFull
            $State.sessionId = [string]$chat.SessionId
            $State | Add-Member -NotePropertyName 'cursorSessionValid' -NotePropertyValue ([bool]$chat.ServerChat) -Force
            $State | Add-Member -NotePropertyName 'cursorChatCreated' -NotePropertyValue $true -Force
            Write-WatchLog "cursor new session id=$($State.sessionId) serverChat=$([bool]$chat.ServerChat)"
        }
    }
    elseif (-not $State.sessionId) {
        $State.sessionId = [guid]::NewGuid().ToString()
    }

    if ($Cursor) {
        $agentCmd = Get-CursorAgentCmd
        if (Test-CursorPrintOnlyMode -State $State) {
            $State.rootPid = 0
            return [pscustomobject]@{ Kind = 'cursor'; Exe = $agentCmd; Process = $null; RootPid = 0; State = $State }
        }
        $sid = [string]$State.sessionId
        $useResumeTui = Test-CursorUseResumeForTui -State $State -ResumeShortcut:$resume
        $livePid = Resolve-CursorWatchRootPid -SessionId $sid -LauncherPid 0
        if ($livePid -le 0) {
            $tuiPromptPath = $promptFile
            if (-not $resume) {
                $seedFile = Join-Path $script:StateDir 'cursor-tui-seed.prompt.txt'
                [IO.File]::WriteAllText($seedFile, (Get-CursorSeedPrompt -ResolvedIrcHome $resolvedHome), $utf8)
                $tuiPromptPath = $seedFile
                Write-WatchLog "cursor New: spawning Composer TUI window=$($script:AgentTuiWindowStyle) (short seed); IRC forwards stay hidden agent -p"
            }
            else {
                Write-WatchLog "cursor Resume: spawning Composer TUI window=$($script:AgentTuiWindowStyle) (resume attach)"
            }
            $head = Get-CommitHeadroomGb
            $refusedLowCommit = $false
            if ($head.FreeGb -ge 0 -and $head.FreeGb -lt 0.5) {
                Write-CursorAgentProcessSnapshot -Reason 'refusing TUI spawn (need ~0.5GB+ free commit)'
                $livePid = 0
                $refusedLowCommit = $true
            }
            else {
                $livePid = Start-CursorInteractiveTui -AgentCmd $agentCmd -WorkDir $cwdFull -SessionId $sid -PromptPath $tuiPromptPath -ResumeOnly:$resume -UseResume:$useResumeTui
            }
            if ($script:CursorModel) {
                Write-WatchLog ("cursor model=$($script:CursorModel)")
            }
            if ($livePid -gt 0) {
                $State = Sync-CursorSessionFromComposer -State $State -ComposerPid $livePid
                $State.seenSession = $true
            }
            else {
                if (-not $refusedLowCommit) {
                    $why = Get-CursorTuiMissNodeWhy
                    Write-CursorAgentProcessSnapshot -Reason "cursor Composer not running ($why)"
                }
                $State = Set-CursorPrintOnlyMode -State $State -Enable
            }
        }
        else {
            Write-WatchLog "cursor TUI already live pid=$livePid session=$sid"
            $State.seenSession = $true
        }
        $State.rootPid = $livePid
        return [pscustomobject]@{ Kind = 'cursor'; Exe = $agentCmd; Process = $null; RootPid = $livePid; State = $State }
    }

    if ($Grok) {
        $exe = Get-GrokAgentPath
        $argList = @('--no-auto-update', '--no-alt-screen', '--cwd', $cwdFull)
        if ($resume) {
            $argList += @('-r', [string]$State.sessionId)
        }
        else {
            $argList += @('-s', [string]$State.sessionId, '--rules', (Get-GrokRules))
        }
        $argList += $prompt
        $started = Start-Process -FilePath $exe -ArgumentList (ConvertTo-WatchProcessArgumentString -ArgumentList $argList) -WorkingDirectory $cwdFull -PassThru -WindowStyle $script:AgentTuiWindowStyle
        $State.seenSession = $true
        $State.rootPid = [int]$started.Id
        return [pscustomobject]@{ Kind = 'grok'; Exe = $exe; Process = $started; RootPid = [int]$started.Id; State = $State }
    }

}

function Start-DetachedWatchWorkerIfNeeded {
    if ($WatchWorker) { return }
    $sp = $PSCommandPath
    if (-not $sp) { throw 'PSCommandPath missing; run via -File.' }
    $workerArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', $sp,
        '-WatchWorker',
        '-Windows', 'off'
    )
    if ($Grok) { $workerArgs += '-Grok' }
    if ($Cursor) { $workerArgs += '-Cursor' }
    if ($New) { $workerArgs += '-New' }
    if ($script:CursorModel) { $workerArgs += @('-Model', $script:CursorModel) }
    if ($PSBoundParameters.ContainsKey('Cwd')) { $workerArgs += @('-Cwd', $Cwd) }
    # Always pass bound slot home so seats 2/3/4 are distinct.
    $homeForWorker = Get-WatchBoundIrcHome
    if (-not $homeForWorker) { $homeForWorker = [string]$IrcHome }
    $workerArgs += @('-IrcHome', $homeForWorker)
    if ($PSBoundParameters.ContainsKey('PollSeconds')) { $workerArgs += @('-PollSeconds', [string]$PollSeconds) }
    if ($PSBoundParameters.ContainsKey('CrashBackoffSeconds')) { $workerArgs += @('-CrashBackoffSeconds', [string]$CrashBackoffSeconds) }
    if ($PSBoundParameters.ContainsKey('LogPath')) { $workerArgs += @('-LogPath', $LogPath) }
    elseif ($script:LogFile) { $workerArgs += @('-LogPath', $script:LogFile) }
    if ($PSBoundParameters.ContainsKey('BoredIdleSeconds')) { $workerArgs += @('-BoredIdleSeconds', [string]$BoredIdleSeconds) }
    if ($PSBoundParameters.ContainsKey('BoredRepeatSeconds')) { $workerArgs += @('-BoredRepeatSeconds', [string]$BoredRepeatSeconds) }
    if ($PSBoundParameters.ContainsKey('BoredAckStaleMinutes')) { $workerArgs += @('-BoredAckStaleMinutes', [string]$BoredAckStaleMinutes) }
    if ($PSBoundParameters.ContainsKey('BoredCheckSeconds')) { $workerArgs += @('-BoredCheckSeconds', [string]$BoredCheckSeconds) }
    if ($PSBoundParameters.ContainsKey('ForwardDedupeSeconds')) { $workerArgs += @('-ForwardDedupeSeconds', [string]$ForwardDedupeSeconds) }
    if ($PSBoundParameters.ContainsKey('WakeTimeoutSeconds')) { $workerArgs += @('-WakeTimeoutSeconds', [string]$WakeTimeoutSeconds) }
    if ($PSBoundParameters.ContainsKey('WakeQueueMax')) { $workerArgs += @('-WakeQueueMax', [string]$WakeQueueMax) }
    if ($script:SeatType -and $script:SeatType -ne 'fleet') { $workerArgs += @('-SeatType', $script:SeatType) }
    if ($NoBored -or $script:NoBored) { $workerArgs += '-NoBored' }
    if ($script:WatchChannelOverride) { $workerArgs += @('-Channel', $script:WatchChannelOverride) }
    if ($script:WatchNickOverride) { $workerArgs += @('-Nick', $script:WatchNickOverride) }
    $log = $LogPath
    if (-not $log) { $log = $script:LogFile }
    if (-not $log) {
        $log = Join-Path $env:USERPROFILE 'Desktop\Watch-AgentHealth\Watch-AgentHealth.log'
    }
    New-Item -ItemType File -Force -Path $log | Out-Null
    $proc = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList $workerArgs -WindowStyle Hidden -PassThru
    $boot = '{0:o} hidden watch monitor pid={1} (-Windows off; log={2})' -f [datetime]::UtcNow, $proc.Id, $log
    Add-Content -LiteralPath $log -Value $boot -Encoding utf8
    Write-Host $boot
    exit 0
}

function Register-WatchWorkerProcess {
    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    $self = $PID
    $kindFlag = if ($Cursor) { '-Cursor' } else { '-Grok' }
    $seatHome = Get-WatchBoundIrcHome
    if (-not $seatHome) { $seatHome = [string]$IrcHome }
    # Only retire stale workers on THIS slot home â€” never kill seats 2/3/4.
    foreach ($row in @(Get-LiveWatchWorkerRows -Kind $script:KindName -SeatHome $seatHome -ExcludePid $self)) {
        $opid = [int]$row.ProcessId
        Write-WatchLog ("closing stale watch worker pid={0} (same home {1})" -f $opid, $seatHome)
        Stop-Process -Id $opid -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 400
    if (Test-Path -LiteralPath $script:WorkerPidPath) {
        try {
            $old = [int](Get-Content -LiteralPath $script:WorkerPidPath -Raw -ErrorAction Stop)
        }
        catch { $old = 0 }
        if ($old -gt 0 -and $old -ne $self) {
            $oldProc = Get-Process -Id $old -ErrorAction SilentlyContinue
            if ($oldProc) {
                Write-WatchLog "replacing previous watch worker pid=$old (this slot)"
                Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 400
            }
        }
    }
    Set-Content -LiteralPath $script:WorkerPidPath -Value ([string]$self) -Encoding ascii -NoNewline
    Write-WatchLog ("watch worker online pid={0} kind={1} slot={2} home={3}" -f $self, $script:KindName, $script:ClientSlot, $seatHome)
}

function Unregister-WatchWorkerProcess {
    if (-not (Test-Path -LiteralPath $script:WorkerPidPath)) { return }
    try {
        $onDisk = [int](Get-Content -LiteralPath $script:WorkerPidPath -Raw)
        if ($onDisk -eq $PID) {
            Remove-Item -LiteralPath $script:WorkerPidPath -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

# FR #97: do NOT create/truncate the default seat-1 log before Bind-WatchSlot.
# Bind-WatchSlot sets per-slot LogFile and creates it only if missing.
$script:LogFile = $LogPath
if (-not $WatchWorker -and $Windows -eq 'on') {
    $WatchWorker = $true
}
# Next free .agentic-irc-watch-* / -2 / -3 … before spawning the detached worker.
Bind-WatchSlot
Start-DetachedWatchWorkerIfNeeded
$state = Read-WatchState
$boundHome = Get-WatchBoundIrcHome
if (-not $state) {
    $state = [pscustomobject]@{
        kind         = $script:KindName
        sessionId    = [guid]::NewGuid().ToString()
        seenSession  = $false
        ircHome      = $boundHome
        clientSlot   = $script:ClientSlot
        ircLogOffset = 0
        rootPid      = 0
    }
}
else {
    # Never keep a sibling seat's ircHome from a misplaced state.json
    $state.ircHome = $boundHome
    $state | Add-Member -NotePropertyName 'clientSlot' -NotePropertyValue $script:ClientSlot -Force
}
if ($New) {
    $oldWatchSid = [string]$state.sessionId
    $state = Reset-WatchSessionForNew -State $state
    $state.kind = $script:KindName
    $state.ircHome = $boundHome
    $state | Add-Member -NotePropertyName 'clientSlot' -NotePropertyValue $script:ClientSlot -Force
    Write-WatchState -Obj $state
    Write-WatchLog "session reset (--new) session=$($state.sessionId) slot=$($script:ClientSlot)"
    if ($Cursor) {
        $n = 0
        if ($oldWatchSid) {
            $n += Stop-CursorAgentNodesForSession -SessionId $oldWatchSid
        }
        $n += Stop-OrphanCursorWatchForwards
        $n += Stop-OrphanCursorAgentNodesForSlot
        if ($n -gt 0) {
            Write-WatchLog "cursor --new pruned $n watch leftover node(s) (this slot only)"
            Start-Sleep -Seconds 2
        }
    }
}

$state = Initialize-WatchIrcHome -State $state
$state | Add-Member -NotePropertyName 'clientSlot' -NotePropertyValue $script:ClientSlot -Force
[void](Clear-OrphanWatchProcessesOnStart -ResolvedHome ([string]$state.ircHome))
# After orphan prune: always (re)connect IRC for this watch home (systray CAST IRON).
$state = Ensure-WatchIrcSeat -State $state
# FR #91: reap orphaned -p wakes from a dead previous monitor (never touch TUI without -p).
$orphanKind = ($script:KindName -eq 'grok') -or [bool]$Grok
$nOrphans = Stop-OrphanWatchWakeProcesses -SessionId ([string]$state.sessionId) -GrokKind:$orphanKind
if ($nOrphans -gt 0) {
    Write-WatchLog ("wake orphans reaped count={0}" -f $nOrphans)
}
$state = Clear-WatchWakeState -State $state
# FR #90 Option B: visible transcript pane for hidden -p wakes (operator sees work).
[void](Ensure-WatchSeatTranscriptPane)
Write-WatchSeatTranscript ('seat online kind={0} session={1} transcript={2}' -f $script:KindName, $state.sessionId, (Get-WatchSeatTranscriptPath))
# FR #100: claim work immediately (deterministic !bored; no LLM).
$state = Sync-WatchBored -State $state -Mode start
if ($WatchWorker) {
    Register-WatchWorkerProcess
}
$state = Initialize-IrcLogTail -State $state
Write-WatchLog "watch start kind=$($script:KindName) slot=$($script:ClientSlot) windows=$Windows cwd=$Cwd session=$($state.sessionId) ircHome=$($state.ircHome) (tails irc.log; irc-in lines echo here)"

$current = $null
try {
    Write-WatchState -Obj $state
    if ($Reload) {
        Write-WatchLog ("watch reload FR#89 build=adopt-live-agent monitorPid={0} session={1} priorRootPid={2}" -f $PID, $state.sessionId, $state.rootPid)
    }
    else {
        Write-WatchLog ("watch build FR#89-adopt-live-agent monitorPid={0}" -f $PID)
    }

    while ($true) {
        try {
        # Keep IRC up while the seat is live (agent+listen on own #{machine} only).
        # Cursor print-only after TUI exit: do not reconnect (Disconnect already ran).
        $skipIrc = $Cursor -and (Test-CursorPrintOnlyMode -State $state)
        if (-not $skipIrc) {
            $ag = @(Get-WatchIrcAgentRows -ResolvedHome ([string]$state.ircHome))
            $li = @(Get-WatchIrcListenRows -ResolvedHome ([string]$state.ircHome))
            if ($ag.Count -eq 0 -or $li.Count -eq 0) {
                $state = Ensure-WatchIrcSeat -State $state
            }
        }
        $needStart = $false
        if (-not $current) {
            # FR #89: adopt live TUI before Start-WatchedAgent (safe monitor hotpatch).
            $adopted = Try-AdoptLiveWatchAgent -State $state
            if ($adopted) {
                $current = $adopted
                $state.rootPid = $adopted.RootPid
                Write-WatchState -Obj $state
            }
            else {
                $needStart = $true
            }
        }
        elseif ($Cursor) {
            if (Test-CursorPrintOnlyMode -State $state) {
                $current.RootPid = 0
                $state.rootPid = 0
            }
            else {
                $livePid = Resolve-CursorWatchRootPid -SessionId ([string]$state.sessionId) -LauncherPid $current.RootPid
                if ($livePid -le 0) {
                    Write-WatchLog "cursor Composer not running session=$($state.sessionId) - print-only (no TUI relaunch)"
                    Disconnect-WatchIrc -State $state -Reason 'tui closed'
                    if ($current.RootPid -gt 0) {
                        Stop-WatchedTree -RootPid $current.RootPid
                    }
                    $state = Set-CursorPrintOnlyMode -State $state -Enable
                    $current.RootPid = 0
                }
                else {
                    if ($livePid -ne $current.RootPid) {
                        $current.RootPid = $livePid
                        $state.rootPid = $livePid
                    }
                    $state = Sync-CursorSessionFromComposer -State $state -ComposerPid $livePid
                }
            }
        }
        elseif (-not (Test-TreeHealthy -RootPid $current.RootPid)) {
            Write-WatchLog "unhealthy agent tree rootPid=$($current.RootPid) - restart (resume session $($state.sessionId))"
            Disconnect-WatchIrc -State $state -Reason 'tui closed'
            Stop-WatchedTree -RootPid $current.RootPid
            $needStart = $true
            Start-Sleep -Seconds $CrashBackoffSeconds
        }

        if ($needStart) {
            $firstRun = -not [bool]$state.seenSession
            $started = Start-WatchedAgent -State $state
            $current = $started
            $state = $started.State
            $state.rootPid = $started.RootPid
            Write-WatchState -Obj $state
            if ($Cursor -and $started.RootPid -le 0) {
                $noTui = if ($Windows -eq 'on') { ' (no live Composer TUI; windows=on)' } else { '' }
                Write-WatchLog "cursor composer not live$noTui session=$($state.sessionId) firstRun=$firstRun exe=$($started.Exe)"
            }
            else {
                Write-WatchLog "started kind=$($started.Kind) exe=$($started.Exe) rootPid=$($started.RootPid) session=$($state.sessionId) firstRun=$firstRun"
                if ($Cursor -and $started.RootPid -gt 0) {
                    Write-WatchLog "cursor seat: Composer TUI window=$($script:AgentTuiWindowStyle); IRC wakes use hidden agent -p"
                }
            }
        }

        # FR #100: tick at BoredCheckSeconds (default 5) so DONE->!bored meets the ~5s gate.
        # IRC forward runs on the same tick (cheap irc.log tail).
        $boredCheck = [int]$script:BoredCheckSeconds
        if ($boredCheck -le 0) { $boredCheck = 5 }
        # FR #91: timeout/reap wake; dequeue next FROM when free.
        $state = Sync-WatchWakeLifecycle -State $state -StartNext
        $state = Sync-IrcForward -State $state
        $state = Sync-WatchWakeLifecycle -State $state -StartNext
        $state = Sync-WatchBored -State $state -Mode poll
        Write-WatchState -Obj $state
        Start-Sleep -Seconds $boredCheck
        }
        catch {
            Write-WatchLog ("watch loop error: $($_.Exception.Message)")
            Start-Sleep -Seconds $CrashBackoffSeconds
        }
    }
}
catch {
    Write-WatchLog ("watch fatal: $($_.Exception.Message)")
}
finally {
    if ($state) {
        Disconnect-WatchIrc -State $state -Reason 'watch stop'
    }
    if ($WatchWorker) {
        Unregister-WatchWorkerProcess
    }
    if ($current) {
        Write-WatchLog "watch stop - leaving process tree rootPid=$($current.RootPid) session=$($state.sessionId)"
    }
    elseif ($WatchWorker) {
        Write-WatchLog "watch stop worker pid=$PID session=$($state.sessionId)"
    }
}
