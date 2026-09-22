# Keep cursor-<machine-id> irc_agent + irc_listen up (Cursor coordinator on fleet seats).
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir 'watch_cursor_irc.log'

function Write-CursorIrcLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

function Get-CursorIrcPython {
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
            'C:\Python\Python312\python.exe',
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe')
        )) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { return $cmd.Source }
    return $null
}

$mid = $env:BOB_MACHINE_ID
if (-not $mid) { $mid = 'ionos' }
$ircHome = Join-Path $env:USERPROFILE '.agentic-irc-cursor'
if ($env:AGENTIC_IRC_CURSOR_HOME -and $env:AGENTIC_IRC_CURSOR_HOME.Trim()) {
    $ircHome = $env:AGENTIC_IRC_CURSOR_HOME.Trim()
}

$ircRoot = $null
foreach ($c in @('C:\ai\agentic_irc', 'D:\ai\agentic_irc', 'C:\src\agentic_irc')) {
    if (Test-Path (Join-Path $c 'scripts\irc_agent.py')) { $ircRoot = $c; break }
}
if (-not $ircRoot) {
    Write-CursorIrcLog 'no agentic_irc checkout; skip'
    exit 1
}

function Get-CursorCoordinatorNick {
    param([string]$MachineId, [string]$IrcHomeDir, [switch]$Renew)
    $pidPath = Join-Path $IrcHomeDir 'coordinator.pid'
    if ($Renew -or -not (Test-Path $pidPath)) {
        $coord = $PID
        Set-Content -Path $pidPath -Value $coord -NoNewline -Encoding utf8
    }
    else {
        try { $coord = [int](Get-Content $pidPath -Raw).Trim() } catch { $coord = $PID }
    }
    return ('{0}-{1}' -f $MachineId, $coord)
}

$nick = Get-CursorCoordinatorNick -MachineId $mid -IrcHomeDir $ircHome

$pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
if (-not (Test-Path $pwFile)) {
    Write-CursorIrcLog 'missing connect.password'
    exit 1
}

function Test-CursorIrcAgentUp {
    param([string]$ExpectedNick, [string]$IrcHomeDir)
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'irc_agent\.py' -and
            $_.CommandLine -match [regex]::Escape($ExpectedNick) -and
            $_.CommandLine -match [regex]::Escape($IrcHomeDir)
        })
    return ($hits.Count -gt 0)
}

function Test-CursorIrcListenUp {
    param([string]$IrcHomeDir)
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'irc_listen\.py' -and
            $_.CommandLine -match [regex]::Escape($IrcHomeDir)
        })
    return ($hits.Count -gt 0)
}

function Start-CursorIrcAgent {
    param([string]$Py, [string]$Nick, [string]$IrcHomeDir)
    if (Test-CursorIrcAgentUp -ExpectedNick $Nick -IrcHomeDir $IrcHomeDir) { return }
    if (-not (Test-Path (Join-Path $IrcHomeDir 'identity.json'))) {
        $env:AGENTIC_IRC_HOME = $IrcHomeDir
        & $Py (Join-Path $ircRoot 'scripts\seal.py') genkey 2>&1 | Out-Null
    }
    $env:AGENTIC_IRC_PASSWORD = (Get-Content $pwFile -Raw).Trim()
    $env:AGENTIC_IRC_HOME = $IrcHomeDir
    $env:AGENTIC_IRC_DEBUG = '1'
    $agent = Join-Path $ircRoot 'scripts\irc_agent.py'
    Start-Process -FilePath $Py -ArgumentList @(
        '-u', $agent,
        '--host', 'irc.ntsa.uk',
        '--port', '6697',
        '--nick', $Nick,
        '--channel', '#bobiverse,#ionos',
        '--home', $IrcHomeDir,
        '--announce-key',
        '--hello', $Nick
    ) -WorkingDirectory $ircRoot -WindowStyle Hidden | Out-Null
    Write-CursorIrcLog "started irc_agent nick=$Nick"
}

function Test-CursorIrcTsrUp {
    $pidFile = Join-Path $logDir "irc-tsr-$nick.pid"
    if (-not (Test-Path $pidFile)) { return $false }
    try {
        $pid = [int](Get-Content $pidFile -Raw).Trim()
        return $null -ne (Get-Process -Id $pid -ErrorAction SilentlyContinue)
    }
    catch { return $false }
}

function Start-CursorIrcListen {
    param([string]$Py, [string]$IrcHomeDir)
    if (Test-CursorIrcTsrUp) { return }
    $tsr = Join-Path $RepoRoot 'tools\Start-IrcTsr.ps1'
    if (Test-Path $tsr) {
        & $tsr -MachineId $mid -IrcHome $IrcHomeDir -IrcRoot $ircRoot 2>&1 | Out-Null
        Write-CursorIrcLog "started IRC TSR (Start-IrcTsr) home=$IrcHomeDir"
        return
    }
    if (Test-CursorIrcListenUp -IrcHomeDir $IrcHomeDir) { return }
    $listen = Join-Path $ircRoot 'scripts\irc_listen.py'
    $outLog = Join-Path $logDir "irc_listen-$($nick).log"
    $errLog = Join-Path $logDir "irc_listen-$($nick).err.log"
    Start-Process -FilePath $Py -ArgumentList @('-u', $listen, '--home', $IrcHomeDir) `
        -WorkingDirectory $ircRoot -WindowStyle Hidden `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog | Out-Null
    Write-CursorIrcLog "started irc_listen home=$IrcHomeDir (no TSR script)"
}

$py = Get-CursorIrcPython
if (-not $py) {
    Write-CursorIrcLog 'no python'
    exit 1
}

Write-CursorIrcLog "watch start pid=$PID nick=$nick pollSec=$PollSec"
while ($true) {
    try {
        New-Item -ItemType Directory -Force -Path $ircHome | Out-Null
        Start-CursorIrcAgent -Py $py -Nick $nick -IrcHomeDir $ircHome
        # TSR must follow every agent start or the coordinator cannot hear IRC.
        Start-CursorIrcListen -Py $py -IrcHomeDir $ircHome
    }
    catch {
        Write-CursorIrcLog ('tick error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
