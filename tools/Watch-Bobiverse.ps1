# Dumb #bobiverse publisher/poller. Not a Grok session. No reasoning.
# POINT local BOB v1 status; harvest peer POINT lines into bob-peers JSON;
# keep irc_agent.py joined. Tray only reads those files.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
if (-not (Test-Path $psd1)) { throw "missing $psd1" }

Remove-Module BobBridge -ErrorAction SilentlyContinue
Import-Module $psd1 -Force

$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir 'watch_bobiverse.log'
function Write-BobiverseLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

function Get-BobiversePython {
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe')
        )) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { return $cmd.Source }
    return $null
}

function Test-BobiverseIrcAgentUp {
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'irc_agent\.py' -and
            $_.CommandLine -match 'bobiverse'
        })
    return ($hits.Count -gt 0)
}

function Start-BobiverseIrcAgent {
    if (Test-BobiverseIrcAgentUp) { return }
    $py = Get-BobiversePython
    if (-not $py) {
        Write-BobiverseLog 'no python; skip irc_agent'
        return
    }
    $ircRoot = $null
    if (Test-Path 'C:\ai\agentic_irc') { $ircRoot = 'C:\ai\agentic_irc' }
    elseif (Test-Path 'D:\ai\agentic_irc') { $ircRoot = 'D:\ai\agentic_irc' }
    if (-not $ircRoot) { return }
    $agent = Join-Path $ircRoot 'scripts\irc_agent.py'
    if (-not (Test-Path $agent)) { return }
    $cfgPath = Join-Path $RepoRoot 'config\bobiverse.json'
    if (-not (Test-Path $cfgPath)) { return }
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $ircHome = Join-Path $env:USERPROFILE '.agentic-irc-bobiverse'
    if ($env:BOB_IRC_HOME -and $env:BOB_IRC_HOME.Trim()) { $ircHome = $env:BOB_IRC_HOME.Trim() }
    if (-not (Test-Path (Join-Path $ircHome 'identity.json'))) {
        Write-BobiverseLog 'no identity.json; run Install-BobIrc.ps1 once'
        return
    }
    $mid = $env:BOB_MACHINE_ID
    if (-not $mid) { $mid = $env:COMPUTERNAME.ToLowerInvariant() }
    $nick = $null
    if ($cfg.nicks) { $nick = [string]$cfg.nicks.$mid }
    if (-not $nick) { $nick = 'bob-' + $mid }
    $channel = [string]$cfg.channel
    $env:AGENTIC_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_DEBUG = '1'
    Start-Process -FilePath $py -ArgumentList @(
        '-u', $agent,
        '--nick', $nick,
        '--channel', $channel,
        '--home', $ircHome,
        '--announce-key',
        '--hello', "$mid-builder"
    ) -WorkingDirectory $ircRoot -WindowStyle Hidden | Out-Null
    Write-BobiverseLog "started irc_agent nick=$nick"
}

Write-BobiverseLog "poller start pid=$PID pollSec=$PollSec"
while ($true) {
    try {
        Start-BobiverseIrcAgent
        Write-BobIrcStatus | Out-Null
        Import-BobIrcPeerTranscript | Out-Null
    }
    catch {
        Write-BobiverseLog ('tick error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
