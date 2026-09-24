# Create one persistent build-worker seat (hidden Watch-AgentHealth slot).
# This is the only supported create path. Do not Start-TalkSeat for a worker.
# Canonical product: SimonBarnett/AgentMonitor. Fleet copy: tools/Watch-AgentHealth.
# Fake-Grok / BOB_NO_AGENT_LAUNCH: no-op (Test-Pack must not spawn a live seat).
[CmdletBinding()]
param(
    [ValidateSet('cursor', 'grok')]
    [string]$Kind = 'cursor',
    [switch]$New,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('New')) { $New = $true }

function Test-BobWatchWorkerLaunchBlocked {
    if ($env:BOB_NO_AGENT_LAUNCH -match '^(?i)(1|true|yes)$') { return $true }
    if ($env:BOB_SKIP_LIVE_GROK -match '^(?i)(1|true|yes)$') { return $true }
    if ((Get-Command Test-BobUsesFakeGrok -ErrorAction SilentlyContinue) -and (Test-BobUsesFakeGrok)) {
        return $true
    }
    return $false
}

function Get-BobWatchAgentHealthScript {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path $MyInvocation.MyCommand.Path }
    $candidates = @(
        (Join-Path $here 'Watch-AgentHealth\Watch-AgentHealth.ps1'),
        (Join-Path $env:USERPROFILE 'Desktop\Watch-AgentHealth\Watch-AgentHealth.ps1'),
        (Join-Path $env:USERPROFILE 'AgentMonitor\Watch-AgentHealth.ps1')
    )
    foreach ($letter in @('E', 'C', 'D')) {
        $candidates += ('{0}:\ai\AgentMonitor\Watch-AgentHealth.ps1' -f $letter)
    }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) {
            return [IO.Path]::GetFullPath($p)
        }
    }
    return $null
}

if (Test-BobWatchWorkerLaunchBlocked) {
    return [pscustomobject]@{
        ok      = $true
        skipped = $true
        reason  = 'test/fake launch blocked'
    }
}

$scriptPath = Get-BobWatchAgentHealthScript
if (-not $scriptPath) {
    return [pscustomobject]@{
        ok     = $false
        error  = 'watch_agenthealth_missing'
        reason = 'Watch-AgentHealth.ps1 not found (install tools/Watch-AgentHealth or Desktop copy)'
    }
}

$kindFlag = if ($Kind -eq 'grok') { '-Grok' } else { '-Cursor' }
$args = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', $scriptPath,
    '-WatchWorker', $kindFlag, '-Windows', 'off'
)
if ($New) { $args += '-New' }

if ($WhatIf) {
    return [pscustomobject]@{
        ok     = $true
        whatIf = $true
        script = $scriptPath
        argv   = $args
    }
}

$p = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList $args -WindowStyle Hidden -PassThru
return [pscustomobject]@{
    ok     = $true
    kind   = $Kind
    new    = [bool]$New
    script = $scriptPath
    pid    = [int]$p.Id
}
