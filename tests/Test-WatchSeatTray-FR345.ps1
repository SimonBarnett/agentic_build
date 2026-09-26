# FR #345 Pester-style self-test (Windows PowerShell 5.1).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WatchSeatTray-FR345.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $RepoRoot 'tools\Bob-WatchSeatSlot.ps1')

$script:Pass = 0
$script:Fail = 0
function Invoke-Case {
    param([string]$Id, [scriptblock]$Body)
    try {
        & $Body
        $script:Pass++
        Write-Host "PASS $Id"
    }
    catch {
        $script:Fail++
        Write-Host "FAIL $Id :: $($_.Exception.Message)"
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('fr345-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$env:BOB_WATCH_SEAT_PROFILE_ROOT = $root
$env:BOB_MACHINE_ID = 'flamingo'

Invoke-Case 'T345-1 two seats get separate homes' {
    $h1 = Get-BobWatchSeatHomePath -Kind grok -Slot 1
    $h2 = Get-BobWatchSeatHomePath -Kind grok -Slot 2
    if ($h1 -eq $h2) { throw 'slot1 and slot2 homes must differ' }
    if ($h2 -notmatch 'watch-grok-2') { throw "slot2 home expected -2 suffix: $h2" }
    if ($h1 -notmatch [regex]::Escape($root)) { throw 'homes must live under test profile root' }
    $log1 = Get-BobWatchSeatLogPath -Slot 1
    $log2 = Get-BobWatchSeatLogPath -Slot 2
    if ($log1 -eq $log2) { throw 'logs must differ by slot' }
}

Invoke-Case 'T345-2 launch args include explicit IrcHome' {
    $h = Get-BobWatchSeatHomePath -Kind grok -Slot 2
    $cwd = 'C:\bob-seat-work\flamingo'
    $args = Build-BobWatchSeatLaunchArgs -ScriptPath 'C:\x\Watch-AgentHealth.ps1' -Kind grok -Slot 2 -IrcHome $h -New -Cwd $cwd
    $joined = $args -join ' '
    if ($joined -notmatch '-IrcHome') { throw "missing -IrcHome: $joined" }
    if ($joined -notmatch [regex]::Escape($h)) { throw "home not in args: $joined" }
    if ($joined -notmatch '-Cwd') { throw "missing -Cwd: $joined" }
    if ($joined -notmatch [regex]::Escape($cwd)) { throw "cwd not in args: $joined" }
    if ($joined -notmatch '-Grok') { throw 'missing -Grok' }
    if ($joined -notmatch '-New') { throw 'missing -New' }
    if ($joined -notmatch '-WatchWorker') { throw 'missing -WatchWorker' }
}

Invoke-Case 'T345-3 identity ok when state matches expected home+unique nick' {
    $h1 = Get-BobWatchSeatHomePath -Kind grok -Slot 1
    $h2 = Get-BobWatchSeatHomePath -Kind grok -Slot 2
    New-Item -ItemType Directory -Force -Path $h1, $h2 | Out-Null
    $sp1 = Get-BobWatchSeatStatePath -Kind grok -Slot 1
    $sp2 = Get-BobWatchSeatStatePath -Kind grok -Slot 2
    New-Item -ItemType Directory -Force -Path (Split-Path $sp1), (Split-Path $sp2) | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($sp1, (@{ ircHome = $h1; ircNick = 'flamingo-111'; clientSlot = 1 } | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText($sp2, (@{ ircHome = $h2; ircNick = 'flamingo-222'; clientSlot = 2 } | ConvertTo-Json), $utf8)
    Set-Content -LiteralPath (Join-Path $h1 'coordinator.pid') -Value "nick=flamingo-111`n" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $h2 'coordinator.pid') -Value "nick=flamingo-222`n" -Encoding utf8
    $v1 = Test-BobWatchSeatIdentityOk -Kind grok -Slot 1 -ExpectedHome $h1 -TimeoutSec 5
    if (-not $v1.ok) { throw "seat1 should ok: $($v1.reason)" }
    $v2 = Test-BobWatchSeatIdentityOk -Kind grok -Slot 2 -ExpectedHome $h2 -TimeoutSec 5
    if (-not $v2.ok) { throw "seat2 should ok: $($v2.reason)" }
}

Invoke-Case 'T345-4 collision: seat2 state points at seat1 home fails verify' {
    $h1 = Get-BobWatchSeatHomePath -Kind grok -Slot 1
    $h2 = Get-BobWatchSeatHomePath -Kind grok -Slot 2
    New-Item -ItemType Directory -Force -Path $h1, $h2 | Out-Null
    $sp2 = Get-BobWatchSeatStatePath -Kind grok -Slot 2
    New-Item -ItemType Directory -Force -Path (Split-Path $sp2) | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($sp2, (@{ ircHome = $h1; ircNick = 'flamingo-111'; clientSlot = 2 } | ConvertTo-Json), $utf8)
    $v = Test-BobWatchSeatIdentityOk -Kind grok -Slot 2 -ExpectedHome $h2 -TimeoutSec 3
    if ($v.ok) { throw 'collision must fail verify' }
    if ($v.reason -notmatch 'collision|wrong home') { throw "expected collision reason got $($v.reason)" }
}

Invoke-Case 'T345-5 stop refuses shared ircHome across two state owners' {
    $h = Get-BobWatchSeatHomePath -Kind grok -Slot 1
    New-Item -ItemType Directory -Force -Path $h | Out-Null
    $sp1 = Get-BobWatchSeatStatePath -Kind grok -Slot 1
    $sp2 = Get-BobWatchSeatStatePath -Kind grok -Slot 2
    New-Item -ItemType Directory -Force -Path (Split-Path $sp1), (Split-Path $sp2) | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($sp1, (@{ ircHome = $h; ircNick = 'a-1' } | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText($sp2, (@{ ircHome = $h; ircNick = 'a-2' } | ConvertTo-Json), $utf8)
    $stop = Stop-BobWatchSeatByHome -IrcHome $h -Reason 'test'
    if ($stop.ok) { throw 'stop must refuse shared home' }
    if ($stop.reason -notmatch 'shared') { throw "expected shared refuse got $($stop.reason)" }
}

Invoke-Case 'T345-6 tray-start.log writes' {
    $p = Write-BobTrayStartLog -Action 'test-line' -Fields @{ slot = 2; home = 'x' }
    if (-not (Test-Path -LiteralPath $p)) { throw 'tray-start.log missing' }
    $body = Get-Content -LiteralPath $p -Raw
    if ($body -notmatch 'test-line') { throw 'log missing action' }
    if ($p -notmatch [regex]::Escape($root)) { throw 'log should be under test profile' }
}

Invoke-Case 'T345-7 WhatIf Start-BobWatchWorker includes home' {
    $r = & (Join-Path $RepoRoot 'tools\Start-BobWatchWorker.ps1') -Kind grok -New -WhatIf -Slot 3 -IrcHome (Get-BobWatchSeatHomePath -Kind grok -Slot 3)
    if (-not $r.ok) { throw "whatif failed $($r | ConvertTo-Json -Compress)" }
    if ($r.slot -ne 3) { throw "slot $($r.slot)" }
    if ($r.argv -join ' ' -notmatch '-IrcHome') { throw 'argv missing IrcHome' }
}

Invoke-Case 'T345-8 source docs tray uses explicit home' {
    $tray = Get-Content -LiteralPath (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($tray -notmatch 'Resolve-BobWatchNextFreeSlot') { throw 'tray must resolve free slot' }
    if ($tray -notmatch 'Build-BobWatchSeatLaunchArgs') { throw 'tray must build launch args with home' }
    if ($tray -notmatch 'Stop-BobTrayAgentWatchSeat') { throw 'tray must safe-stop seats' }
    if ($tray -notmatch 'Get-BobWatchLiveSeatSummaries') { throw 'tray must list seats on menu/tooltip' }
    $start = Get-Content -LiteralPath (Join-Path $RepoRoot 'tools\Start-BobWatchWorker.ps1') -Raw
    if ($start -notmatch '-IrcHome') { throw 'Start-BobWatchWorker must pass -IrcHome' }
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item Env:\BOB_WATCH_SEAT_PROFILE_ROOT -ErrorAction SilentlyContinue
Write-Host "FR345 summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
