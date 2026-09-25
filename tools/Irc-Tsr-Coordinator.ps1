# IRC TSR coordinator nick + respawn backoff (dot-sourced by Start-IrcTsr, Watch-IrcTsr, Watch-CursorIrc).
# ASCII only (Windows PowerShell 5.1 reads BOM-less files as ANSI).

# --- coordinator nick + restart backoff (flamingo 24-25/09: 1833 orphaned irc_listen.py) ---
# coordinator.pid is written in TWO formats: a bare PID (Start-IrcTsr / Watch-CursorIrc) or
# key=value lines from agentic_irc talk seats / Watch-AgentHealth (nick=<m>-<n>, seat=, listen=,
# agent=, home=). The old [int](Get-Content -Raw) parse threw on key=value, so every script fell
# back to its OWN pid: Start-IrcTsr (run inside the watcher) named the runner <m>-<watcherPid>,
# Watch-IrcTsr looked for irc-tsr-<m>-coord.pid, never found it, and called Start-IrcTsr every
# PollSec (1433 restarts on 25/09 alone). One parser, used by all three, fixes the nick drift.

function Get-IrcTsrCoordinatorId {
    # Stable coordinator id from coordinator.pid text. 0 = unknown (caller must NOT use its own $PID).
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if (-not $Text) { return 0 }
    $t = $Text.Trim()
    $n = 0
    if ([int]::TryParse($t, [ref]$n)) { if ($n -gt 0) { return $n } else { return 0 } }
    # key=value: the nick= suffix (what the owner is named on the wire), then agent= / seat=
    # (agentic_irc talk_seat_pid order).
    foreach ($key in @('nick', 'agent', 'seat')) {
        foreach ($line in ($t -split "`r?`n")) {
            if ($key -eq 'nick' -and $line -match '^\s*nick\s*=\s*\S*?-(\d+)\s*$') { return [int]$Matches[1] }
            if ($key -ne 'nick' -and $line -match ('^\s*' + $key + '\s*=\s*(\d+)\s*$')) {
                if ([int]$Matches[1] -gt 0) { return [int]$Matches[1] }
            }
        }
    }
    return 0
}

function Get-IrcTsrCoordinatorNick {
    # <machine>-<coordinator id>; <machine>-coord when coordinator.pid is missing or unreadable.
    # Start-IrcTsr, Watch-IrcTsr and Watch-CursorIrc MUST all use this so they agree on the
    # runner pid file irc-tsr-<nick>.pid.
    param(
        [Parameter(Mandatory)][string]$MachineId,
        [Parameter(Mandatory)][string]$IrcHome
    )
    $pidPath = Join-Path $IrcHome 'coordinator.pid'
    $text = $null
    if (Test-Path -LiteralPath $pidPath) {
        try { $text = [System.IO.File]::ReadAllText($pidPath) } catch { $text = $null }
    }
    $id = Get-IrcTsrCoordinatorId -Text $text
    if ($id -gt 0) { return ('{0}-{1}' -f $MachineId, $id) }
    return ('{0}-coord' -f $MachineId)
}

function Initialize-IrcTsrCoordinatorPid {
    # Write a bare coordinator id only when the file is missing. Never overwrite a seat's
    # key=value file (talk seats own it).
    param(
        [Parameter(Mandatory)][string]$IrcHome,
        [Parameter(Mandatory)][int]$CoordinatorId
    )
    $pidPath = Join-Path $IrcHome 'coordinator.pid'
    if (Test-Path -LiteralPath $pidPath) { return $false }
    New-Item -ItemType Directory -Force -Path $IrcHome | Out-Null
    Set-Content -Path $pidPath -Value $CoordinatorId -NoNewline -Encoding ascii
    return $true
}

function Get-IrcTsrRestartDelaySec {
    # Respawn backoff: 0 restarts in a row -> no wait; then Base, 2*Base, 4*Base ... capped at Max.
    param(
        [int]$ConsecutiveRestarts,
        [int]$BaseSec = 30,
        [int]$MaxSec = 600
    )
    if ($ConsecutiveRestarts -le 0) { return 0 }
    $exp = [Math]::Min($ConsecutiveRestarts - 1, 10)
    $d = [int]($BaseSec * [Math]::Pow(2, $exp))
    if ($d -gt $MaxSec) { $d = $MaxSec }
    return $d
}
