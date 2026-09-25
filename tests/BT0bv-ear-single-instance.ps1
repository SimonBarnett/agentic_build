# BT0bv ear single instance (off-DEV, standalone; exit 0 = pass).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\BT0bv-ear-single-instance.ps1
# flamingo 25/09 10:05 BST: a failed process query read as "no ear"; Watch-Bobiverse started a
# second bob-flamingo (pid 57612) beside pid 12176, which ran as bob-flamingo_l.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $RepoRoot 'tools'
try {
    . (Join-Path $tools 'Bobiverse-Ear.ps1')
    $old = [datetime]'2026-09-24T21:25:22'
    $new = [datetime]'2026-09-25T10:05:48'
    $procs = @(
        [pscustomobject]@{ ProcessId = 57612; CreationDate = $new; CommandLine = 'python.exe -u C:\ai\agentic_irc\scripts\irc_agent.py --host irc.ntsa.uk --port 6697 --nick bob-flamingo --channel #bobiverse,#flamingo --home C:\Users\simon\.agentic-irc-bobiverse' },
        [pscustomobject]@{ ProcessId = 12176; CreationDate = $old; CommandLine = 'python.exe -u C:\ai\agentic_irc\scripts\irc_agent.py --host irc.ntsa.uk --port 6697 --nick bob-flamingo --channel #bobiverse,#flamingo --home C:\Users\simon\.agentic-irc-bobiverse' },
        [pscustomobject]@{ ProcessId = 700; CreationDate = $new; CommandLine = 'python.exe irc_agent.py --host irc.ntsa.uk --nick flamingo-6200 --home C:\Users\simon\.agentic-irc-cursor' },
        [pscustomobject]@{ ProcessId = 701; CreationDate = $new; CommandLine = 'python.exe irc_agent.py --host irc.libera.chat --nick bob-flamingo --home C:\x\bobiverse' },
        [pscustomobject]@{ ProcessId = 702; CreationDate = $new; CommandLine = 'python.exe irc_listen.py --home C:\Users\simon\.agentic-irc-bobiverse' },
        [pscustomobject]@{ ProcessId = 703; CreationDate = $new; CommandLine = $null }
    )
    $ears = @(Select-BobiverseEarProcesses -Processes $procs | ForEach-Object { $_.ProcessId } | Sort-Object)
    if (($ears -join ',') -ne '12176,57612') { throw "ears: got $($ears -join ',')" }
    $dup = @(Select-BobiverseEarDuplicates -Processes $procs | ForEach-Object { $_.ProcessId })
    if (($dup -join ',') -ne '57612') { throw "keep oldest 12176, stop newer 57612: got $($dup -join ',')" }
    if (@(Select-BobiverseEarDuplicates -Processes @($procs[1], $procs[2])).Count -ne 0) { throw 'single ear: no duplicates' }
    if (@(Select-BobiverseEarDuplicates -Processes @()).Count -ne 0) { throw 'no processes: no duplicates' }
    if ((Get-BobiverseEarSpawnDecision -QueryOk $false -EarCount 0) -ne 'unknown') { throw 'failed query must be unknown (never spawn)' }
    if ((Get-BobiverseEarSpawnDecision -QueryOk $true -EarCount 0) -ne 'spawn') { throw 'query ok + no ear -> spawn' }
    if ((Get-BobiverseEarSpawnDecision -QueryOk $true -EarCount 1) -ne 'up') { throw 'query ok + ear -> up' }
    $src = Get-Content (Join-Path $tools 'Watch-Bobiverse.ps1') -Raw
    if ($src -notmatch 'Bobiverse-Ear\.ps1') { throw 'Watch-Bobiverse must dot-source Bobiverse-Ear.ps1' }
    if ($src -notmatch 'Get-BobiverseEarSpawnDecision') { throw 'Test-BobiverseIrcAgentUp must treat a failed query as unknown' }
    if ($src -notmatch 'Stop-BobiverseEarDuplicates') { throw 'Watch-Bobiverse must stop duplicate ears each tick' }
    $a = $src.IndexOf('function Test-BobiverseIrcAgentUp'); $b = $src.IndexOf('function Start-BobiverseIrcAgent')
    if ($src.Substring($a, $b - $a) -match 'Get-CimInstance[^\r\n|]*SilentlyContinue') { throw 'ear check must not swallow a failed process query' }
    Write-Host 'PASS BT0bv ear single instance'
    exit 0
}
catch {
    Write-Host ('FAIL BT0bv ear single instance: ' + $_.Exception.Message)
    exit 1
}
