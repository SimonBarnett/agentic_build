# Keep IRC TSR alive. Poll; restart if the runner died, listen child is gone,
# or the runner is older than RestartAfterSec (stuck/deaf).
# Does NOT start Watch-CursorIrc or cursor-<id> extras.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [int]$RestartAfterSec = 600,
    [int]$SilenceSec = 60,
    [string]$MachineId,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
if (-not $MachineId) { $MachineId = $env:BOB_MACHINE_ID }
if (-not $MachineId) { $MachineId = 'ionos' }

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
$startScript = Join-Path $RepoRoot 'tools\Start-IrcTsr.ps1'
$ircRoot = $null
foreach ($c in @('C:\ai\agentic_irc', 'D:\ai\agentic_irc', 'C:\src\agentic_irc')) {
    if (Test-Path (Join-Path $c 'scripts\irc_agent.py')) { $ircRoot = $c; break }
}

function Write-TsrWatchLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

function Get-TsrRunnerPid {
    if (-not (Test-Path $tsrPidFile)) { return 0 }
    try { return [int](Get-Content $tsrPidFile -Raw).Trim() } catch { return 0 }
}

function Test-TsrHealthy {
    $rid = Get-TsrRunnerPid
    if ($rid -le 0) { return $false }
    $proc = Get-Process -Id $rid -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }
    $listen = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -and $_.CommandLine -match 'irc_listen\.py' -and $_.CommandLine -match [regex]::Escape($ircHome)
        })
    if ($listen.Count -eq 0) { return $false }
    if ($RestartAfterSec -gt 0 -and $proc.StartTime) {
        $age = [int]((Get-Date) - $proc.StartTime).TotalSeconds
        if ($age -ge $RestartAfterSec) { return $false }
    }
    if ($SilenceSec -gt 0) {
        $wake = Join-Path $logDir "irc-tsr-$nick-wake.jsonl"
        $ircLog = Join-Path $ircHome 'irc.log'
        $stamp = $null
        if (Test-Path $wake) { $stamp = (Get-Item $wake).LastWriteTime }
        if (Test-Path $ircLog) {
            $logStamp = (Get-Item $ircLog).LastWriteTime
            if (-not $stamp -or $logStamp -gt $stamp) { $stamp = $logStamp }
        }
        if (-not $stamp) { return $false }
        $quiet = [int]((Get-Date) - $stamp).TotalSeconds
        if ($quiet -ge $SilenceSec) { return $false }
    }
    return $true
}

function Test-TalkSeatAgentUp {
    if (-not $ircRoot) { return $false }
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'irc_agent\.py' -and
            $_.CommandLine -match [regex]::Escape($nick) -and
            $_.CommandLine -match [regex]::Escape($ircHome)
        })
    return ($hits.Count -gt 0)
}

function Start-TalkSeatAgent {
    if (-not $ircRoot) {
        Write-TsrWatchLog 'no agentic_irc; skip irc_agent start'
        return
    }
    $py = $null
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
            'C:\Python\Python312\python.exe'
        )) {
        if ($c -and (Test-Path -LiteralPath $c)) { $py = $c; break }
    }
    if (-not $py) { return }
    $pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
    if (-not (Test-Path $pwFile)) { return }
    New-Item -ItemType Directory -Force -Path $ircHome | Out-Null
    $ident = Join-Path $ircHome 'identity.json'
    if (-not (Test-Path $ident)) {
        $env:AGENTIC_IRC_HOME = $ircHome
        & $py (Join-Path $ircRoot 'scripts\seal.py') genkey 2>&1 | Out-Null
    }
    $env:AGENTIC_IRC_PASSWORD = (Get-Content $pwFile -Raw).Trim()
    $env:AGENTIC_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_DEBUG = '1'
    $agent = Join-Path $ircRoot 'scripts\irc_agent.py'
    Start-Process -FilePath $py -ArgumentList @(
        '-u', $agent,
        '--host', 'irc.ntsa.uk', '--port', '6697',
        '--nick', $nick,
        '--channel', '#bobiverse,#ionos',
        '--home', $ircHome,
        '--announce-key',
        '--hello', "$nick talk-seat-up"
    ) -WorkingDirectory $ircRoot -WindowStyle Hidden | Out-Null
    Write-TsrWatchLog "started irc_agent nick=$nick"
}

Write-TsrWatchLog "watch start poll=${PollSec}s silence=${SilenceSec}s restartAfter=${RestartAfterSec}s nick=$nick"
while ($true) {
    try {
        if (-not (Test-TalkSeatAgentUp)) {
            Write-TsrWatchLog 'irc_agent missing; Start-TalkSeatAgent'
            Start-TalkSeatAgent
        }
        if (-not (Test-TsrHealthy)) {
            Write-TsrWatchLog 'TSR down or stale; Start-IrcTsr'
            & $startScript -MachineId $MachineId -IrcHome $ircHome -IrcRoot $ircRoot 2>&1 | Out-Null
        }
    }
    catch {
        Write-TsrWatchLog ('tick error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
