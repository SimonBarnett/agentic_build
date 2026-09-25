# FR #328: one-shot ensure / restart for bob-{machine} irc_agent.
# Default: ensure singleton. -Restart: graceful quit then start (loads hotpatched scripts).
# Does not touch other nicks. Safe for scheduled task.
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MachineId,
    [string]$RepoRoot,
    [string]$IrcRoot,
    [switch]$Restart,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
. (Join-Path $RepoRoot 'tools\Bob-IrcAgentSupervisor.ps1')
if (-not $IrcRoot) {
    if (Test-Path 'C:\ai\agentic_irc') { $IrcRoot = 'C:\ai\agentic_irc' }
    elseif (Test-Path 'D:\ai\agentic_irc') { $IrcRoot = 'D:\ai\agentic_irc' }
    else { $IrcRoot = Join-Path (Split-Path $RepoRoot -Parent) 'agentic_irc' }
}
$IrcRoot = [IO.Path]::GetFullPath($IrcRoot)
$cfg = Get-Content (Join-Path $RepoRoot 'config\bobiverse.json') -Raw | ConvertFrom-Json
$nick = [string]$cfg.nicks.$MachineId
if (-not $nick) { $nick = 'bob-' + $MachineId }
$agentHome = Join-Path $env:USERPROFILE '.agentic-irc-bobiverse'
$hostName = [string]$cfg.host
$port = 6697
if ($cfg.port) { $port = [int]$cfg.port }
$channels = [string]$cfg.channel
if (-not $channels) { $channels = '#bobiverse' }
if (Test-Path (Join-Path $RepoRoot 'src\BobBridge.psd1')) {
    try {
        Import-Module (Join-Path $RepoRoot 'src\BobBridge.psd1') -Force -ErrorAction Stop
        $channels = Get-BobIrcBuilderChannels -MachineId $MachineId
    }
    catch { }
}

$py = $null
foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe')
    )) {
    if (Test-Path $c) { $py = $c; break }
}
if (-not $py) {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { $py = $cmd.Source }
}
if (-not $py) { throw 'python.exe not found' }
$agent = Join-Path $IrcRoot 'scripts\irc_agent.py'
if (-not (Test-Path -LiteralPath $agent)) { throw "missing $agent" }

$procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })
$health = Get-BobIrcAgentHealth -Nick $nick -IrcHome $agentHome -Processes $procs -IrcRoot $IrcRoot
Write-Output (Write-BobIrcAgentHealthLine -Health $health)

if ($WhatIf) {
    Write-Output "whatif: would $(if ($Restart) { 'restart' } else { 'ensure' }) $nick"
    exit 0
}

# Password only in child env for real start
$saved = @{ pw = $env:AGENTIC_IRC_PASSWORD; dbg = $env:AGENTIC_IRC_DEBUG }
$env:AGENTIC_IRC_DEBUG = '1'
$pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
if (Test-Path -LiteralPath $pwFile) {
    $env:AGENTIC_IRC_PASSWORD = (Get-Content -LiteralPath $pwFile -Raw).Trim()
}

try {
    if ($Restart) {
        $r = Invoke-BobIrcAgentRestart -Nick $nick -IrcHome $agentHome -Python $py -AgentPath $agent `
            -IrcRoot $IrcRoot -IrcHost $hostName -IrcPort $port -Channels $channels -Hello "$MachineId-builder"
        Write-Output "restart: $r"
    }
    else {
        $r = Invoke-BobIrcAgentEnsure -Nick $nick -IrcHome $agentHome -Python $py -AgentPath $agent `
            -IrcRoot $IrcRoot -IrcHost $hostName -IrcPort $port -Channels $channels -Hello "$MachineId-builder"
        Write-Output "ensure: $r"
    }
}
finally {
    $env:AGENTIC_IRC_PASSWORD = $saved.pw
    $env:AGENTIC_IRC_DEBUG = $saved.dbg
}

$procs2 = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })
$health2 = Get-BobIrcAgentHealth -Nick $nick -IrcHome $agentHome -Processes $procs2 -IrcRoot $IrcRoot
Write-Output (Write-BobIrcAgentHealthLine -Health $health2)
