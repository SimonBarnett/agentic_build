# Dumb #bobiverse publisher/poller. Not a Grok session. No reasoning.
# Refresh local bob-peers JSON; channel talk on real change; tray pull via !bobiverse ~120s.
# keep irc_agent.py joined. Tray only reads those files.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [int]$BobiversePullSec = 120,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
if (-not (Test-Path $psd1)) { throw "missing $psd1" }

Remove-Module BobBridge -ErrorAction SilentlyContinue
Import-Module $psd1 -Force

. (Join-Path $PSScriptRoot 'Bobiverse-Ear.ps1')

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

function Test-BobiverseIrcPrivateErgoHost {
    param([string]$CommandLine)
    if (-not $CommandLine) { return $false }
    # irc.ntsa.uk is the cert/SNI name. 127.0.0.1 is the same private Ergo
    # (loopback). Do not treat loopback as stale/Libera.
    return ($CommandLine -match 'irc\.ntsa\.uk' -or $CommandLine -match '127\.0\.0\.1')
}

function Stop-StaleBobiverseIrcAgent {
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'irc_agent\.py' -and
            $_.CommandLine -match 'bobiverse' -and
            -not (Test-BobiverseIrcPrivateErgoHost $_.CommandLine)
        })
    foreach ($p in $hits) {
        try {
            Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
            Write-BobiverseLog "killed stale irc_agent pid=$($p.ProcessId) (not irc.ntsa.uk/127.0.0.1)"
        }
        catch { }
    }
}

function Test-BobiverseIrcAgentUp {
    # Key on fleet bob-* nick — worker homes under .../workers/... contain
    # "bobiverse" in the path and must not count as the keep-alive agent (#70).
    # A failed process query is UNKNOWN, not "down": treating it as down started a second
    # ear (bob-flamingo_l) on flamingo 25/09 when the box was out of resources.
    $snap = Get-BobiverseProcessSnapshot
    $ears = @(Select-BobiverseEarProcesses -Processes $snap.Processes)
    $decision = Get-BobiverseEarSpawnDecision -QueryOk $snap.Ok -EarCount $ears.Count
    if ($decision -eq 'unknown') {
        Write-BobiverseLog ('ear check: process query failed ({0}); not starting irc_agent' -f $snap.Error)
    }
    return ($decision -ne 'spawn')
}

function Stop-BobiverseEarDuplicates {
    $snap = Get-BobiverseProcessSnapshot
    if (-not $snap.Ok) { return }
    foreach ($p in @(Select-BobiverseEarDuplicates -Processes $snap.Processes)) {
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
        Write-BobiverseLog "stopped duplicate ear irc_agent pid=$($p.ProcessId) (keep oldest)"
    }
}

function Start-BobiverseIrcAgent {
    try { Compact-BobIrcOutbox } catch { }
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
    $resolvedMid = Resolve-BobiverseMachineId $mid
    if ($resolvedMid) { $mid = $resolvedMid }
    $nick = $null
    if ($cfg.nicks) { $nick = [string]$cfg.nicks.$mid }
    if (-not $nick) { $nick = 'bob-' + $mid }
    $channel = Get-BobIrcBuilderChannels -MachineId $mid
    $ircHost = [string]$cfg.host
    $ircPort = 6697
    if ($cfg.port) { $ircPort = [int]$cfg.port }
    if ($env:BOB_IRC_HOST -and $env:BOB_IRC_HOST.Trim()) {
        $ircHost = $env:BOB_IRC_HOST.Trim()
    }
    if (-not $ircHost -or $ircHost -eq 'irc.libera.chat') {
        Write-BobiverseLog 'skip irc_agent: no private host (libera disabled)'
        return
    }
    $pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
    if (-not (Test-Path $pwFile)) {
        Write-BobiverseLog 'skip irc_agent: missing ~/.grok/ergo/connect.password'
        return
    }
    $env:AGENTIC_IRC_PASSWORD = (Get-Content $pwFile -Raw).Trim()
    $env:AGENTIC_IRC_HOME = $ircHome
    $env:AGENTIC_IRC_DEBUG = '1'
    Start-Process -FilePath $py -ArgumentList @(
        '-u', $agent,
        '--host', $ircHost,
        '--port', "$ircPort",
        '--nick', $nick,
        '--channel', $channel,
        '--home', $ircHome
    ) -WorkingDirectory $ircRoot -WindowStyle Hidden | Out-Null
    Write-BobiverseLog "started irc_agent nick=$nick host=$ircHost port=$ircPort"
}

Write-BobiverseLog "poller start pid=$PID pollSec=$PollSec pullSec=$BobiversePullSec"
while ($true) {
    try {
        Stop-StaleBobiverseIrcAgent
        Stop-BobiverseEarDuplicates
        Start-BobiverseIrcAgent
        $localDoc = Write-BobIrcStatus -SkipDigestWebhook -PassThru
        Request-BobIrcBobiversePull -MinIntervalSec $BobiversePullSec | Out-Null
        Import-BobIrcTrayPull | Out-Null
        if ($localDoc) {
            Sync-BobDigestWebhookAfterBobiversePull -LocalDoc $localDoc
        }
        Import-BobIrcPeerTranscript | Out-Null
        # FR #192 / #175 A7: apply pending shop channel repo descriptions (SHOPDESC + TOPIC outbox).
        try { Sync-BobShopChannelRepoDescriptions | Out-Null } catch { Write-BobiverseLog ('shop desc: ' + $_.Exception.Message) }
        # Shop backup: idle w-* says !BORED only. Does not !ACCEPT. Does not claim Jeeves GIT.
        Import-BobWorkerGitShop | Out-Null
    }
    catch {
        Write-BobiverseLog ('tick error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
