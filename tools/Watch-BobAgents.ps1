# Stall detector for this machine. Prints ACTION_REQUIRED / FAILED only.
# Logon-task watcher + Grok Bot WIP hangs. Not a Windows service.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [int]$StallSec = 600,
    [int]$HeartbeatStaleSec = 90,
    [string]$RepoRoot,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
if (-not (Test-Path $psd1)) { throw "missing $psd1" }

if (-not $LogPath) {
    $logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $LogPath = Join-Path $logDir ("watch_bob_agents_{0}.log" -f $PID)
}

Remove-Module BobBridge -ErrorAction SilentlyContinue
Import-Module $psd1 -Force

$WipPattern = '(?i)(\bstarting with\b|\bthen commit\b|\bworking on\b|\babout to\b)'

function Write-Diag([string]$m) {
    $line = '{0:o} {1}' -f [datetime]::UtcNow, $m
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

function Get-GrokBotMarker {
    $homes = @(
        (Join-Path $env:APPDATA 'Grok Bot'),
        (Join-Path $env:USERPROFILE 'AppData\Roaming\Grok Bot')
    )
    foreach ($h in $homes) {
        $p = Join-Path $h 'sand-session-marker.json'
        if (Test-Path $p) {
            try { return @{ home = $h; marker = (Get-Content $p -Raw | ConvertFrom-Json) } }
            catch { }
        }
    }
    return $null
}

function Test-JobProcess {
    param([string]$SessionId)
    if (-not $SessionId) { return $false }
    $esc = [regex]::Escape($SessionId)
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match $esc })
    return ($hits.Count -gt 0)
}

function Test-GrokBotProcUp {
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)Grok Bot' })
    return ($hits.Count -gt 0)
}

function Get-GrokBotMarkerAgeSec {
    $got = Get-GrokBotMarker
    if (-not $got -or -not $got.marker) { return $null }
    $ms = [int64]0
    if (-not [int64]::TryParse([string]$got.marker.aliveAtMs, [ref]$ms)) { return $null }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    return [int](($now - $ms) / 1000)
}

$seen = @{
    watcher_down = $false
    grokbot_down = $false
    inbox        = @{}
    running      = @{}
    stall        = @{}
}

Write-Diag "start poll=$PollSec stall=$StallSec heartbeat=$HeartbeatStaleSec"

while ($true) {
    try {
        $health = Get-BobHealth
        $watcherUp = [bool]$health.watcher_up
        $age = $health.last_seen_age_sec
        $heartbeatStale = ($null -ne $age -and [int]$age -gt $HeartbeatStaleSec)
        $runningNow = @(Get-BobBuilds -Lane running -ErrorAction SilentlyContinue)
        $busy = $runningNow.Count -gt 0
        if ($busy) {
            Write-Diag ("watcher busy jobs={0} last_seen_age_sec={1}" -f $runningNow.Count, $age)
        }
        # lastSeen only updates at tick start; a live grok.exe job holds the loop.
        $watcherDead = (-not $watcherUp) -or ($heartbeatStale -and -not $busy)
        if ($watcherDead) {
            if (-not $seen.watcher_down) {
                $seen.watcher_down = $true
                $msg = "ACTION_REQUIRED: watcher_down watcher_up=$watcherUp last_seen=$($health.last_seen) age_sec=$age running=$($runningNow.Count)"
                Write-Diag $msg
                Write-Output $msg
            }
        }
        else {
            if ($seen.watcher_down) { Write-Diag 'watcher recovered' }
            $seen.watcher_down = $false
        }

        $procLive = Test-GrokBotProcUp
        $markerAge = Get-GrokBotMarkerAgeSec
        Write-Diag "grokbot procLive=$procLive marker_age_sec=$markerAge"

        $inbox = @(Get-BobBuilds -Lane inbox -ErrorAction SilentlyContinue)
        $nowInbox = @{}
        foreach ($j in $inbox) {
            $id = [string]$j.id
            $nowInbox[$id] = $true
            $created = $j.createdAt
            $jobAge = $null
            if ($created) {
                try {
                    $t = [datetime]::Parse($created, $null, [Globalization.DateTimeStyles]::RoundtripKind)
                    $jobAge = [int]([datetime]::UtcNow - $t.ToUniversalTime()).TotalSeconds
                }
                catch { }
            }
            if ($jobAge -ge $HeartbeatStaleSec -and -not $seen.inbox.ContainsKey($id)) {
                $seen.inbox[$id] = $true
                $msg = "ACTION_REQUIRED: inbox_stale $id age_sec=$jobAge"
                Write-Diag $msg
                Write-Output $msg
            }
        }
        foreach ($k in @($seen.inbox.Keys)) {
            if (-not $nowInbox.ContainsKey($k)) { $seen.inbox.Remove($k) }
        }

        $running = @(Get-BobBuilds -Lane running -ErrorAction SilentlyContinue)
        $nowRun = @{}
        foreach ($j in $running) {
            $id = [string]$j.id
            $nowRun[$id] = $true
            $sid = [string]$j.sessionId
            if (-not $sid) { $sid = $id }
            $claimedAge = $null
            if ($j.claimedAt) {
                try {
                    $t = [datetime]::Parse($j.claimedAt, $null, [Globalization.DateTimeStyles]::RoundtripKind)
                    $claimedAge = [int]([datetime]::UtcNow - $t.ToUniversalTime()).TotalSeconds
                }
                catch { }
            }
            $alive = Test-JobProcess -SessionId $sid
            if ((-not $alive) -and $claimedAge -ge $HeartbeatStaleSec -and -not $seen.running.ContainsKey($id)) {
                $seen.running[$id] = $true
                $msg = "ACTION_REQUIRED: running_orphan $id session=$sid age_sec=$claimedAge"
                Write-Diag $msg
                Write-Output $msg
            }
        }
        foreach ($k in @($seen.running.Keys)) {
            if (-not $nowRun.ContainsKey($k)) { $seen.running.Remove($k) }
        }

        if ($health.grokbot) {
            $agents = @(Get-BobAgents)
            $nowStall = @{}
            $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            foreach ($a in $agents) {
                $name = [string]$a.name
                $text = [string]$a.last
                $act = 0
                if ($a.lastActivityAt) { [void][int64]::TryParse([string]$a.lastActivityAt, [ref]$act) }
                $idleSec = if ($act -gt 0) { [int](($nowMs - $act) / 1000) } else { 0 }
                $wip = ($text -and ($text -match $WipPattern))
                if ($wip -and $idleSec -ge $StallSec) {
                    $nowStall[$name] = $true
                    $prevAct = $seen.stall[$name]
                    if ($prevAct -ne $act) {
                        $seen.stall[$name] = $act
                        $snip = $text
                        if ($snip.Length -gt 180) { $snip = $snip.Substring(0, 180) }
                        $msg = "ACTION_REQUIRED: agent_stall $name idle_sec=$idleSec last=$snip"
                        Write-Diag $msg
                        Write-Output $msg
                    }
                }
            }
            foreach ($k in @($seen.stall.Keys)) {
                if (-not $nowStall.ContainsKey($k)) { $seen.stall.Remove($k) }
            }
        }
    }
    catch {
        Write-Diag ("tick error: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
