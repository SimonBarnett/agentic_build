# BT0irtsr coordinator nick restart loop (off-DEV, standalone; exit 0 = pass).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\BT0irtsr-coordinator-nick.ps1
# flamingo 24-25/09: coordinator.pid held talk-seat key=value lines; the old [int] parse threw,
# Start-IrcTsr named the runner <m>-<watcherPid>, Watch-IrcTsr looked for irc-tsr-<m>-coord.pid
# and restarted the TSR every 30s (1433x on 25/09; pre-#326 each restart orphaned irc_listen: 1833).
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $RepoRoot 'tools'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('bt0irtsr-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    . (Join-Path $tools 'Irc-Tsr-Coordinator.ps1')
    $kv = "nick=flamingo-24252`nseat=24252`nlisten=14584`nagent=31360`nhome=C:\Users\simon\.agentic-irc-cursor`n"
    $oldThrew = $false
    try { [void][int]($kv.Trim()) } catch { $oldThrew = $true }
    if (-not $oldThrew) { throw 'repro: old [int] parse must fail on key=value coordinator.pid' }
    if ((Get-IrcTsrCoordinatorId -Text $kv) -ne 24252) { throw 'key=value: nick= suffix wins' }
    if ((Get-IrcTsrCoordinatorId -Text "agent=31360`nseat=24252") -ne 31360) { throw 'no nick=: agent= before seat=' }
    if ((Get-IrcTsrCoordinatorId -Text "seat=24252`r`n") -ne 24252) { throw 'seat= only (CRLF)' }
    if ((Get-IrcTsrCoordinatorId -Text ' 12904 ') -ne 12904) { throw 'bare pid' }
    foreach ($bad in @('', '0', 'garbage', "nick=`nseat=", 'agent=-5')) {
        if ((Get-IrcTsrCoordinatorId -Text $bad) -ne 0) { throw "unknown must be 0 (never caller PID): '$bad'" }
    }
    $h = Join-Path $tmp 'cursor-home'
    New-Item -ItemType Directory -Force -Path $h | Out-Null
    if ((Get-IrcTsrCoordinatorNick -MachineId 'flamingo' -IrcHome $h) -ne 'flamingo-coord') { throw 'missing file -> <m>-coord' }
    if (-not (Initialize-IrcTsrCoordinatorPid -IrcHome $h -CoordinatorId 777)) { throw 'init must write when missing' }
    if ((Get-IrcTsrCoordinatorNick -MachineId 'flamingo' -IrcHome $h) -ne 'flamingo-777') { throw 'bare file -> flamingo-777' }
    [System.IO.File]::WriteAllText((Join-Path $h 'coordinator.pid'), $kv)
    if (Initialize-IrcTsrCoordinatorPid -IrcHome $h -CoordinatorId 999) { throw 'init must not overwrite a seat key=value file' }
    if ((Get-IrcTsrCoordinatorNick -MachineId 'flamingo' -IrcHome $h) -ne 'flamingo-24252') { throw 'key=value file -> flamingo-24252' }
    $delays = @(0, 1, 2, 3, 5, 10, 50 | ForEach-Object { Get-IrcTsrRestartDelaySec -ConsecutiveRestarts $_ -BaseSec 30 -MaxSec 600 })
    if (($delays -join ',') -ne '0,30,60,120,480,600,600') { throw "backoff: got $($delays -join ',')" }
    foreach ($f in @('Start-IrcTsr.ps1', 'Watch-IrcTsr.ps1', 'Watch-CursorIrc.ps1')) {
        $src = Get-Content (Join-Path $tools $f) -Raw
        if ($src -notmatch 'Get-IrcTsrCoordinatorNick') { throw "$f must use the shared coordinator nick parser" }
        if ($src -match '\[int\]\(Get-Content \$pidPath') { throw "$f must not [int]-parse coordinator.pid" }
        if ($src -match '\$coord = \$PID') { throw "$f must not fall back to its own PID for the coordinator nick" }
    }
    $watch = Get-Content (Join-Path $tools 'Watch-IrcTsr.ps1') -Raw
    if ($watch -notmatch 'Get-IrcTsrRestartDelaySec') { throw 'Watch-IrcTsr must back off repeated restarts' }
    if ($watch -notmatch 'Update-TsrWatchPaths') { throw 'Watch-IrcTsr must re-resolve the nick each tick' }
    $cursor = Get-Content (Join-Path $tools 'Watch-CursorIrc.ps1') -Raw
    if ($cursor -notmatch 'Get-IrcTsrRestartDelaySec') { throw 'Watch-CursorIrc must back off irc_agent / TSR respawns' }
    Write-Host 'PASS BT0irtsr coordinator nick restart loop'
    exit 0
}
catch {
    Write-Host ('FAIL BT0irtsr coordinator nick restart loop: ' + $_.Exception.Message)
    exit 1
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
