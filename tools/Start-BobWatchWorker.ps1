# Create one persistent build-worker seat (hidden Watch-AgentHealth slot).
# This is the only supported create path. Do not Start-TalkSeat for a worker.
# Canonical product: SimonBarnett/AgentMonitor. Fleet copy: tools/Watch-AgentHealth.
# FR #345: pass explicit -IrcHome for next free slot; verify identity; safe stop.
# Fake-Grok / BOB_NO_AGENT_LAUNCH: no-op (Test-Pack must not spawn a live seat).
[CmdletBinding()]
param(
    [ValidateSet('cursor', 'grok')]
    [string]$Kind = 'cursor',
    [switch]$New,
    [switch]$WhatIf,
    [int]$Slot = 0,
    [string]$IrcHome = '',
    [switch]$SkipVerify,
    [int]$VerifyTimeoutSec = 60
)

$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('New')) { $New = $true }

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path $MyInvocation.MyCommand.Path }
. (Join-Path $here 'Bob-WatchSeatSlot.ps1')

function Test-BobWatchWorkerLaunchBlocked {
    if ($env:BOB_NO_AGENT_LAUNCH -match '^(?i)(1|true|yes)$') { return $true }
    if ($env:BOB_SKIP_LIVE_GROK -match '^(?i)(1|true|yes)$') { return $true }
    if ((Get-Command Test-BobUsesFakeGrok -ErrorAction SilentlyContinue) -and (Test-BobUsesFakeGrok)) {
        return $true
    }
    return $false
}

function Get-BobWatchAgentHealthScript {
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

# FR #345: explicit slot + home (do not rely on monitor alone)
if ($Slot -gt 0 -and $IrcHome) {
    $pick = [pscustomobject]@{ Slot = $Slot; IrcHome = [IO.Path]::GetFullPath($IrcHome); Kind = $Kind }
}
elseif ($IrcHome) {
    $pick = [pscustomobject]@{ Slot = $(if ($Slot -gt 0) { $Slot } else { 1 }); IrcHome = [IO.Path]::GetFullPath($IrcHome); Kind = $Kind }
}
else {
    $pick = Resolve-BobWatchNextFreeSlot -Kind $Kind -ExcludePid $PID
}

New-Item -ItemType Directory -Force -Path $pick.IrcHome | Out-Null
$argList = Build-BobWatchSeatLaunchArgs -ScriptPath $scriptPath -Kind $Kind -Slot $pick.Slot -IrcHome $pick.IrcHome -New:$New

Write-BobTrayStartLog -Action 'start' -Fields @{
    kind   = $Kind
    slot   = $pick.Slot
    home   = $pick.IrcHome
    script = $scriptPath
    whatIf = [bool]$WhatIf
}

if ($WhatIf) {
    return [pscustomobject]@{
        ok      = $true
        whatIf  = $true
        script  = $scriptPath
        argv    = $argList
        slot    = $pick.Slot
        ircHome = $pick.IrcHome
    }
}

$p = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList $argList -WindowStyle Hidden -PassThru
$result = [pscustomobject]@{
    ok      = $true
    kind    = $Kind
    new     = [bool]$New
    script  = $scriptPath
    pid     = [int]$p.Id
    slot    = $pick.Slot
    ircHome = $pick.IrcHome
    nick    = ''
    verify  = $null
}

if (-not $SkipVerify) {
    $v = Test-BobWatchSeatIdentityOk -Kind $Kind -Slot $pick.Slot -ExpectedHome $pick.IrcHome -TimeoutSec $VerifyTimeoutSec
    $result.verify = $v
    $result.nick = [string]$v.nick
    if (-not $v.ok) {
        Write-BobTrayStartLog -Action 'verify-fail' -Fields @{
            kind   = $Kind
            slot   = $pick.Slot
            home   = $pick.IrcHome
            reason = $v.reason
            pid    = $result.pid
        }
        # Stop ONLY this seat's processes by home (never teardown foreign home)
        $stop = Stop-BobWatchSeatByHome -IrcHome $pick.IrcHome -Reason ('verify-fail: ' + $v.reason)
        $result.ok = $false
        $result.error = 'seat_identity_failed'
        $result.reason = $v.reason
        $result.stopped = $stop
        return $result
    }
    Write-BobTrayStartLog -Action 'verify-ok' -Fields @{
        kind = $Kind
        slot = $pick.Slot
        home = $pick.IrcHome
        nick = $v.nick
        pid  = $result.pid
    }
}

return $result
