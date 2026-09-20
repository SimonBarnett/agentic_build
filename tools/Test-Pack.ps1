# Off-DEV test pack (BT0*). Uses Fake-Grok. Does not touch real ~/.grok/bob-bridge.
[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$src = Join-Path $RepoRoot 'src\BobBridge.psd1'
$fake = Join-Path $RepoRoot 'tools\Fake-Grok.ps1'
$schemaDir = Join-Path $RepoRoot 'schemas'

function New-TestRoot {
    $d = Join-Path $env:TEMP ('bob-bridge-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $d 'cwd') | Out-Null
    return $d
}

function Import-Bridge {
    param([string]$BridgeRoot)
    $env:BOB_BRIDGE_HOME = $BridgeRoot
    $env:BOB_GROK_EXE = $fake
    $env:BOB_IRC_HOME = Join-Path $BridgeRoot 'irc-home'
    $ircCfg = Join-Path $BridgeRoot 'no-bobiverse.json'
    if (-not (Test-Path $ircCfg)) {
        '{"channel":"#test","mode":"free","mootId":"testmoot","nicks":{}}' | Set-Content -Path $ircCfg -Encoding utf8
    }
    $env:BOB_IRC_CONFIG = $ircCfg
    $env:BOB_CURSOR_USAGE_FILE = Join-Path $BridgeRoot 'no-cursor-usage.json'
    $env:BOB_SKIP_LIVE_GROK = '1'
    $env:BOB_FLEET_BUNDLED = '0'
    $env:BOB_FLEET_REGISTRY = $null
    $env:BOB_FLEET_SHARE = $null
    Remove-Module BobBridge -ErrorAction SilentlyContinue
    Import-Module $src -Force
}

$script:Pass = 0
$script:Fail = 0
$script:Results = @()

function Invoke-Case {
    param([string]$Id, [scriptblock]$Body)
    $bridgeRoot = $null
    try {
        $bridgeRoot = New-TestRoot
        Import-Bridge -BridgeRoot $bridgeRoot
        & $Body $bridgeRoot
        $script:Pass++
        $script:Results += [pscustomobject]@{ id = $Id; ok = $true; detail = 'pass' }
        Write-Host "PASS $Id"
    }
    catch {
        $script:Fail++
        $msg = $_.Exception.Message
        $script:Results += [pscustomobject]@{ id = $Id; ok = $false; detail = $msg }
        Write-Host "FAIL $Id :: $msg"
    }
    finally {
        Remove-Module BobBridge -ErrorAction SilentlyContinue
        $env:BOB_BRIDGE_HOME = $null
        $env:BOB_GROK_EXE = $null
        $env:BOB_WEEKLY_LOG = $null
        $env:BOB_FLEET_REGISTRY = $null
        $env:BOB_FLEET_SHARE = $null
        $env:BOB_FLEET_BUNDLED = $null
        $env:BOB_IRC_HOME = $null
        $env:BOB_IRC_CONFIG = $null
        $env:BOB_CURSOR_USAGE_FILE = $null
        $env:BOB_CURSOR_AGENT_FIXTURE = $null
        $env:BOB_CURSOR_USD_GBP_RATE = $null
        $env:BOB_SKIP_LIVE_GROK = $null
        $env:BOB_CAPACITY_FILE = $null
        $env:BOB_GH_EXE = $null
        $env:BOB_FAKE_GH_MODE = $null
        $env:BOB_FAKE_GH_LOG = $null
        $env:BOB_FAKE_GH_QUIET = $null
        $env:BOB_MACHINE_ID = $null
    }
}

# --- BT0 skills ---
Invoke-Case 'BT0 skills' {
    foreach ($n in @('grok-build-fleet', 'unstick-grok-bot', 'bob-build-loop', 'bob-spec-intake', 'bob-build-dispatch', 'bob-hostile-mrb', 'box-usage', 'harvest-agent-skills', 'bob-fleet-monitor', 'bob-fleet-tray', 'start-bob-copilot', 'start-bob-cursor', 'cursor-mrb-dev', 'bob-job-loop', 'bob-irc', 'reinstall-agentic-build-skills', 'setup-remote-grok-bot', 'cursor-sand-billing')) {
        $p = Join-Path $RepoRoot ".grok\skills\$n\SKILL.md"
        if (-not (Test-Path $p)) { throw "missing $p" }
        $raw = Get-Content $p -Raw
        if ($raw -notmatch ('(?m)^name:\s*' + [regex]::Escape($n))) { throw "name mismatch $n" }
    }
}

# --- BT0 parse ---
Invoke-Case 'BT0 parse' {
    $files = Get-ChildItem $RepoRoot -Recurse -Include *.ps1, *.psm1, *.psd1 |
        Where-Object { $_.FullName -notmatch '\\tests\\fixtures\\' }
    foreach ($f in $files) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            throw "$($f.FullName): $($errors[0].Message)"
        }
    }
}

# --- BT0b schema ---
Invoke-Case 'BT0b schema' {
    $required = @{
        'health.schema.json'        = @('ok', 'grok_installed', 'logged_in', 'grok_version', 'worker_count', 'leader_up', 'machine', 'watcher_up', 'last_seen')
        'overlay.schema.json'       = @('workers')
        'status.schema.json'        = @('sessionId', 'kind', 'state', 'cwd', 'title', 'updatedAt')
        'completion.schema.json'    = @('id', 'session', 'status', 'summary', 'evidence', 'needs_human', 'next_suggested')
        'prompt-packet.schema.json' = @('id', 'from', 'to_session', 'goal', 'constraints', 'success', 'reply_channel')
    }
    if ($required.Count -ne 5) { throw 'expected five schemas' }
    foreach ($name in $required.Keys) {
        $path = Join-Path $schemaDir $name
        if (-not (Test-Path $path)) { throw "missing $name" }
        $s = Get-Content $path -Raw | ConvertFrom-Json
        if (-not $s.required) { throw "$name has no required keys" }
        foreach ($k in $required[$name]) {
            if (@($s.required) -notcontains $k) { throw "$name missing required $k" }
        }
    }
}

# --- BT0c no-sendkeys ---
Invoke-Case 'BT0c no-sendkeys' {
    $hits2 = @(Get-ChildItem (Join-Path $RepoRoot 'src') -Recurse -Include *.ps1, *.psm1, *.psd1 |
        Select-String -Pattern 'SendKeys|UIAutomation|WScript\.Shell')
    if ($hits2.Count -gt 0) {
        throw ($hits2 | ForEach-Object { "$($_.Path):$($_.LineNumber) $($_.Line.Trim())" }) -join '; '
    }
}

# --- BT0d oneshot ---
Invoke-Case 'BT0d oneshot' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic -Title 'pong'
    if (-not $r.ok) { throw "start not ok: $($r.completion | ConvertTo-Json -Compress)" }
    $last = Get-BobResult -SessionId $r.sessionId
    if ($last.result -ne 'PONG') { throw "last_result.result=$($last.result)" }
    $compPath = Join-Path $bridgeRoot "workers\$($r.sessionId)\outbox\completion.json"
    if (-not (Test-Path $compPath)) { throw "missing $compPath" }
    $comp = Get-Content $compPath -Raw | ConvertFrom-Json
    if ($comp.status -ne 'ok') { throw "completion.status=$($comp.status)" }
    $workers = Get-BobWorkers
    if (@($workers).Count -ne 1) { throw "overlay count=$(@($workers).Count)" }
    if (-not $r.processGone) { throw 'process not gone' }
}

# --- BT0e resume ---
Invoke-Case 'BT0e resume' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic
    $id = $r.sessionId
    Remove-Module BobBridge -Force
    $env:BOB_BRIDGE_HOME = $bridgeRoot
    $env:BOB_GROK_EXE = $fake
    Import-Module $src -Force
    $s = Send-BobPrompt -SessionId $id -Prompt 'PONG2'
    if (-not $s.ok) { throw "send not ok: $($s | ConvertTo-Json -Compress)" }
    if (-not $s.resumed) { throw 'resumed=false' }
    $last = Get-BobResult -SessionId $id
    if ($last.result -ne 'PONG2') { throw "result=$($last.result)" }
    if (-not $last.resumed) { throw 'last_result.resumed=false' }
}

# --- BT0f cwd ---
Invoke-Case 'BT0f cwd' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r1 = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic
    if (-not $r1.ok) { throw 'first start failed' }
    $r2 = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic
    if ($r2.ok) { throw 'second start should fail' }
    if ($r2.error -ne 'worker_exists') { throw "error=$($r2.error)" }
    $workers = Get-BobWorkers
    if (@($workers).Count -ne 1) { throw "overlay count=$(@($workers).Count)" }
}

# --- BT0g profile ---
Invoke-Case 'BT0g profile' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile formprep -WhatIfArgv
    $text = [IO.File]::ReadAllText($r.argvPath)
    if ($text -notmatch '--rules') { throw 'formprep argv missing --rules' }
    if ($text -match '--always-approve') { throw 'formprep argv has --always-approve' }
    if ($text -match '--yolo') { throw 'formprep argv has --yolo' }
    $g = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic -WhatIfArgv -Force
    $gtext = [IO.File]::ReadAllText($g.argvPath)
    if ($gtext -notmatch 'SimonBarnett/agentic_build') { throw 'build agent argv must pass agentic_build skills' }
}

# --- BT0h synth ---
Invoke-Case 'BT0h synth' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $fail = Start-BobWorker -Cwd $cwd -Prompt 'FAIL' -Profile generic
    if ($fail.ok) { throw 'FAIL should not be ok' }
    if ($fail.completion.status -ne 'failed') { throw "status=$($fail.completion.status)" }
    if ($fail.completion.status -eq 'ok') { throw 'failed completion marked ok' }
    Stop-BobWorker -SessionId $fail.sessionId | Out-Null

    $cwd2 = Join-Path $bridgeRoot 'cwd2'
    New-Item -ItemType Directory -Force -Path $cwd2 | Out-Null
    $empty = Start-BobWorker -Cwd $cwd2 -Prompt 'EMPTY' -Profile generic
    if ($empty.completion.status -ne 'blocked') { throw "EMPTY status=$($empty.completion.status)" }
    if ($empty.ok) { throw 'EMPTY should not be ok' }
}

# --- BT0i audit ---
Invoke-Case 'BT0i audit' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic
    $audit = Join-Path $bridgeRoot 'audit.jsonl'
    if (-not (Test-Path $audit)) { throw 'audit.jsonl missing' }
    $lines = @(Get-Content $audit | Where-Object { $_.Trim() })
    if ($lines.Count -lt 1) { throw 'audit.jsonl empty' }
    $row = $lines[-1] | ConvertFrom-Json
    if (-not $row.sha256) { throw 'sha256 missing' }
    if ($row.sha256.Length -ne 64) { throw "sha256 length $($row.sha256.Length)" }
    $raw = Get-Content $audit -Raw
    if ($raw -match 'XAI_API_KEY') { throw 'audit contains XAI_API_KEY' }
    $ref = Start-BobWorker -Cwd (Join-Path $bridgeRoot 'other') -Prompt 'password=secret' -Profile generic -Force
    if ($ref.error -ne 'refuse') { throw "password prompt not refused: $($ref.error)" }
    $mention = Start-BobWorker -Cwd $cwd -Prompt 'Do not set or request XAI_API_KEY' -Profile generic -WhatIfArgv -Force
    if ($mention.error -eq 'refuse') { throw 'instructional XAI_API_KEY mention was refused' }
    if (-not $mention.ok) { throw "mention whatif failed: $($mention | ConvertTo-Json -Compress)" }
}

# --- BT0j grokbot hermetic ---
Invoke-Case 'BT0j grokbot hermetic' {
    param($bridgeRoot)
    $agents = @(Get-BobAgents)
    if ($agents.Count -ne 0) { throw "Fake-Grok must not list live agents: $($agents.Count)" }
    $cwd = Join-Path $bridgeRoot 'cwd'
    $r = Start-BobWorker -Cwd $cwd -Prompt 'PONG' -Profile generic -Agent Bob
    if (-not $r.ok) { throw "fake -Agent Bob should still oneshot: $($r | ConvertTo-Json -Compress)" }
    if ($r.transport -eq 'grokbot') { throw 'Fake-Grok must not use grokbot transport' }
    $last = Get-BobResult -SessionId $r.sessionId
    if ($last.result -ne 'PONG') { throw "result=$($last.result)" }
}

# --- BT0k fleet fake store ---
Invoke-Case 'BT0k fleet fake store' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $reg = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    if ($reg.id -ne 'testhost') { throw "id=$($reg.id)" }
    if ($reg.mssql -ne 'integrated') { throw 'mssql not integrated' }
    $machines = @(Get-BobMachines)
    if ($machines.Count -lt 1) { throw 'no machines' }

    $bad = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'password=secret' -Profile generic
    if ($bad.error -ne 'refuse') { throw "secret goal not refused: $($bad.error)" }

    $q = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'PONG' -Profile generic -Success 'echo' -Constraints @('Do not set or request XAI_API_KEY')
    if (-not $q.ok) { throw "enqueue failed $($q | ConvertTo-Json -Compress)" }
    $inbox = Get-BobBuild -JobId $q.jobId
    if ($inbox.lane -ne 'inbox') { throw "lane=$($inbox.lane)" }

    $watch = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
    $env:BOB_MACHINE_ID = 'testhost'
    & $watch -Once -RepoRoot $RepoRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Watch-BobJobs exit $LASTEXITCODE" }

    $done = Get-BobBuild -JobId $q.jobId
    if ($done.lane -ne 'outbox') { throw "expected outbox, lane=$($done.lane)" }
    if ($done.state -ne 'done') { throw "state=$($done.state)" }
    if (-not $done.completion -or $done.completion.status -ne 'ok') { throw 'completion not ok' }

    $q2 = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'PONG' -Profile generic
    $st = Stop-BobBuild -JobId $q2.jobId
    if (-not $st.ok) { throw 'stop enqueue failed' }
    & $watch -Once -RepoRoot $RepoRoot | Out-Null
    $stopped = Get-BobBuild -JobId $q2.jobId
    if ($stopped.state -ne 'stopped') { throw "expected stopped, state=$($stopped.state)" }

    $drive = Register-BobMachine -Id testhost -CwdRoots 'C:'
    $root = [string]@($drive.cwdRoots)[0]
    if ($root -ne 'C:\') { throw "drive-root cwdRoots=$root" }

    $h = Get-BobHealth
    if ($null -eq $h.watcher_up) { throw 'health.watcher_up missing' }
    if (-not ($h.PSObject.Properties.Name -contains 'last_seen')) { throw 'health.last_seen missing' }

    $watchSrc = Get-Content $watch -Raw
    if ($watchSrc -match '(?m)^\s*\$mid\s*=\s*Get-ThisMachineId\b') { throw 'Watch-BobJobs must not call private Get-ThisMachineId' }
    if ($watchSrc -match 'catch\s*\{\s*Write-Error') { throw 'Watch-BobJobs catch must not Write-Error (kills poller under ErrorAction Stop)' }
    if ($watchSrc -notmatch '(?s)if \(\$Once\).+while \(\$true\).+Invoke-BobFleetTick') {
        throw 'idle Watch-BobJobs loop must Invoke-BobFleetTick so lastSeen stays fresh'
    }
    $tw = Get-Content (Join-Path $RepoRoot 'src\Private\Test-BobWatcher.ps1') -Raw
    if ($tw -match 'Watch-BobTray') { throw 'watcher_up must not treat Watch-BobTray as the pull worker' }
}

# --- BT0l tray hover (weekly remaining + machine tiles T1-T7) ---
Invoke-Case 'BT0l tray hover' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot

    $h = Get-BobTrayHover
    if ($null -ne $h.remaining_pct) { throw "idle remaining_pct=$($h.remaining_pct) expected null (no weekly log)" }
    if ([string]$h.title -ne '#Bobiverse (testhost)') { throw "title=$($h.title)" }
    if ([string]$h.scope -ne 'local-store') { throw "scope=$($h.scope)" }
    if ([string]$h.machine -ne 'testhost') { throw "machine=$($h.machine)" }
    if ([string]$h.body -match '(?i)no fleet jobs running') { throw "idle body still says no fleet jobs: $($h.body)" }
    if ([string]$h.jobs_text -notmatch '(?m)^Cursor Models \(') { throw "idle jobs_text missing Cursor Models account: $($h.jobs_text)" }
    if ([string]$h.jobs_text -notmatch '(?m)^[ ]{0,2}testhost \(') { throw "idle jobs_text missing testhost tile: $($h.jobs_text)" }
    if ([string]$h.account_name -ne 'Cursor Models') { throw "account_name=$($h.account_name)" }
    if ($null -ne $h.account_remaining_pct) { throw 'cursor account must not copy Grok Build xAI remaining' }
    if ([string]$h.jobs_text -notmatch 'no jobs') { throw "idle jobs_text missing no jobs: $($h.jobs_text)" }
    $hoverSrc = Get-Content (Join-Path $RepoRoot 'src\Public\Get-BobTrayHover.ps1') -Raw
    if ($hoverSrc -notmatch 'Get-BobLiveGrokAgents') { throw 'hover must include live grok.exe even if Bob did not start it' }
    $env:BOB_SKIP_LIVE_GROK = '1'
    if (@(Get-BobLiveGrokAgents).Count -ne 0) { throw 'BOB_SKIP_LIVE_GROK must suppress live grok scan' }
    if ([string]$h.remaining_kind -ne 'weekly') { throw "kind=$($h.remaining_kind)" }
    if ([string]$h.body -notmatch 'weekly remaining') { throw "body missing weekly remaining: $($h.body)" }
    if ([string]$h.body -match '(?i)context remaining') { throw "body still says context remaining: $($h.body)" }
    if ([string]$h.title -match '(?i)Bob \(') { throw "title branded as one machine: $($h.title)" }

    $paint = Get-BobTrayBarPaint -RemainingPct $h.remaining_pct -BarWidth 392
    if ($paint.known) { throw 'null remaining must be unknown' }
    if ($paint.show_track) { throw 'null remaining must hide track' }
    if ($paint.show_fill) { throw 'null remaining must not fill' }
    if ($null -ne $paint.fill_width) { throw "null remaining fill_width=$($paint.fill_width) must not be numeric (would look depleted)" }
    if ($paint.pulse) { throw 'must not pulse when remaining unknown' }
    if ($paint.caption -notmatch 'Weekly remaining') { throw "caption=$($paint.caption)" }
    if ($paint.caption -notmatch 'n/a') { throw "caption=$($paint.caption)" }

    $zero = Get-BobTrayBarPaint -RemainingPct 0 -BarWidth 392
    if (-not $zero.known) { throw '0% weekly remaining must be known' }
    if (-not $zero.show_track) { throw '0% must show empty track' }
    if ($zero.show_fill) { throw '0% must not draw a fill' }
    if ($zero.fill_width -ne 0) { throw "0% fill_width=$($zero.fill_width)" }
    if (-not $zero.pulse) { throw '0% weekly remaining must pulse' }
    if ([int]$zero.fill_r -le [int]$zero.fill_g) { throw "0% bar must be redder than green r=$($zero.fill_r) g=$($zero.fill_g)" }

    $full = Get-BobTrayBarPaint -RemainingPct 100 -BarWidth 392
    if ([int]$full.fill_g -le [int]$full.fill_r) { throw "100% bar must be greener than red r=$($full.fill_r) g=$($full.fill_g)" }
    if ($full.fill_width -le 0) { throw '100% must fill' }

    $mid = Get-BobTrayBarPaint -RemainingPct 50 -BarWidth 392
    if ($mid.fill_width -le 0) { throw "50% fill_width=$($mid.fill_width)" }
    if ($mid.pulse) { throw '50% must not pulse' }
    if ($mid.caption -notmatch 'Weekly remaining') { throw "50% caption=$($mid.caption)" }

    $nine = Get-BobTrayBarPaint -RemainingPct 9 -BarWidth 392
    if (-not $nine.show_fill) { throw '9% must show fill (drain as used, remaining fills left)' }
    if ($nine.fill_width -le 0) { throw "9% fill_width=$($nine.fill_width)" }
    if (-not $nine.pulse) { throw '9% weekly remaining must pulse' }

    $low = Get-BobTrayBarPaint -RemainingPct 5 -BarWidth 392
    if (-not $low.pulse) { throw '5% must pulse' }

    $emptyStr = Get-BobTrayBarPaint -RemainingPct '' -BarWidth 392
    if ($null -ne $emptyStr.fill_width) { throw 'empty-string remaining must not fill' }
    if ($emptyStr.pulse) { throw 'empty-string remaining must not pulse' }

    $akNone = Get-BobTrayAlertKind -Alerts @() -RemainingPct $null
    if ($akNone -ne 'none') { throw "alert=$akNone" }
    $akWeek = Get-BobTrayAlertKind -Alerts @() -RemainingPct 5
    if ($akWeek -ne 'weekly') { throw "alert=$akWeek" }
    $akWatch = Get-BobTrayAlertKind -Alerts @('ACTION_REQUIRED: watcher_down watcher_up=False') -RemainingPct 5
    if ($akWatch -ne 'watcher') { throw "alert=$akWatch" }
    $akStall = Get-BobTrayAlertKind -Alerts @('ACTION_REQUIRED: agent_stall Bob idle_sec=900') -RemainingPct $null
    if ($akStall -ne 'stall') { throw "alert=$akStall" }

    $weekLog = Join-Path $bridgeRoot 'weekly.jsonl'
    $weekLine = '{"ts":"2026-09-19T12:00:00Z","src":"shell","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":91.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-09-26T00:00:00Z"}}}}'
    [IO.File]::WriteAllText($weekLog, $weekLine + [Environment]::NewLine)
    $env:BOB_WEEKLY_LOG = $weekLog
    $w = Get-BobWeeklyRemaining -LogPath $weekLog
    if ($null -eq $w) { throw 'weekly parser returned null for 91% used' }
    if ([int]$w.remaining_pct -ne 9) { throw "91% used remaining=$($w.remaining_pct) expected 9" }
    $hw = Get-BobTrayHover
    if ([int]$hw.remaining_pct -ne 9) { throw "hover remaining_pct=$($hw.remaining_pct) expected 9 from weekly log" }
    if ([string]$hw.remaining_kind -ne 'weekly') { throw "kind=$($hw.remaining_kind)" }
    if ([string]$hw.body -notmatch 'weekly remaining  9%') { throw "body missing 9% weekly: $($hw.body)" }
    if ([string]$hw.short.Length -gt 63) { throw "short exceeds 63: $($hw.short)" }
    $pw = Get-BobTrayBarPaint -RemainingPct $hw.remaining_pct -BarWidth 392
    if ($pw.fill_width -le 0) { throw '9% weekly remaining must paint a fill' }
    if ($pw.caption -notmatch '9%') { throw "9% caption=$($pw.caption)" }

    $badWeek = Join-Path $bridgeRoot 'weekly-noperiod.jsonl'
    [IO.File]::WriteAllText($badWeek, '{"ts":"2026-09-19T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"}}}}' + [Environment]::NewLine)
    $wn = Get-BobWeeklyRemaining -LogPath $badWeek
    if ($null -ne $wn) { throw 'missing creditUsagePercent must be n/a, not invented' }

    $monthLog = Join-Path $bridgeRoot 'weekly-monthly.jsonl'
    [IO.File]::WriteAllText($monthLog, '{"ts":"2026-09-19T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":10.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}}}' + [Environment]::NewLine)
    $wm = Get-BobWeeklyRemaining -LogPath $monthLog
    if ($null -ne $wm) { throw 'monthly creditUsagePercent must not be reported as weekly remaining' }

    $noType = Join-Path $bridgeRoot 'weekly-notype.jsonl'
    [IO.File]::WriteAllText($noType, '{"ts":"2026-09-19T12:00:00Z","msg":"billing: fetched credits config","ctx":{"config":{"creditUsagePercent":10.0}}}' + [Environment]::NewLine)
    $wt = Get-BobWeeklyRemaining -LogPath $noType
    if ($null -ne $wt) { throw 'creditUsagePercent without weekly period type must be n/a' }

    $env:BOB_WEEKLY_LOG = $null

    $gitCwd = Join-Path $bridgeRoot 'irc-repo'
    New-Item -ItemType Directory -Force -Path $gitCwd | Out-Null
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { throw 'git required for owner/repo job-line test' }
    & git -C $gitCwd init -q
    & git -C $gitCwd remote add origin https://github.com/SimonBarnett/agentic_irc.git

    $jobId = '9f96bc0e-1111-2222-3333-444455556666'
    $runDir = Join-Path $bridgeRoot 'fleet\running\testhost'
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $job = [pscustomobject]@{
        id        = $jobId
        machine   = 'testhost'
        cwd       = $gitCwd
        claimedAt = [DateTime]::UtcNow.ToString('o')
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $runDir ($jobId + '.json')), ($job | ConvertTo-Json -Depth 6))

    $h2 = Get-BobTrayHover
    if ($h2.job_count -ne 1) { throw "job_count=$($h2.job_count)" }
    if ([string]$h2.title -ne '#Bobiverse (testhost)') { throw "running title=$($h2.title)" }
    if ([string]$h2.body -match '(?i)no fleet jobs running') { throw "running body says no fleet jobs: $($h2.body)" }
    if ([string]$h2.jobs_text -notmatch 'SimonBarnett/agentic_irc') { throw "jobs_text missing owner/repo: $($h2.jobs_text)" }
    if ([string]$h2.jobs_text -match '(?i)7e8797e|[0-9a-f]{40}') { throw "jobs_text looks like SHA: $($h2.jobs_text)" }
    $row = @($h2.jobs)[0]
    if ([string]$row.repo -ne 'SimonBarnett/agentic_irc') { throw "repo=$($row.repo)" }
    if ([string]$h2.jobs_text -notmatch '(?m)^[ ]{0,2}testhost \(') { throw "running jobs_text missing testhost tile" }
    if ($null -ne $h2.remaining_pct) { throw 'running without weekly log must keep remaining_pct null' }
    $paint2 = Get-BobTrayBarPaint -RemainingPct $h2.remaining_pct -BarWidth 392
    if ($null -ne $paint2.fill_width) { throw 'running without weekly log must not set fill_width' }

    $shaCwd = Join-Path $bridgeRoot '7e8797eabcdef'
    New-Item -ItemType Directory -Force -Path $shaCwd | Out-Null
    $job2Id = 'aaaaaaaa-1111-2222-3333-444455556666'
    $job2 = [pscustomobject]@{
        id        = $job2Id
        machine   = 'testhost'
        cwd       = $shaCwd
        claimedAt = [DateTime]::UtcNow.ToString('o')
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $runDir ($job2Id + '.json')), ($job2 | ConvertTo-Json -Depth 6))
    $h3 = Get-BobTrayHover
    $shaRow = @($h3.jobs) | Where-Object { $_.id -eq $job2Id } | Select-Object -First 1
    if (-not $shaRow) { throw 'missing SHA-cwd job row' }
    if ([string]$shaRow.repo -match '(?i)^[0-9a-f]{7,40}$') { throw "SHA cwd leaked as repo=$($shaRow.repo)" }
    if ([string]$h3.jobs_text -match '7e8797eabcdef') { throw "jobs_text shows SHA leaf: $($h3.jobs_text)" }

    $macDir = Join-Path $bridgeRoot 'fleet\machines'
    [IO.File]::WriteAllText((Join-Path $macDir 'otherhost.json'), '{"id":"otherhost"}')
    $otherGit = Join-Path $bridgeRoot 'formprep-repo'
    New-Item -ItemType Directory -Force -Path $otherGit | Out-Null
    & git -C $otherGit init -q
    & git -C $otherGit remote add origin git@github.com:SimonBarnett/FormPrep.git
    $otherId = 'bbbbbbbb-1111-2222-3333-444455556666'
    $otherDir = Join-Path $bridgeRoot 'fleet\running\otherhost'
    New-Item -ItemType Directory -Force -Path $otherDir | Out-Null
    $otherJob = [pscustomobject]@{
        id        = $otherId
        machine   = 'otherhost'
        cwd       = $otherGit
        claimedAt = [DateTime]::UtcNow.ToString('o')
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $otherDir ($otherId + '.json')), ($otherJob | ConvertTo-Json -Depth 6))
    $qId = 'cccccccc-1111-2222-3333-444455556666'
    $qDir = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    New-Item -ItemType Directory -Force -Path $qDir | Out-Null
    $qJob = [pscustomobject]@{
        id        = $qId
        machine   = 'testhost'
        cwd       = $gitCwd
        createdAt = [DateTime]::UtcNow.ToString('o')
        state     = 'queued'
    }
    [IO.File]::WriteAllText((Join-Path $qDir ($qId + '.json')), ($qJob | ConvertTo-Json -Depth 6))
    $h4 = Get-BobTrayHover
    if ([string]$h4.title -ne '#Bobiverse (testhost)') { throw "multi-machine title=$($h4.title)" }
    if ([string]$h4.jobs_text -notmatch '(?m)^[ ]{0,2}testhost \(') { throw "multi jobs_text missing testhost tile: $($h4.jobs_text)" }
    if ([string]$h4.jobs_text -notmatch '(?m)^[ ]{0,2}otherhost \(') { throw "multi jobs_text missing otherhost tile: $($h4.jobs_text)" }
    if ([string]$h4.jobs_text -notmatch 'SimonBarnett/FormPrep') { throw "otherhost missing owner/repo: $($h4.jobs_text)" }
    $idxThis = ([string]$h4.jobs_text).IndexOf("testhost")
    $idxPeer = ([string]$h4.jobs_text).IndexOf("otherhost")
    if ($idxThis -lt 0 -or $idxPeer -lt 0 -or $idxThis -gt $idxPeer) { throw "this host tile must be first: $($h4.jobs_text)" }
    $testhostBlock = ([string]$h4.jobs_text -split '(?m)^otherhost')[0]
    $runIdx = $testhostBlock.IndexOf('running')
    $qIdx = $testhostBlock.IndexOf('queued')
    if ($runIdx -lt 0 -or $qIdx -lt 0 -or $runIdx -gt $qIdx) { throw "testhost must list running before queued: $testhostBlock" }
    if ([string]$h4.jobs_text -match 'other hosts not in this store') { throw 'peer tiles present so must not claim other hosts missing' }
    $macIds = @($h4.machines | ForEach-Object { [string]$_.id })
    if ($macIds[0] -ne 'testhost') { throw "machines[0]=$($macIds[0]) expected testhost" }
    if ($macIds -notcontains 'otherhost') { throw 'machines missing otherhost' }

    $peerHome = Join-Path $bridgeRoot 'peer-marchhare'
    $peerRun = Join-Path $peerHome 'fleet\running\marchhare'
    New-Item -ItemType Directory -Force -Path $peerRun | Out-Null
    $peerGit = Join-Path $bridgeRoot 'peek-repo'
    New-Item -ItemType Directory -Force -Path $peerGit | Out-Null
    & git -C $peerGit init -q
    & git -C $peerGit remote add origin https://github.com/SimonBarnett/agentic_build.git
    $freshSeen = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $peerHome 'machine.json'), (@{ id = 'marchhare'; lastSeen = $freshSeen } | ConvertTo-Json))
    $peerJobId = 'dddddddd-1111-2222-3333-444455556666'
    $peerJob = [pscustomobject]@{
        id        = $peerJobId
        machine   = 'marchhare'
        cwd       = $peerGit
        repo      = 'SimonBarnett/agentic_build'
        claimedAt = $freshSeen
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $peerRun ($peerJobId + '.json')), ($peerJob | ConvertTo-Json -Depth 6))

    $staleHome = Join-Path $bridgeRoot 'peer-stale'
    New-Item -ItemType Directory -Force -Path (Join-Path $staleHome 'fleet\running\ce-priority-dev1') | Out-Null
    $oldSeen = [datetime]::UtcNow.AddHours(-6).ToString('o')
    [IO.File]::WriteAllText((Join-Path $staleHome 'machine.json'), (@{ id = 'ce-priority-dev1'; lastSeen = $oldSeen } | ConvertTo-Json))

    $deadHome = Join-Path $bridgeRoot 'peer-missing\does-not-exist'
    $regPath = Join-Path $bridgeRoot 'fleet\registry.json'
    $regObj = [ordered]@{
        staleAfterSec = 900
        peekTimeoutMs = 2000
        machines      = @(
            [ordered]@{ id = 'testhost'; hostname = 'testhost' },
            [ordered]@{ id = 'marchhare'; peekRoot = $peerHome },
            [ordered]@{ id = 'ionos'; peekRoot = $deadHome },
            [ordered]@{ id = 'ce-priority-dev1'; peekRoot = $staleHome }
        )
    }
    [IO.File]::WriteAllText($regPath, ($regObj | ConvertTo-Json -Depth 6))

    $h5 = Get-BobTrayHover
    if ([string]$h5.title -ne '#Bobiverse (testhost)') { throw "registry title=$($h5.title)" }
    if ([string]$h5.scope -ne 'fleet-peek') { throw "scope=$($h5.scope) expected fleet-peek" }
    if (-not $h5.peer_peek) { throw 'peer_peek should be true when registry has peers' }
    $txt = [string]$h5.jobs_text
    if ($txt -notmatch '(?m)^Cursor Models \(') { throw "h5 missing Cursor Models account: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}testhost \(') { throw "h5 missing testhost: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}otherhost \(') { throw "h5 missing otherhost: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}marchhare\b') { throw "h5 missing marchhare: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ionos\b') { throw "h5 missing ionos: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ce-priority-dev1\b') { throw "h5 missing ce-priority-dev1: $txt" }
    if ($txt -match 'other hosts not in this store') { throw 'registry peers present so must not claim other hosts missing' }
    if ($txt -notmatch '(?m)^[ ]{0,2}marchhare(?:  -  [^\r\n(]+)? \([^)]+\)\r?\n(?:[ ]+fuels:[^\r\n]+\r?\n)?[ ]+SimonBarnett/agentic_build') { throw "marchhare peek missing nested owner/repo: $txt" }
    if ($txt -match '(?m)^marchhare\r?\n  unreachable') { throw "marchhare reachable but marked unreachable: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ionos(?:  -  [^\r\n(]+)? \(') { throw "ionos missing MACHINENAME (pct) heading: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ionos(?:  -  [^\r\n(]+)? \([^)]+\)\r?\n(?:[ ]+fuels:[^\r\n]+\r?\n)?[ ]+not in moot') { throw "ionos must be not in moot: $txt" }
    if ($txt -match '(?m)^ionos\r?\n  unreachable') { throw "do not say unreachable for a box that is not in the moot: $txt" }
    if ($txt -notmatch '(?m)^[ ]{0,2}ce-priority-dev1(?:  -  [^\r\n(]+)? \([^)]+\)\r?\n(?:[ ]+fuels:[^\r\n]+\r?\n)?[ ]+lastSeen stale') { throw "stale peer must say lastSeen stale: $txt" }
    $ids5 = @($h5.machines | ForEach-Object { [string]$_.id })
    if ($ids5[0] -ne 'testhost') { throw "h5 machines[0]=$($ids5[0])" }
    foreach ($need in @('testhost', 'otherhost', 'marchhare', 'ionos', 'ce-priority-dev1')) {
        if ($ids5 -notcontains $need) { throw "h5 machines missing $need : $($ids5 -join ',')" }
    }
    $snapHome = Join-Path $bridgeRoot 'peer-snap'
    $snapPeekDir = Join-Path $snapHome 'fleet\peek'
    New-Item -ItemType Directory -Force -Path $snapPeekDir | Out-Null
    $snapNow = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText((Join-Path $snapHome 'machine.json'), (@{ id = 'snapbox'; lastSeen = $snapNow } | ConvertTo-Json))
    $env:BOB_MACHINE_ID = 'snapbox'
    $env:BOB_BRIDGE_HOME = $snapHome
    $null = Register-BobMachine -Id snapbox -CwdRoots $snapHome
    $snapRun = Join-Path $snapHome 'fleet\running\snapbox'
    New-Item -ItemType Directory -Force -Path $snapRun | Out-Null
    $sj1 = [pscustomobject]@{ id = 'eeeeeeee-1111-2222-3333-444455556666'; machine = 'snapbox'; cwd = $gitCwd; repo = 'SimonBarnett/agentic_irc'; claimedAt = $snapNow; state = 'running' }
    $sj2 = [pscustomobject]@{ id = 'ffffffff-1111-2222-3333-444455556666'; machine = 'snapbox'; cwd = $otherGit; repo = 'SimonBarnett/FormPrep'; claimedAt = $snapNow; state = 'running' }
    [IO.File]::WriteAllText((Join-Path $snapRun ($sj1.id + '.json')), ($sj1 | ConvertTo-Json -Depth 6))
    [IO.File]::WriteAllText((Join-Path $snapRun ($sj2.id + '.json')), ($sj2 | ConvertTo-Json -Depth 6))
    $mod = Get-Module BobBridge
    & $mod { Write-BobFleetPeekSnapshot }
    $written = Get-Content (Join-Path $snapPeekDir 'snapbox.json') -Raw
    if ($written -notmatch '"running":\[') { throw "snapshot JSON must keep running as an array: $written" }
    if ($written -match 'eeeeeeee-1111-2222-3333-444455556666 ffffffff') { throw "snapshot collapsed job ids (PS5 property unroll): $written" }
    if ($written -notmatch 'eeeeeeee-1111-2222-3333-444455556666') { throw "snapshot missing job 1: $written" }
    if ($written -notmatch 'ffffffff-1111-2222-3333-444455556666') { throw "snapshot missing job 2: $written" }

    $env:BOB_BRIDGE_HOME = $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $regObj.machines += [ordered]@{ id = 'snapbox'; peekRoot = $snapHome }
    [IO.File]::WriteAllText($regPath, ($regObj | ConvertTo-Json -Depth 6))
    $hSnap = Get-BobTrayHover
    $snapTxt = [string]$hSnap.jobs_text
    if ($snapTxt -notmatch '(?m)^[ ]{0,2}snapbox \([^)]+\)\r?\n(?:[ ]+fuels:[^\r\n]+\r?\n)?[ ]+SimonBarnett/') { throw "snapbox tile missing nested jobs: $snapTxt" }
    if ($snapTxt -notmatch 'SimonBarnett/agentic_irc') { throw "snapbox missing irc job: $snapTxt" }
    if ($snapTxt -notmatch 'SimonBarnett/FormPrep') { throw "snapbox missing FormPrep job: $snapTxt" }
    $snapTile = @($hSnap.machines | Where-Object { [string]$_.id -eq 'snapbox' })[0]
    if ([int]$snapTile.job_count -ne 2) { throw "snapbox job_count=$($snapTile.job_count) expected 2 (PS5 ConvertTo-Json collapse?)" }

    $ionosTile = @($h5.machines | Where-Object { [string]$_.id -eq 'ionos' })[0]
    if ([string]$ionosTile.reach -ne 'not-in-moot') { throw "ionos reach=$($ionosTile.reach)" }
    if ([int]$ionosTile.job_count -ne 0) { throw "ionos job_count=$($ionosTile.job_count) (invented?)" }
    $mhTile = @($h5.machines | Where-Object { [string]$_.id -eq 'marchhare' })[0]
    if ([int]$mhTile.job_count -lt 1) { throw 'marchhare peek job missing' }
    $staleTile = @($h5.machines | Where-Object { [string]$_.id -eq 'ce-priority-dev1' })[0]
    if ([string]$staleTile.reach -ne 'stale') { throw "stale reach=$($staleTile.reach)" }

    $peekDoc = Join-Path $RepoRoot 'docs\bob-fleet-peer-peek.md'
    if (-not (Test-Path $peekDoc)) { throw 'missing docs/bob-fleet-peer-peek.md' }
    $peekRaw = Get-Content $peekDoc -Raw
    if ($peekRaw -notmatch '(?i)winrm') { throw 'peer-peek doc must name WinRM (and reject it)' }
    if ($peekRaw -notmatch 'unreachable') { throw 'peer-peek doc must define unreachable' }

    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    foreach ($bad in @('No fleet jobs running', 'no fleet jobs running', 'Context remaining')) {
        if ($traySrc.Contains($bad)) { throw "Watch-BobTray still contains stale UI copy: $bad" }
    }
    if ($traySrc -notmatch 'jobs_text') { throw 'Watch-BobTray card must render jobs_text machine tiles' }
    if ($traySrc -notmatch 'Weekly remaining') { throw 'Watch-BobTray must label Weekly remaining' }
    if ($traySrc -notmatch 'Hide-BobTrayCard') { throw 'Watch-BobTray must have an X close (Hide-BobTrayCard)' }
    if ($traySrc -notmatch 'Rebuild-BobTrayTiles') { throw 'Watch-BobTray must paint one weekly bar per machine tile' }
    if ($traySrc -match 'New-BobTrayCursorBitmap') { throw 'Watch-BobTray must not draw a cursor icon on the account bar' }
    if ($traySrc -notmatch 'Clear-BobNativeTip') { throw 'dark card must clear native NotifyIcon tip to avoid double dialog' }
    if ($traySrc -notmatch 'HideTooltipWindows') { throw 'must pop shell tooltips_class32 so native tip does not stack on the card' }
    if ($traySrc -match 'ShowBalloonTip') { throw 'BalloonTip is a second dialog; use the dark card only' }
    if ($traySrc -match 'tip\.Show\(\)') { throw 'do not Form.Show after ShowParkedAt (second dialog)' }
    if ($traySrc -notmatch 'Transparent') { throw 'machine-name label BackColor must be Transparent so it does not cover the bar' }
    if ($traySrc -notmatch 'fill_r') { throw 'Watch-BobTray must use gradient fill_r/fill_g/fill_b' }
    if ($traySrc -notmatch 'Get-BobTrayBarPaint') { throw 'Watch-BobTray paint path does not use Get-BobTrayBarPaint' }
    if ($traySrc -notmatch 'Get-BobTrayBarPaint') { throw 'Watch-BobTray must paint weekly bars via Get-BobTrayBarPaint' }

    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch '(?i)weekly remaining') { throw 'bob-fleet-tray skill must document weekly remaining bar' }
    if ($skillTray -notmatch 'creditUsagePercent') { throw 'bob-fleet-tray skill must name creditUsagePercent source' }
    if ($skillTray -notmatch 'Bob Fleet') { throw 'bob-fleet-tray skill must name title Bob Fleet' }
    if ($skillTray -notmatch 'alert:') { throw 'bob-fleet-tray skill must document badge sources' }
    if ($skillTray -notmatch 'not in moot') { throw 'bob-fleet-tray skill must document not-in-moot tiles' }
    if ($skillTray -notmatch 'bobiverse') { throw 'bob-fleet-tray skill must name bobiverse seats' }
    if ($skillTray -notmatch 'marchhare-bugets') { throw 'bob-fleet-tray skill must reject ghost IRC ids' }
    if ($skillTray -notmatch 'lastSeen stale') { throw 'bob-fleet-tray skill must document lastSeen stale' }
    if ($skillTray -notmatch 'bob-fleet-peer-peek') { throw 'bob-fleet-tray skill must point at peer-peek transport doc' }
    $skillBox = Get-Content (Join-Path $RepoRoot '.grok\skills\box-usage\SKILL.md') -Raw
    if ($skillBox -notmatch '(?i)weekly') { throw 'box-usage skill must document weekly vs context' }
    if ($skillBox -notmatch 'creditUsagePercent') { throw 'box-usage skill must name creditUsagePercent source' }
}

# --- BT0m tray tip placement (NC-T01..NC-T03) ---
Invoke-Case 'BT0m tray tip placement' {
    $icon = @{ X = 1880; Y = 1048; Width = 24; Height = 24 }
    $work = @{ X = 0; Y = 0; Width = 1920; Height = 1040 }
    $cursorA = @{ X = 1892; Y = 1060 }
    $p = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 -IconRect $icon -Cursor $cursorA -WorkArea $work
    if ($p.source -ne 'icon') { throw "source=$($p.source) expected icon" }
    if (-not $p.moved) { throw 'first place must set moved' }
    if ($p.x -ne 1484) { throw "icon x=$($p.x) expected 1484 (right-aligned to icon)" }
    if ($p.y -lt 0) { throw "icon y=$($p.y)" }
    if (($p.y + 120) -gt 1040) { throw "icon y=$($p.y) not clamped into work area" }
    $iconX = $p.x
    $iconY = $p.y

    $cursorB = @{ X = 400; Y = 300 }
    $sticky = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 -IconRect $icon -Cursor $cursorB -WorkArea $work -AlreadyVisible $true -CurrentX $iconX -CurrentY $iconY
    if ($sticky.source -ne 'sticky') { throw "already-visible source=$($sticky.source)" }
    if ($sticky.moved) { throw 'already visible must not move' }
    if ($sticky.x -ne $iconX -or $sticky.y -ne $iconY) { throw "sticky moved from $iconX,$iconY to $($sticky.x),$($sticky.y)" }

    $cur = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 -Cursor @{ X = 800; Y = 600 } -WorkArea @{ X = 0; Y = 0; Width = 1920; Height = 1080 }
    if ($cur.source -ne 'cursor') { throw "missing-icon source=$($cur.source)" }
    if ($cur.x -ne 380) { throw "cursor x=$($cur.x) expected 800-420" }
    if ($cur.y -ne 468) { throw "cursor y=$($cur.y) expected 600-120-12" }

    $clamp = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 -Cursor @{ X = 10; Y = 10 } -WorkArea @{ X = 0; Y = 0; Width = 1920; Height = 1080 }
    if ($clamp.x -lt 8 -or $clamp.y -lt 8) { throw "cursor clamp x=$($clamp.x) y=$($clamp.y)" }

    $topBar = Get-BobTrayTipPlacement -TipWidth 420 -TipHeight 120 `
        -IconRect @{ X = 1880; Y = 4; Width = 24; Height = 24 } `
        -Cursor @{ X = 1890; Y = 16 } `
        -WorkArea @{ X = 0; Y = 40; Width = 1920; Height = 1040 }
    if ($topBar.source -ne 'icon') { throw 'top-taskbar must use icon' }
    if ($topBar.y -lt 40) { throw "top-taskbar y=$($topBar.y) should sit in work area below icon" }

    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($traySrc -notmatch 'Get-BobTrayTipPlacement') { throw 'Watch-BobTray must call Get-BobTrayTipPlacement' }
    if ($traySrc -notmatch 'AlreadyVisible') { throw 'Watch-BobTray must pass AlreadyVisible to placement' }
    if ($traySrc -notmatch '(?s)if \(-not \(Test-BobTrayTipVisible\)\).{0,800}Get-BobTrayTipPlacement') {
        throw 'Get-BobTrayTipPlacement must run only when tip is not visible'
    }
    if ($traySrc -match '\$x = \$pt\.X - \$tip\.Width') { throw 'Watch-BobTray still derives Location from cursor X every move' }
    if ($traySrc -notmatch 'ShowWithoutActivation') { throw 'tip form missing ShowWithoutActivation (NC-T02)' }
    if ($traySrc -notmatch '0x08000000') { throw 'tip form missing WS_EX_NOACTIVATE (NC-T02)' }
    if ($traySrc -notmatch 'Shell_NotifyIconGetRect') { throw 'Watch-BobTray should prefer Shell_NotifyIconGetRect' }
    foreach ($bad in @('Bob fleet', 'No fleet jobs running', 'no fleet jobs running')) {
        if ($traySrc.Contains($bad)) { throw "Watch-BobTray still contains fleet UI copy: $bad" }
    }

    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch 'Get-BobTrayTipPlacement') { throw 'bob-fleet-tray skill must name Get-BobTrayTipPlacement' }
    if ($skillTray -notmatch '(?i)already visible') { throw 'bob-fleet-tray skill must document already-visible sticky contract' }
    if ($skillTray -notmatch 'ShowWithoutActivation') { throw 'bob-fleet-tray skill must document ShowWithoutActivation' }
}

# --- BT0n tray tip show (NC-D01 / NC-D02) ---
Invoke-Case 'BT0n tray tip show' {
    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($traySrc -notmatch 'function Show-BobTrayCard') { throw 'Watch-BobTray missing Show-BobTrayCard' }
    if ($traySrc -match "Show-BobTrayCard -Reason 'hover'") { throw 'MouseMove must not Show-BobTrayCard (hover stacked a second TipForm)' }
    if ($traySrc -match 'Add_MouseMove') { throw 'no hover events: Add_MouseMove must be gone' }
    if ($traySrc -match '\$iconProbe') { throw 'no hover events: iconProbe timer must be gone' }
    if ($traySrc -match '\$hideTip') { throw 'card must stay parked until X; hideTip auto-hide must be gone' }
    if ($traySrc -notmatch "Show-BobTrayCard -Reason 'click'") { throw 'left-click / Status must show the dark card' }
    if ($traySrc -match '(?s)overTip.{0,240}cardClosed = \$false') { throw 'must not rearm hover by clearing cardClosed when leaving the tip' }
    if ($traySrc -match 'function Restore-BobNativeTip') { throw 'must not restore NotifyIcon.Text (white P+ idle chip is the double dialog)' }
    if ($traySrc -match '\$notify\.Text = \$') { throw 'must not assign NotifyIcon.Text from a short P+ string' }
    if ($traySrc -notmatch 'IsDisposed') { throw 'TipForm access must guard IsDisposed' }
    if ($traySrc -notmatch 'TryHide') { throw 'TipForm must TryHide so the TOPMOST HWND is actually hidden' }
    if ($traySrc -notmatch 'SWP_HIDEWINDOW') { throw 'TryHide must use SWP_HIDEWINDOW' }
    if ($traySrc -notmatch 'Initialize-BobTrayTipForm') { throw 'disposed TipForm must recreate via Initialize-BobTrayTipForm' }
    if ($traySrc -notmatch 'LiveCount') { throw 'TipForm must expose LiveCount so only one instance is live' }
    if ($traySrc -match '(?s)function Show-BobTrayCard.{0,500}Update-Hover') { throw 'Show-BobTrayCard must not Get-BobTrayHover/Update-Hover (idle hover would freeze on peer DNS)' }
    $peekSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Get-BobFleetPeek.ps1') -Raw
    if ($peekSrc -notmatch '(?s)function Test-BobHostnameResolves.+Invoke-BobTimed') {
        throw 'Test-BobHostnameResolves must time out DNS so idle tray hover stays instant'
    }
    if ($traySrc -notmatch "Show-BobTrayCard -Reason 'click'") { throw 'left-click must show card (overflow fallback)' }
    if ($traySrc -notmatch 'ShowParkedAt') { throw 'tip form must force-show via ShowParkedAt' }
    if ($traySrc -notmatch 'SetWindowPos') { throw 'tip show must use SetWindowPos' }
    if ($traySrc -notmatch 'SWP_NOACTIVATE') { throw 'SetWindowPos must pass SWP_NOACTIVATE' }
    if ($traySrc -notmatch 'SWP_SHOWWINDOW') { throw 'SetWindowPos must pass SWP_SHOWWINDOW' }
    if ($traySrc -notmatch 'tip show fail') { throw 'Watch-BobTray must log tip show failures' }
    if ($traySrc -notmatch 'tip hide error') { throw 'Watch-BobTray must log tip hide failures' }
    if ($traySrc -notmatch 'iconRectCache') { throw 'icon rect must be cached off the NotifyIcon callback' }
    if ($traySrc -match '(?s)Add_MouseMove\(\{.{0,400}Get-BobNotifyIconRect') {
        throw 'Do not call Shell_NotifyIconGetRect / Get-BobNotifyIconRect from MouseMove'
    }
    if ($traySrc -notmatch '(?s)if \(-not \(Test-BobTrayTipVisible\)\).{0,800}Get-BobTrayTipPlacement') {
        throw 'Get-BobTrayTipPlacement must run only when tip is not visible'
    }
    if ($traySrc -match '\$x = \$pt\.X - \$tip\.Width') { throw 'Watch-BobTray still derives Location from cursor X every move' }
    foreach ($bad in @('Bob fleet', 'No fleet jobs running', 'no fleet jobs running')) {
        if ($traySrc.Contains($bad)) { throw "Watch-BobTray still contains fleet UI copy: $bad" }
    }

    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch '(?i)left-click') { throw 'bob-fleet-tray skill must document left-click card show' }
    if ($skillTray -notmatch '(?i)P\+ idle') { throw 'bob-fleet-tray skill must name the native P+ idle chip as the fail' }
    if ($skillTray -notmatch '(?i)Never park') { throw 'bob-fleet-tray skill must forbid parking NotifyIcon.Text' }
    if ($skillTray -notmatch 'ShowParkedAt') { throw 'bob-fleet-tray skill must document ShowParkedAt' }
    if ($skillTray -notmatch '(?i)watch_bob_tray\.log') { throw 'bob-fleet-tray skill must name the tray log' }
    if ($skillTray -notmatch '(?i)hideTip') { throw 'bob-fleet-tray skill must say no hideTip auto-hide' }
    if ($skillTray -notmatch '_Watch-Bobiverse-ionos') { throw 'bob-fleet-tray skill must name _Watch-Bobiverse-ionos Restart path' }
    if ($traySrc -notmatch 'Stop-BobiverseMoot') { throw 'Restart watcher must kill Watch-Bobiverse + bobiverse irc_agent' }
    if ($traySrc -notmatch 'Restart-BobTrayWatcher') { throw 'tray Restart watcher must rejoin #bobiverse' }
    if ($traySrc -notmatch '_Watch-Bobiverse') { throw 'Restart watcher must start _Watch-Bobiverse-<id> wrapper' }
    if ($traySrc -notmatch "Restart watcher") { throw 'right-click menu must include Restart watcher' }
    if (-not (Test-Path (Join-Path $RepoRoot 'tools\_Watch-Bobiverse-ionos.ps1'))) { throw 'missing tools/_Watch-Bobiverse-ionos.ps1' }
    $installSrc = Get-Content (Join-Path $RepoRoot 'tools\Install-BobFleet.ps1') -Raw
    if ($installSrc -notmatch '_Watch-Bobiverse-') { throw 'Install-BobFleet must register _Watch-Bobiverse-<id>' }

    $onWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
    if (-not $onWindows) {
        Write-Host 'BT0n STA ShowParkedAt smoke skipped (WinForms not available on this host)'
        return
    }
    $sta = {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        if (-not ('BobTrayShowTest.TipForm' -as [type])) {
            $refs = @(
                [System.Windows.Forms.Form].Assembly.Location,
                [System.Drawing.Point].Assembly.Location
            )
            Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace BobTrayShowTest {
    public static class Shell {
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public const int SW_SHOWNA = 8;
        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;
        public const uint SWP_HIDEWINDOW = 0x0080;
    }
    public class TipForm : Form {
        static TipForm _live;
        public static int LiveCount {
            get { return (_live != null && !_live.IsDisposed) ? 1 : 0; }
        }
        public TipForm() { _live = this; }
        protected override void Dispose(bool disposing) {
            if (object.ReferenceEquals(_live, this)) _live = null;
            base.Dispose(disposing);
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x08000000;
                cp.ExStyle |= 0x00000080;
                cp.ExStyle |= 0x00000008;
                return cp;
            }
        }
        public bool TryHide() {
            if (this.IsDisposed) return true;
            try {
                if (this.IsHandleCreated) {
                    Shell.SetWindowPos(this.Handle, System.IntPtr.Zero, 0, 0, 0, 0,
                        Shell.SWP_NOSIZE | Shell.SWP_NOMOVE | Shell.SWP_NOACTIVATE | Shell.SWP_HIDEWINDOW);
                }
                if (this.Visible) this.Hide();
                return this.IsDisposed || !this.Visible;
            } catch (System.ObjectDisposedException) { return true; }
        }
        public bool ShowParkedAt(int x, int y) {
            if (this.IsDisposed) return false;
            try {
                this.Left = x; this.Top = y;
                if (!this.IsHandleCreated) this.CreateHandle();
                if (this.IsDisposed) return false;
                Shell.SetWindowPos(this.Handle, Shell.HWND_TOPMOST, x, y, this.Width, this.Height,
                    Shell.SWP_NOACTIVATE | Shell.SWP_SHOWWINDOW);
                if (!this.Visible) this.Visible = true;
                return !this.IsDisposed && this.Visible;
            } catch (System.ObjectDisposedException) { return false; }
        }
    }
}
'@
        }
        $f = New-Object BobTrayShowTest.TipForm
        $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $f.ShowInTaskbar = $false
        $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $f.Size = New-Object System.Drawing.Size 200, 80
        $ok = $false
        try {
            $ok = [bool]$f.ShowParkedAt(48, 48)
            if (-not $f.Visible) { throw 'ShowParkedAt did not set Visible' }
            if (-not $ok) { throw 'ShowParkedAt returned false' }
            if ([int][BobTrayShowTest.TipForm]::LiveCount -ne 1) { throw 'LiveCount must be 1 while shown' }
            if (-not $f.TryHide()) { throw 'TryHide failed' }
            $f.Dispose()
            $after = $false
            try { $after = [bool]$f.ShowParkedAt(48, 48) } catch { throw 'ShowParkedAt on disposed form must not throw' }
            if ($after) { throw 'ShowParkedAt on disposed form must return false' }
            $hid = $false
            try { $hid = [bool]$f.TryHide() } catch { throw 'TryHide on disposed form must not throw' }
            if (-not $hid) { throw 'TryHide on disposed form must return true' }
            if ([int][BobTrayShowTest.TipForm]::LiveCount -ne 0) { throw 'LiveCount must be 0 after dispose' }
        }
        finally {
            try { if (-not $f.IsDisposed) { $f.Hide(); $f.Dispose() } } catch { }
        }
        'ok'
    }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($sta.ToString())
    try {
        $out = $ps.Invoke()
        if ($ps.HadErrors) {
            $err = @($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
            throw "STA ShowParkedAt smoke failed: $err"
        }
        if ([string]$out[-1] -ne 'ok') { throw "STA ShowParkedAt smoke output=$out" }
    }
    finally {
        $ps.Dispose()
        $rs.Dispose()
    }
}

# --- BT0o bobiverse IRC fallback (no SMB) ---
Invoke-Case 'BT0o bobiverse irc' {
    param($bridgeRoot)
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $pt = ConvertTo-BobIrcPoint ([pscustomobject]@{
            id       = 'ionos'
            weekly   = 4
            running  = 1
            queued   = 0
            lastSeen = [DateTime]::UtcNow.ToString('o')
            jobs     = @([pscustomobject]@{ repo = 'SimonBarnett/agentic_build'; state = 'running' })
        })
    if ($pt -notmatch '^BOB v1 id=ionos') { throw "point=$pt" }
    $parsed = ConvertFrom-BobIrcPoint $pt
    if ($parsed.id -ne 'ionos') { throw "parsed id=$($parsed.id)" }
    if ([int]$parsed.weekly -ne 4) { throw "weekly=$($parsed.weekly)" }
    if ($parsed.jobs[0].repo -ne 'SimonBarnett/agentic_build') { throw 'job repo missing' }

    $ircHome = Join-Path $bridgeRoot 'irc-home'
    $peerDir = Join-Path $ircHome 'bob-peers'
    New-Item -ItemType Directory -Force -Path $peerDir | Out-Null
    $env:BOB_IRC_HOME = $ircHome
    $fresh = [DateTime]::UtcNow.ToString('o')
    $ionosPeer = @{
        ok       = $true
        id       = 'ionos'
        weekly   = 4
        running  = 1
        queued   = 0
        lastSeen = $fresh
        jobs     = @(@{ repo = 'SimonBarnett/agentic_build'; state = 'running'; machine = 'ionos'; id = 'irc-job-1' })
        source   = 'irc'
    } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $peerDir 'ionos.json'), $ionosPeer)
    $macDir = Join-Path $bridgeRoot 'fleet\machines'
    New-Item -ItemType Directory -Force -Path $macDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $macDir 'ionos.json'), '{"id":"ionos"}')
    $h = Get-BobTrayHover
    $txt = [string]$h.jobs_text
    if ($txt -notmatch '(?m)^[ ]{0,2}ionos\b') { throw "missing ionos tile: $txt" }
    if ($txt -match '(?m)^ionos\r?\n  unreachable') { throw "IRC peer marked unreachable: $txt" }
    if ($txt -notmatch 'SimonBarnett/agentic_build') { throw "IRC jobs missing: $txt" }
    $tile = @($h.machines | Where-Object { [string]$_.id -eq 'ionos' })[0]
    if ([string]$tile.reach -ne 'irc-fallback') { throw "reach=$($tile.reach)" }

    $cfg = Get-Content (Join-Path $RepoRoot 'config\bobiverse.json') -Raw | ConvertFrom-Json
    if ([string]$cfg.channel -ne '#bobiverse') { throw "channel=$($cfg.channel)" }
    if ([string]$cfg.mode -ne 'free') { throw "mode=$($cfg.mode)" }
    if ([string]$cfg.host -ne 'irc.ntsa.uk') { throw "host=$($cfg.host)" }
    if ([string]$cfg.nicks.flamingo -ne 'bob-flamingo') { throw 'flamingo nick' }
    $installIrc = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrc.ps1') -Raw
    if ($installIrc -notmatch 'AGENTIC_IRC_PASSWORD') { throw 'Install-BobIrc must load connect.password' }

    $env:BOB_IRC_CONFIG = Join-Path $RepoRoot 'config\bobiverse.json'
    $mootDir = Join-Path $ircHome 'moot'
    New-Item -ItemType Directory -Force -Path $mootDir | Out-Null
    $tx = '1700000000 bob-marchhare POINT BOB v1 id=marchhare weekly=40 running=0 queued=0 lastSeen=2026-09-20T10:00:00Z jobs=-'
    [IO.File]::WriteAllText((Join-Path $mootDir ($cfg.mootId + '.txt')), $tx)
    $got = @(Import-BobIrcPeerTranscript)
    $mh = Read-BobIrcPeer -Id marchhare
    if (-not $mh) { throw 'transcript harvest did not write marchhare peer' }
    if ([int]$mh.weekly -ne 40) { throw "harvest weekly=$($mh.weekly)" }

    $ghostTx = @(
        '1700000001 evil POINT BOB v1 id=marchhare-bugets weekly=9 running=0 queued=0 lastSeen=2026-09-20T10:00:00Z jobs=-'
        '1700000002 bob-flamingo POINT BOB v1 id=bob-flamingo weekly=20 running=0 queued=0 lastSeen=2026-09-20T10:00:00Z jobs=-'
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $mootDir ($cfg.mootId + '.txt')), $tx + "`n" + $ghostTx)
    $got2 = @(Import-BobIrcPeerTranscript)
    if ($got2 -contains 'marchhare-bugets') { throw 'ghost IRC id marchhare-bugets must not be harvested' }
    if (Test-Path (Join-Path $peerDir 'marchhare-bugets.json')) { throw 'must not write bob-peers/marchhare-bugets.json' }
    if ($got2 -notcontains 'flamingo') { throw 'id=bob-flamingo POINT must resolve to flamingo' }
    $macDir2 = Join-Path $bridgeRoot 'fleet\machines'
    New-Item -ItemType Directory -Force -Path $macDir2 | Out-Null
    [IO.File]::WriteAllText((Join-Path $macDir2 'marchhare-bugets.json'), '{"id":"marchhare-bugets"}')
    $hSeats = Get-BobTrayHover
    $seatIds = @($hSeats.machines | ForEach-Object { [string]$_.id })
    if ($seatIds -contains 'marchhare-bugets') { throw "ghost tile leaked: $($seatIds -join ',')" }
    foreach ($need in @('flamingo', 'ionos', 'marchhare', 'ce-priority-dev1')) {
        if ($seatIds -notcontains $need) { throw "missing bobiverse seat $need : $($seatIds -join ',')" }
    }
    $ionosSeat = @($hSeats.machines | Where-Object { [string]$_.id -eq 'ionos' })[0]
    if ([string]$ionosSeat.reach -ne 'irc-fallback') { throw "ionos seat reach=$($ionosSeat.reach) expected irc-fallback" }
    if ([string]$hSeats.jobs_text -match 'marchhare-bugets') { throw "jobs_text has ghost: $($hSeats.jobs_text)" }

    $watchBv = Get-Content (Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1') -Raw
    if ($watchBv -notmatch 'irc\.ntsa\.uk') { throw 'Watch-Bobiverse must require irc.ntsa.uk' }
    if ($watchBv -match 'grok\.exe') { throw 'Watch-Bobiverse must not invoke grok.exe' }
    if ($watchBv -match 'Start-BobWorker|Invoke-BobFleetTick|Send-BobPrompt') { throw 'Watch-Bobiverse must not start a Grok reasoning job' }
    if ($watchBv -notmatch 'Write-BobIrcStatus') { throw 'Watch-Bobiverse must POINT via Write-BobIrcStatus' }
    if ($watchBv -notmatch 'Import-BobIrcPeerTranscript') { throw 'Watch-Bobiverse must poll peer POINT lines' }
    if ($watchBv -notmatch 'BOB_IRC_HOST') { throw 'Watch-Bobiverse must honor BOB_IRC_HOST' }
    if ($watchBv -notmatch '127\.0\.0\.1') { throw 'Watch-Bobiverse must treat 127.0.0.1 as private Ergo' }
    if ($watchBv -notmatch 'Test-BobiverseIrcPrivateErgoHost') { throw 'Watch-Bobiverse must share private-Ergo host match' }
    if ($watchBv -match '(?m)^\s*\$ircHost\s*=\s*[''"]127\.0\.0\.1[''"]') { throw 'must not default ionos to 127.0.0.1' }
    if ($watchBv -notmatch 'Compact-BobIrcOutbox') { throw 'Start-BobiverseIrcAgent must compact a fat POINT outbox' }
    $installIrc2 = Get-Content (Join-Path $RepoRoot 'tools\Install-BobIrc.ps1') -Raw
    if ($installIrc2 -notmatch 'Compact-BobIrcOutbox') { throw 'Install-BobIrc must compact a fat POINT outbox' }
    $docsBv = Get-Content (Join-Path $RepoRoot 'docs\bobiverse.md') -Raw
    if ($docsBv -notmatch 'Outbox POINT backlog') { throw 'docs/bobiverse.md must note POINT backlog disconnect loop' }

    $env:BOB_MACHINE_ID = 'testhost'
    $ob = Join-Path $ircHome 'outbox.txt'
    if (Test-Path $ob) { Remove-Item -LiteralPath $ob -Force }
    Write-BobIrcStatus | Out-Null
    Write-BobIrcStatus | Out-Null
    if (-not (Test-Path $ob)) { throw 'Write-BobIrcStatus did not create outbox' }
    $obLines = @(Get-Content $ob | Where-Object { $_ })
    if ($obLines.Count -ne 1) { throw "dedupe failed: outbox lines=$($obLines.Count)" }
    if ($obLines[0] -notmatch 'MOOT v1 POINT' -or $obLines[0] -notmatch 'BOB v1 ') { throw "outbox line=$($obLines[0])" }
    Add-Content -Path $ob -Value 'MOOT v1 POINT b0b1be15e0000001 :BOB v1 id=testhost weekly=99 reset=- cur=- crst=- running=0 queued=0 lastSeen=2026-09-20T00:00:00Z jobs=-' -Encoding utf8
    Write-BobIrcStatus | Out-Null
    $obLines2 = @(Get-Content $ob | Where-Object { $_ })
    if ($obLines2.Count -ne 3) { throw "status change must append: outbox lines=$($obLines2.Count)" }

    $fatHome = Join-Path $bridgeRoot 'irc-fat'
    New-Item -ItemType Directory -Force -Path $fatHome | Out-Null
    $fatOut = Join-Path $fatHome 'outbox.txt'
    $sample = 'MOOT v1 POINT b0b1be15e0000001 :BOB v1 id=testhost weekly=1 reset=- cur=- crst=- running=0 queued=0 lastSeen=2026-09-20T00:00:00Z jobs=-'
    $fat = New-Object System.Collections.Generic.List[string]
    [void]$fat.Add('PRIVMSG #bobiverse :keep-me')
    while (([Text.Encoding]::UTF8.GetByteCount(($fat -join "`n"))) -lt 33000) { [void]$fat.Add($sample) }
    [IO.File]::WriteAllLines($fatOut, $fat)
    Compact-BobIrcOutbox -Home $fatHome
    $after = @(Get-Content $fatOut | Where-Object { $_ })
    if ($after.Count -ne 2) { throw "compact kept $($after.Count) lines (want PRIVMSG + latest POINT)" }
    if ($after[0] -notmatch 'keep-me') { throw 'compact dropped non-POINT line' }
    if ($after[1] -notmatch 'id=testhost') { throw 'compact lost self POINT' }
    $tickSrc = Get-Content (Join-Path $RepoRoot 'src\Private\Invoke-BobFleet.ps1') -Raw
    if ($tickSrc -match 'Write-BobIrcStatus') { throw 'fleet tick must not POINT; that is Watch-Bobiverse automation' }

    $cursorFile = Join-Path $bridgeRoot 'cursor-usage.json'
    '{"percentUsed":98}' | Set-Content -Path $cursorFile -Encoding utf8
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile
    $cu = Get-BobCursorAgentWeeklyRemaining
    if ([int]$cu.used_pct -ne 98) { throw "cursor used=$($cu.used_pct)" }
    if ([int]$cu.remaining_pct -ne 2) { throw "cursor remaining=$($cu.remaining_pct) expected 2 from 98% used" }
    $hCur = Get-BobTrayHover
    if ([int]$hCur.account_remaining_pct -ne 2) { throw "hover cursor remaining=$($hCur.account_remaining_pct)" }
    if ([string]$hCur.jobs_text -notmatch '(?m)^Cursor Models \(2%\)') { throw "jobs_text cursor=$($hCur.jobs_text)" }
    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    if ($traySrc -notmatch 'Watch-Bobiverse\.ps1') { throw 'tray must start Watch-Bobiverse, not a grok job' }
    if ($traySrc -match 'Start-IrcWatcher[\s\S]{0,400}Install-BobIrc') { throw 'tray must not run Install-BobIrc on every poll' }
}

# --- BT0o2 Cursor Models spending meter vs Sand (issue #21 / #25) ---
Invoke-Case 'BT0o2 cursor models spending meter' {
    param($bridgeRoot)
    $apiFixture = Join-Path $bridgeRoot 'cursor-spending-api-fixture.json'
    @'
{
  "period": {
    "planUsage": { "autoPercentUsed": 1 },
    "billingCycleEnd": "2026-10-16T00:00:00Z",
    "spendLimitUsage": { "individualUsed": 6850 }
  },
  "sand": {
    "usagePercent": 100,
    "nextResetTimestampUtc": "2026-09-23T00:00:00Z"
  }
}
'@ | Set-Content -Path $apiFixture -Encoding utf8
    $py = $null
    foreach ($c in @(
            'python',
            'py',
            'C:\Python\Python312\python.exe',
            'C:\Python\Python313\python.exe',
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe')
        )) {
        if (-not $c) { continue }
        if ($c -eq 'python' -or $c -eq 'py') {
            try {
                $probe = & $c -c "import sys; print(sys.executable)" 2>$null
                if ($probe) { $py = $c; break }
            }
            catch { }
            continue
        }
        if (Test-Path $c) { $py = $c; break }
    }
    if (-not $py) { throw 'python required for Get-CursorAgentUsage parser test' }
    $script = Join-Path $RepoRoot 'tools\Get-CursorAgentUsage.py'
    $env:BOB_CURSOR_AGENT_FIXTURE = $apiFixture
    $env:BOB_CURSOR_USD_GBP_RATE = '0.7918'
    $parsedRaw = & $py $script 2>$null
    if (-not $parsedRaw) { throw 'Get-CursorAgentUsage fixture run returned empty' }
    $parsed = $parsedRaw | ConvertFrom-Json
    if ([int]$parsed.used_pct -ne 1) { throw "parser used_pct=$($parsed.used_pct) expected 1 from autoPercentUsed=1" }
    if ([int]$parsed.remaining_pct -ne 99) { throw "parser remaining_pct=$($parsed.remaining_pct) expected 99" }
    if ([string]$parsed.period_end -notmatch '2026-10-16') { throw "parser period_end=$($parsed.period_end) expected Cursor Models Oct 16" }
    if ([string]$parsed.period_end -match '2026-09-23') { throw 'parser must not use Sand reset as Cursor Models period_end' }
    if ([int]$parsed.sand_used_pct -ne 100) { throw "parser sand_used_pct=$($parsed.sand_used_pct)" }
    $cursorFile = Join-Path $bridgeRoot 'cursor-spending-meter-doc.json'
    $parsedRaw | Set-Content -Path $cursorFile -Encoding utf8
    $env:BOB_CURSOR_USAGE_FILE = $cursorFile
    $env:BOB_CURSOR_AGENT_FIXTURE = $null
    $cu = Get-BobCursorAgentWeeklyRemaining
    if ([int]$cu.used_pct -ne 1) { throw "cursor models used=$($cu.used_pct) expected 1" }
    if ([int]$cu.remaining_pct -ne 99) { throw "cursor models remaining=$($cu.remaining_pct) expected 99 (not Sand/overage)" }
    if ($null -eq $cu.sand_remaining_pct -or [int]$cu.sand_remaining_pct -ne 0) { throw "sand_remaining_pct=$($cu.sand_remaining_pct)" }
    if (-not $cu.sand_exhausted) { throw 'sand_exhausted must be true' }
    if ($null -eq $cu.overage_gbp) { throw 'overage_gbp must remain a separate field' }
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $cap = Get-BobCapacity
    if ([int]$cap.cursor_models.remaining_pct -ne 99) { throw "capacity cursor_models=$($cap.cursor_models.remaining_pct)" }
    if ([string]$cap.cursor_models.period_end -notmatch '2026-10-16') { throw "capacity period_end=$($cap.cursor_models.period_end)" }
    if ([string]$cap.cursor_models.period_end -match '2026-09-23') { throw 'capacity must not use Sand reset for cursor_models.period_end' }
    $hostRow = @($cap.machines | Where-Object { [string]$_.id -eq 'testhost' })[0]
    if ($null -eq $hostRow.grok_bot.remaining_pct -or [int]$hostRow.grok_bot.remaining_pct -ne 0) {
        throw "grok_bot.remaining_pct=$($hostRow.grok_bot.remaining_pct) expected Sand slot 0"
    }
    if ([int]$cap.cursor_models.remaining_pct -le 0) {
        throw 'Sand 100% + overage must not block cursor-models fuel'
    }
    $pick = Select-BobGitWorker -Capacity $cap
    if ($pick.wait -or [string]$pick.fuel -ne 'cursor-models') {
        throw "Select-BobGitWorker expected cursor-models got fuel=$($pick.fuel) wait=$($pick.wait)"
    }
    $hCur = Get-BobTrayHover
    if ([int]$hCur.account_remaining_pct -ne 99) { throw "hover cursor remaining=$($hCur.account_remaining_pct)" }
    if ([string]$hCur.jobs_text -notmatch '(?m)^Cursor Models \(99%\)') { throw "jobs_text must show Cursor Models (99%): $($hCur.jobs_text)" }
    if ([string]$hCur.jobs_text -match [char]0x00A3) { throw 'jobs_text must not show Sand overage GBP as Cursor Models remaining' }
}

# --- BT0p git-task capacity picker (issue #8) ---
Invoke-Case 'BT0p git-task picker' {
    param($bridgeRoot)
    $fixture = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99; period_end = '2026-10-01T00:00:00Z' }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ remaining_pct = 0; available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'ionos'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @('C:\ai'); grok_build = [pscustomobject]@{ remaining_pct = 100; period_end = '2026-09-27T00:00:00Z' }
                grok_bot = [pscustomobject]@{ remaining_pct = 0; period_end = '2026-09-23T00:00:00Z' }
                fuels = @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
            }
            [pscustomobject]@{
                id = 'flamingo'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @('C:\ai'); grok_build = [pscustomobject]@{ remaining_pct = 85; period_end = '2026-09-27T00:00:00Z' }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
            }
            [pscustomobject]@{
                id = 'marchhare'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @('C:\ai'); grok_build = [pscustomobject]@{ remaining_pct = 4; period_end = '2026-09-26T00:00:00Z' }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build', 'copilot', 'grok-bot')
            }
            [pscustomobject]@{
                id = '2012'; kind = 'dumb'; gitEligible = $false; alive = $true; jobs = 0
                cwdRoots = @(); grok_build = [pscustomobject]@{ remaining_pct = $null }
                grok_bot = [pscustomobject]@{ remaining_pct = $null }
                fuels = @()
            }
        )
    }

    $def = Select-BobGitWorker -Capacity $fixture
    if ($def.wait) { throw "default picker waited: $($def.reason)" }
    if ($def.fuel -ne 'cursor-models') { throw "default fuel=$($def.fuel) expected cursor-models" }
    if ($def.machine -eq '2012') { throw 'default picker selected DUMB' }
    if (@('ionos', 'flamingo', 'marchhare') -notcontains $def.machine) { throw "default machine=$($def.machine)" }
    if ($def.machine -ne 'ionos') { throw "default machine=$($def.machine) expected ionos (highest grok-build remaining tie-break)" }

    $gb = Select-BobGitWorker -Capacity $fixture -Fuel grok-build
    if ($gb.wait) { throw "grok-build picker waited: $($gb.reason)" }
    if ($gb.fuel -ne 'grok-build') { throw "grok-build fuel=$($gb.fuel)" }
    if ($gb.machine -ne 'ionos') { throw "grok-build machine=$($gb.machine) expected ionos over flamingo over marchhare" }

    $dumb = Select-BobGitWorker -Capacity $fixture -Machine '2012' -Fuel grok-build
    if (-not $dumb.wait) { throw 'pin DUMB must wait' }

    $pin = Select-BobGitWorker -Capacity $fixture -Machine flamingo -Fuel grok-build
    if ($pin.wait) { throw "pin wait: $($pin.reason)" }
    if ($pin.machine -ne 'flamingo' -or $pin.fuel -ne 'grok-build') { throw "pin=$($pin.machine)/$($pin.fuel)" }

    $empty = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 0 }
        on_demand     = [pscustomobject]@{ remaining_pct = 10; enabled = $true }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'ionos'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @('C:\ai'); grok_build = [pscustomobject]@{ remaining_pct = 0 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build', 'grok-bot', 'on-demand')
            }
        )
    }
    $wait = Select-BobGitWorker -Capacity $empty
    if (-not $wait.wait) { throw 'all included empty must wait when AllowOnDemand is false' }
    $od = Select-BobGitWorker -Capacity $empty -AllowOnDemand
    if ($od.wait) { throw "on-demand should pick: $($od.reason)" }
    if ($od.fuel -ne 'on-demand') { throw "on-demand fuel=$($od.fuel)" }

    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $capFile = Join-Path $bridgeRoot 'capacity.json'
    $liveFix = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99 }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'testhost'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @($bridgeRoot)
                grok_build = [pscustomobject]@{ remaining_pct = 50 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build')
            }
        )
    }
    [IO.File]::WriteAllText($capFile, ($liveFix | ConvertTo-Json -Depth 8))
    $env:BOB_CAPACITY_FILE = $capFile
    $q = Start-BobBuild -Task git -Goal ping -Cwd (Join-Path $bridgeRoot 'cwd')
    if (-not $q.ok) { throw "git enqueue failed $($q | ConvertTo-Json -Compress)" }
    if ($q.wait) { throw "git enqueue waited: $($q.reason)" }
    if (-not $q.machine) { throw 'git job missing machine' }
    if ($q.fuel -ne 'cursor-models') { throw "git job fuel=$($q.fuel)" }
    $job = Get-BobBuild -JobId $q.jobId
    if ($job.task -ne 'git') { throw "job.task=$($job.task)" }
    if ($job.fuel -ne 'cursor-models') { throw "job.fuel=$($job.fuel)" }
    if (-not $job.machine) { throw 'job.machine empty' }
    if ($job.branch -notmatch '^work/') { throw "job.branch=$($job.branch)" }
    if ([string]$job.kind -ne 'build') { throw "git ping kind=$($job.kind)" }
    if ([string]$job.model -ne 'composer-2.5') { throw "cursor build model=$($job.model) expected composer-2.5" }
    $pinModel = Get-BobJobModel -Kind build -Fuel grok-build
    if ($pinModel -ne 'build0.1') { throw "grok build model=$pinModel expected build0.1" }
    $mrbC = Get-BobJobModel -Kind mrb -Fuel cursor-models
    if ($mrbC -ne 'grok-4.6') { throw "mrb cursor model=$mrbC" }
    $mrbG = Get-BobJobModel -Kind mrb -Fuel grok-build
    if ($mrbG -ne 'grok-4.6') { throw "mrb grok model=$mrbG" }
    $equiv = Resolve-BobGrokCliModel -Wanted 'build0.1'
    if ($equiv -eq 'build0.1') { throw 'Resolve-BobGrokCliModel must not pass unknown build0.1 to grok.exe -m' }
    if ($equiv -ne 'grok-4.5' -and $equiv -ne 'grok-4.6') { throw "build0.1 equivalent=$equiv" }
    $argvBuild = Start-BobWorker -Cwd (Join-Path $bridgeRoot 'cwd') -Prompt 'PONG' -Profile generic -Model 'build0.1' -WhatIfArgv -Force
    $argvText = ($argvBuild.argv -join ' ')
    if ($argvText -match '(^|\s)-m\s+build0\.1(\s|$)') { throw "argv still has -m build0.1: $argvText" }
    if ($argvText -notmatch '(^|\s)-m\s+grok-4\.(5|6)(\s|$)') { throw "argv missing grok catalog -m: $argvText" }

    $pinJob = Start-BobBuild -Task git -Machine testhost -Fuel grok-build -Goal ping -Cwd (Join-Path $bridgeRoot 'cwd')
    if ($pinJob.machine -ne 'testhost' -or $pinJob.fuel -ne 'grok-build') {
        throw "pin job $($pinJob.machine)/$($pinJob.fuel)"
    }

    $fix = Start-BobBuild -Task git -Fix -Goal ping -Cwd (Join-Path $bridgeRoot 'cwd')
    if ($fix.fuel -ne 'cursor-models') { throw "FIX picker fuel=$($fix.fuel) (must re-run, not stick on grok-build)" }

    $env:BOB_CAPACITY_FILE = $null
}

# --- BT0q kind mrb cursor packet (issue #10 fix 2) ---
Invoke-Case 'BT0q kind mrb packet' {
    param($bridgeRoot)
    $cfgPath = Join-Path $RepoRoot 'config\default.json'
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $expectedMrb = [string]$cfg.models.mrbCursor
    if (-not $expectedMrb) { throw 'config models.mrbCursor missing' }
    $cursor = Join-Path $RepoRoot 'tools\Start-BobCursor.ps1'
    $jobCwd = Join-Path $bridgeRoot 'mrb-cwd'
    New-Item -ItemType Directory -Force -Path $jobCwd | Out-Null
    $job = [pscustomobject]@{
        id     = [guid]::NewGuid().ToString()
        repo   = 'https://github.com/SimonBarnett/agentic_build'
        cwd    = $jobCwd
        goal   = 'Hostile MRB fixture'
        kind   = 'mrb'
        fuel   = 'cursor-models'
        task   = 'git'
        branch = 'work/mrb-fixture'
    }
    $r = & $cursor -Job $job
    if (-not $r.packetPath -or -not (Test-Path $r.packetPath)) { throw 'missing cursor handoff packet' }
    $packet = Get-Content $r.packetPath -Raw | ConvertFrom-Json
    if ([string]$packet.kind -ne 'mrb') { throw "packet.kind=$($packet.kind)" }
    if ([string]$packet.model -eq 'composer-2.5') { throw 'kind=mrb must not resolve composer-2.5' }
    if ([string]$packet.model -ne $expectedMrb) { throw "packet.model=$($packet.model) expected $expectedMrb" }
}

# Start-BobCursor must not Win32_Process-launch under Fake-Grok (BOB_GROK_EXE); fleet tick still completes.
Invoke-Case 'BT0q2 fleet mrb cursor suppress' {
    param($bridgeRoot)
    $cfg = Get-Content (Join-Path $RepoRoot 'config\default.json') -Raw | ConvertFrom-Json
    $expectedMrb = [string]$cfg.models.mrbCursor
    $cwd = Join-Path $bridgeRoot 'cwd'
    if ($env:BOB_GROK_EXE -notmatch '(?i)Fake-Grok') { throw 'BOB_GROK_EXE must be Fake-Grok for suppress seam' }
    $cursor = Join-Path $RepoRoot 'tools\Start-BobCursor.ps1'
    $direct = & $cursor -Repo 'https://github.com/SimonBarnett/agentic_build' -Cwd $cwd -Goal 'MRB suppress probe' -Kind mrb -Mrb 'https://github.com/SimonBarnett/agentic_build/issues/1'
    if ($direct.started) { throw 'Start-BobCursor must not launch cursor-agent when BOB_GROK_EXE is Fake-Grok' }
    if ($direct.pid) { throw "unexpected pid=$($direct.pid)" }
    if (-not $direct.packetPath -or -not (Test-Path $direct.packetPath)) { throw 'missing cursor handoff packet' }

    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $capFile = Join-Path $bridgeRoot 'capacity.json'
    $liveFix = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99 }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'testhost'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @($bridgeRoot)
                grok_build = [pscustomobject]@{ remaining_pct = 50 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build')
            }
        )
    }
    [IO.File]::WriteAllText($capFile, ($liveFix | ConvertTo-Json -Depth 8))
    $env:BOB_CAPACITY_FILE = $capFile
    $q = Start-BobBuild -Task git -Fuel cursor-models -Kind mrb -Goal 'MRB fleet fixture' -Cwd $cwd -Repo 'https://github.com/SimonBarnett/agentic_build'
    if (-not $q.ok) { throw "enqueue failed $($q | ConvertTo-Json -Compress)" }
    $watch = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
    & $watch -Once -RepoRoot $RepoRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Watch-BobJobs exit $LASTEXITCODE" }
    $done = Get-BobBuild -JobId $q.jobId
    if ($done.lane -ne 'outbox') { throw "lane=$($done.lane)" }
    if ($done.state -ne 'done') { throw "state=$($done.state)" }
    if ([string]$done.kind -ne 'mrb') { throw "job.kind=$($done.kind)" }
    if ([string]$done.model -ne $expectedMrb) { throw "job.model=$($done.model)" }
    if ([string]$done.fuel -ne 'cursor-models') { throw "job.fuel=$($done.fuel)" }
    if (-not $done.completion -or $done.completion.status -ne 'ok') { throw 'fleet cursor-models handoff must complete ok' }
}

# --- BT0r–BT0u Start-BobMrb / gh preflight (issue #13) ---
Invoke-Case 'BT0r mrb body-file' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $log = Join-Path $bridgeRoot 'fake-gh.jsonl'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $savedLog = $env:BOB_FAKE_GH_LOG
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $env:BOB_FAKE_GH_LOG = $log
    try {
        $body = @'
Verdict line with "double quotes", `backticks`, and $dollar.

```powershell
Write-Output "fenced"
```
'@
        $mrb = Join-Path $RepoRoot 'tools\Start-BobMrb.ps1'
        $r = & $mrb -Repo 'fixture/repo' -Title 'quote test' -Verdict FAIL -Body $body
        if (-not $r.ok) { throw 'Start-BobMrb failed' }
        if (-not (Test-Path $log)) { throw 'fake gh log missing' }
        $row = (Get-Content $log | Select-Object -Last 1) | ConvertFrom-Json
        if ([string]$row.body -ne $body) { throw 'body round-trip mismatch' }
        if ($row.argv -notmatch '--body-file') { throw 'gh must use --body-file' }
        if ($row.argv -match '--body\s') { throw 'gh must not use --body argv' }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
        $env:BOB_FAKE_GH_LOG = $savedLog
    }
}

Invoke-Case 'BT0s mrb label skip' {
    param($bridgeRoot)
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $log = Join-Path $bridgeRoot 'fake-gh-label.jsonl'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $savedLog = $env:BOB_FAKE_GH_LOG
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'label-fail'
    $env:BOB_FAKE_GH_LOG = $log
    $env:BOB_FAKE_GH_QUIET = '1'
    try {
        $mrb = Join-Path $RepoRoot 'tools\Start-BobMrb.ps1'
        $r = & $mrb -Repo 'fixture/repo' -Title 'label skip' -Verdict FAIL -Body 'plain body' 2>$null
        if (-not $r.ok) { throw 'issue create should succeed without labels' }
        if ($r.labelsApplied -contains 'mrb-fail') { throw 'mrb-fail should be dropped when create fails' }
        if ($r.labelsDropped -notcontains 'mrb-fail') { throw "labelsDropped=$($r.labelsDropped -join ',')" }
        $row = (Get-Content $log | Select-Object -Last 1) | ConvertFrom-Json
        if ([string]$row.body -notmatch 'Labels not applied') { throw 'body must note dropped labels' }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
        $env:BOB_FAKE_GH_LOG = $savedLog
        $env:BOB_FAKE_GH_QUIET = $null
    }
}

Invoke-Case 'BT0t gh preflight absent' {
    param($bridgeRoot)
    . (Join-Path $RepoRoot 'tools\Bob-Gh.ps1')
    $savedGh = $env:BOB_GH_EXE
    $env:BOB_GH_EXE = Join-Path $bridgeRoot 'no-such-gh.exe'
    try {
        $null = Test-BobGhIssuePosting -Repo 'fixture/repo'
        throw 'preflight should fail when gh absent'
    }
    catch {
        if ($_.Exception.Message -notmatch 'gh\.exe not found') { throw $_.Exception.Message }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
    }
}

Invoke-Case 'BT0u gh preflight dead token' {
    param($bridgeRoot)
    . (Join-Path $RepoRoot 'tools\Bob-Gh.ps1')
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $savedGh = $env:BOB_GH_EXE
    $savedMode = $env:BOB_FAKE_GH_MODE
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'dead'
    try {
        $null = Test-BobGhIssuePosting -Repo 'fixture/repo'
        throw 'preflight should fail on dead token'
    }
    catch {
        if ($_.Exception.Message -notmatch 'gh auth login') { throw $_.Exception.Message }
    }
    finally {
        $env:BOB_GH_EXE = $savedGh
        $env:BOB_FAKE_GH_MODE = $savedMode
    }
}

# --- BT0v Start-BobMrbHandoff (issue #16 fix 3) ---
function New-Bt0vCapacity {
    param([string]$BridgeRoot)
    $capFile = Join-Path $BridgeRoot 'capacity-mrb.json'
    $liveFix = [pscustomobject]@{
        cursor_models = [pscustomobject]@{ remaining_pct = 99 }
        on_demand     = [pscustomobject]@{ remaining_pct = 0; enabled = $false }
        copilot       = [pscustomobject]@{ available = $false }
        machines      = @(
            [pscustomobject]@{
                id = 'testhost'; kind = 'windows'; gitEligible = $true; alive = $true; jobs = 0
                cwdRoots = @($BridgeRoot)
                grok_build = [pscustomobject]@{ remaining_pct = 50 }
                grok_bot = [pscustomobject]@{ remaining_pct = 0 }
                fuels = @('cursor-models', 'grok-build')
            }
        )
    }
    [IO.File]::WriteAllText($capFile, ($liveFix | ConvertTo-Json -Depth 8))
    return $capFile
}

Invoke-Case 'BT0v1 mrb handoff remote refuse' {
    param($bridgeRoot)
    $handoff = Join-Path $RepoRoot 'tools\Start-BobMrbHandoff.ps1'
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $pick = [pscustomobject]@{ wait = $false; machine = 'flamingo'; fuel = 'grok-build'; reason = $null }
    try {
        & $handoff -Issue 16 -Repo 'fixture/repo' -Fuel grok-build -TestSkipCursor -TestGitWorkerResult $pick -Cwd (Join-Path $bridgeRoot 'cwd')
        throw 'expected remote worker refuse'
    }
    catch {
        if ($_.Exception.Message -notmatch 'cannot verify worker') { throw $_.Exception.Message }
    }
}

Invoke-Case 'BT0v2 mrb handoff identity refuse' {
    param($bridgeRoot)
    $handoff = Join-Path $RepoRoot 'tools\Start-BobMrbHandoff.ps1'
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $pick = [pscustomobject]@{ wait = $false; machine = 'testhost'; fuel = 'grok-build'; reason = $null }
    try {
        & $handoff -Issue 16 -Repo 'fixture/repo' -Fuel grok-build -TestSkipCursor -TestGitWorkerResult $pick -Cwd (Join-Path $bridgeRoot 'cwd')
        throw 'expected identity refuse'
    }
    catch {
        if ($_.Exception.Message -notmatch 'cannot resolve this machine identity') { throw $_.Exception.Message }
    }
}

Invoke-Case 'BT0v3 mrb handoff local packet' {
    param($bridgeRoot)
    $cfg = Get-Content (Join-Path $RepoRoot 'config\default.json') -Raw | ConvertFrom-Json
    $expectedMrb = [string]$cfg.models.mrbGrok
    $handoff = Join-Path $RepoRoot 'tools\Start-BobMrbHandoff.ps1'
    $fakeGh = Join-Path $RepoRoot 'tests\fixtures\Fake-Gh.ps1'
    $ghLog = Join-Path $bridgeRoot 'handoff-gh.jsonl'
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $env:BOB_CAPACITY_FILE = New-Bt0vCapacity -BridgeRoot $bridgeRoot
    $env:BOB_GH_EXE = $fakeGh
    $env:BOB_FAKE_GH_MODE = 'ok'
    $env:BOB_FAKE_GH_LOG = $ghLog
    $pick = [pscustomobject]@{ wait = $false; machine = 'testhost'; fuel = 'grok-build'; reason = $null }
    $r = & $handoff -Issue 16 -Repo 'fixture/repo' -Fuel grok-build -TestSkipCursor -TestGitWorkerResult $pick -Cwd $cwd
    if (-not $r.ok) { throw "handoff failed $($r | ConvertTo-Json -Compress)" }
    if ($r.handed -ne 'grok-build') { throw "handed=$($r.handed)" }
    if (-not (Test-Path $r.path)) { throw 'missing inbox packet' }
    if (-not (Test-Path $ghLog)) { throw 'gh preflight log missing' }
    $ghRows = @(Get-Content $ghLog | ForEach-Object { $_ | ConvertFrom-Json })
    if (-not ($ghRows | Where-Object { $_.command -eq 'auth status' })) { throw 'preflight must log auth status' }
    $repoProbe = @($ghRows | Where-Object { $_.command -eq 'repo view' })
    if ($repoProbe.Count -lt 1) { throw 'preflight must log repo view' }
    if (($repoProbe[0].argv -join ' ') -notmatch 'fixture/repo') { throw 'repo view must target fixture/repo' }
    $packet = Get-Content $r.path -Raw | ConvertFrom-Json
    $mrbUrl = 'https://github.com/fixture/repo/issues/16'
    if ([string]$packet.mrb -ne $mrbUrl) { throw "packet.mrb=$($packet.mrb)" }
    if ([string]$packet.kind -ne 'mrb') { throw "packet.kind=$($packet.kind)" }
    if ([string]$packet.model -ne $expectedMrb) { throw "packet.model=$($packet.model) expected $expectedMrb" }
}

Invoke-Case 'BT0w mrb handoff skip cursor fuel refuse' {
    param($bridgeRoot)
    $handoff = Join-Path $RepoRoot 'tools\Start-BobMrbHandoff.ps1'
    $pick = [pscustomobject]@{ wait = $false; machine = 'testhost'; fuel = 'grok-build'; reason = $null }
    try {
        & $handoff -Issue 16 -Repo 'fixture/repo' -Fuel cursor-models -TestSkipCursor -TestGitWorkerResult $pick -Cwd (Join-Path $bridgeRoot 'cwd')
        throw 'cursor-models + TestSkipCursor must refuse'
    }
    catch {
        if ($_.Exception.Message -notmatch 'TestSkipCursor') { throw $_.Exception.Message }
    }
}

# --- BT0x fuel/model compatibility gate (issue #17) ---
Invoke-Case 'BT0x1 fuel model enqueue refuse' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $bad = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'PONG' -Profile generic -Fuel grok-build -Model 'composer-2.5'
    if ($bad.ok) { throw 'mismatched fuel/model must not enqueue' }
    if ([string]$bad.error -ne 'fuel_model_mismatch') { throw "error=$($bad.error)" }
    if ([string]$bad.reason -notmatch 'fuel_model_mismatch') { throw "reason=$($bad.reason)" }
    $inbox = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    if (Test-Path $inbox) {
        $left = @(Get-ChildItem $inbox -Filter '*.json' -ErrorAction SilentlyContinue).Count
        if ($left -gt 0) { throw "inbox still has $left packet(s) after refuse" }
    }
}

Invoke-Case 'BT0x2 fuel model tick refuse' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $jobId = [guid]::NewGuid().ToString()
    $packet = [pscustomobject]@{
        id            = $jobId
        from          = 'test'
        goal          = 'PONG'
        machine       = 'testhost'
        cwd           = $cwd
        profile       = 'generic'
        createdAt     = [DateTime]::UtcNow.ToString('o')
        fuel          = 'grok-build'
        model         = 'claude-opus-5-thinking-high'
        task          = 'fleet'
        kind          = 'build'
    }
    $inDir = Join-Path $bridgeRoot 'fleet\inbox\testhost'
    New-Item -ItemType Directory -Force -Path $inDir | Out-Null
    $inPath = Join-Path $inDir ($jobId + '.json')
    [IO.File]::WriteAllText($inPath, ($packet | ConvertTo-Json -Depth 8))
    $sessDir = Join-Path $bridgeRoot 'fake-grok-home\sessions'
    $before = 0
    if (Test-Path $sessDir) { $before = @(Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    Invoke-BobFleetTick | Out-Null
    $after = 0
    if (Test-Path $sessDir) { $after = @(Get-ChildItem $sessDir -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    if ($after -ne $before) { throw "Fake-Grok sessions grew $before -> $after (grok.exe must not start)" }
    $done = Get-BobBuild -JobId $jobId
    if ($done.lane -ne 'outbox') { throw "lane=$($done.lane)" }
    if ($done.state -ne 'failed') { throw "state=$($done.state)" }
    if (-not $done.completion -or $done.completion.status -ne 'failed') { throw 'completion not failed' }
    if ([string]$done.completion.summary -notmatch 'fuel_model_mismatch') { throw "summary=$($done.completion.summary)" }
}

Invoke-Case 'BT0x3 fuel model matched enqueue' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $cfg = Get-Content (Join-Path $RepoRoot 'config\default.json') -Raw | ConvertFrom-Json
    if (-not $cfg.fuelModelFamilies) { throw 'config fuelModelFamilies missing' }
    $pairs = [ordered]@{
        'cursor-models' = [string]$cfg.models.buildCursor
        'grok-build'    = [string]$cfg.models.buildGrok
        'grok-bot'      = 'grok-4.6'
        'on-demand'     = [string]$cfg.models.buildGrokFallback
        'copilot'       = $null
    }
    foreach ($fuel in $pairs.Keys) {
        $model = $pairs[$fuel]
        $args = @{
            Machine = 'testhost'
            Cwd     = $cwd
            Goal    = 'PONG'
            Profile = 'generic'
            Fuel    = $fuel
        }
        if ($model) { $args['Model'] = $model }
        $q = Start-BobBuild @args
        if (-not $q.ok) { throw "fuel=$fuel model=$model enqueue failed $($q | ConvertTo-Json -Compress)" }
        if ([string]$q.fuel -ne $fuel) { throw "fuel=$fuel got $($q.fuel)" }
        $job = Get-BobBuild -JobId $q.jobId
        if ($job.lane -ne 'inbox') { throw "fuel=$fuel lane=$($job.lane)" }
    }
    $src = Get-Content (Join-Path $RepoRoot 'src\Public\Get-BobCapacity.ps1') -Raw
    if ($src -match 'fuel_model_mismatch fuel=grok-build model=composer') { throw 'hard-coded mismatch string in Get-BobCapacity' }
    if ($src -notmatch 'Get-BobFuelModelConfig') { throw 'mapping must use Get-BobFuelModelConfig' }
}

Invoke-Case 'BT0x4 fuel model matched tick' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot
    $env:BOB_MACHINE_ID = 'testhost'
    $q = Start-BobBuild -Machine testhost -Cwd $cwd -Goal 'PONG' -Profile generic -Fuel grok-build -Model 'build0.1'
    if (-not $q.ok) { throw "enqueue failed $($q | ConvertTo-Json -Compress)" }
    $watch = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
    & $watch -Once -RepoRoot $RepoRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Watch-BobJobs exit $LASTEXITCODE" }
    $done = Get-BobBuild -JobId $q.jobId
    if ($done.lane -ne 'outbox') { throw "lane=$($done.lane)" }
    if ($done.state -ne 'done') { throw "state=$($done.state)" }
    if (-not $done.completion -or $done.completion.status -ne 'ok') { throw 'matched grok-build tick must complete ok' }
}

# --- BT0loop Start-BobBuildLoop (issue mrb-loop-automation) ---
. (Join-Path $RepoRoot 'tools\Bob-BuildLoop.ps1')

Invoke-Case 'BT0loop1 required-fixes parse' {
    param($bridgeRoot)
    $body = @'
## Verdict
FAIL

## Required fixes
- Gate A still red
- Do not invent API Foo

## Nits
- typo
'@
    $fixes = Get-BobMrbRequiredFixes $body
    if ($fixes -notmatch 'Gate A still red') { throw "fixes missing gate: $fixes" }
    if ($fixes -notmatch 'Do not invent API Foo') { throw 'fixes missing API line' }
    if ($fixes -match 'typo') { throw 'nits leaked into required fixes' }
    if ($fixes -match 'PASS-UAT') { throw 'UAT must not appear' }
}

Invoke-Case 'BT0loop2 backlink payload' {
    param($bridgeRoot)
    $payload = New-BobMrbBacklinkComment -Url 'https://github.com/fixture/repo/issues/9' -Sha 'abc1234dead'
    if ($payload -notmatch 'https://github.com/fixture/repo/issues/9') { throw "payload missing url: $payload" }
    if ($payload -notmatch 'abc1234dead') { throw "payload missing sha: $payload" }
    if ($payload -notmatch '^Next board:') { throw "payload prefix: $payload" }
    $pr = New-BobFixPrComment -Url 'https://github.com/fixture/repo/pull/4' -Sha 'abc1234dead'
    if ($pr -notmatch 'FIX PR:') { throw "fix pr payload: $pr" }
}

Invoke-Case 'BT0loop3 state file round-trip' {
    param($bridgeRoot)
    $path = Get-BobBuildLoopStatePath -Repo 'fixture/repo' -Issue 19
    $root = [IO.Path]::GetFullPath($env:BOB_BRIDGE_HOME)
    if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "state path not under test bridge: $path (root $root)" }
    $liveBridge = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.grok\bob-bridge'))
    if ($path.StartsWith($liveBridge, [StringComparison]::OrdinalIgnoreCase)) { throw 'must not use live bob-bridge' }
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'deadbeefcafebabe' -Cwd (Join-Path $bridgeRoot 'cwd')
    $row = [pscustomobject]@{ sha = 'deadbeefcafebabe'; pr = 'https://github.com/fixture/repo/pull/2'; mrb = 'https://github.com/fixture/repo/issues/8'; verdict = 'FAIL'; issue = 8 }
    $state = Add-BobBuildLoopPass -State $state -Pass $row
    Write-BobBuildLoopState -Path $path -State $state
    $board = Get-BobMrbBoard -Repo 'fixture/repo' -Issue 19 -Path $path
    if ([int]$board.issue -ne 19) { throw "issue=$($board.issue)" }
    if ([string]$board.sha -ne 'deadbeefcafebabe') { throw "sha=$($board.sha)" }
    if ([string]$board.verdict -ne 'FAIL') { throw "verdict=$($board.verdict)" }
    if (@($board.passes).Count -ne 1) { throw 'expected one pass row' }
}

Invoke-Case 'BT0loop4 wait_pr retry on dead job' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_pr'
    $state.jobAttempts = 1
    $state.currentPid = 4242
    $state.currentKind = 'build'
    $world = [pscustomobject]@{
        Job          = [pscustomobject]@{ pid = 4242; startError = $null; started = $true }
        ProcessAlive = $false
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
    if ($d.kind -ne 'build') { throw "kind=$($d.kind)" }
}

Invoke-Case 'BT0loop4b wait_pr retry on start refused (state startError)' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_pr'
    $state.jobAttempts = 1
    $state.currentKind = 'build'
    $state.startError = 'enqueue refused'
    $state.currentPid = $null
    $state.currentJobId = 'job-refused'
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
    if ($d.kind -ne 'build') { throw "kind=$($d.kind)" }
}

Invoke-Case 'BT0loop4c wait_mrb retry on refused-start world' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_mrb'
    $state.jobAttempts = 1
    $state.currentKind = 'mrb'
    $state.currentPid = $null
    $world = [pscustomobject]@{
        Job          = [pscustomobject]@{ startError = 'MRB handoff refused'; started = $false; pid = $null }
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
    if ($d.kind -ne 'mrb') { throw "kind=$($d.kind)" }
}

Invoke-Case 'BT0loop4c2 wait_mrb retry on state startError no job' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_mrb'
    $state.jobAttempts = 1
    $state.currentKind = 'mrb'
    $state.startError = 'MRB handoff enqueue failed (enqueue refused)'
    $state.currentPid = $null
    $state.currentJobId = $null
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
    if ($d.kind -ne 'mrb') { throw "kind=$($d.kind)" }
}

Invoke-Case 'BT0loop4d2 wait_pr cursor-models completion not ok no pid' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3 -Fuel 'cursor-models'
    $state.phase = 'wait_pr'
    $state.jobAttempts = 1
    $state.currentKind = 'build'
    $state.currentPid = $null
    $state.currentJobId = 'cursor-done-bad'
    $world = [pscustomobject]@{
        Job          = [pscustomobject]@{ id = 'cursor-done-bad'; fuel = 'cursor-models'; completionStatus = 'error'; pid = $null }
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
}

Invoke-Case 'BT0loop4d wait_pr cursor-models no pid no job' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3 -Fuel 'cursor-models'
    $state.phase = 'wait_pr'
    $state.jobAttempts = 1
    $state.currentKind = 'build'
    $state.currentPid = $null
    $state.currentJobId = 'cursor-miss'
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'retry_job') { throw "action=$($d.action)" }
}

Invoke-Case 'BT0loop4e retry_job FIX goal keeps required fixes from state' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd')
    $state.lastMrb = 'https://github.com/fixture/repo/issues/8'
    $state.requiredFixes = '- Restore gate A'
    $fixes = Resolve-BobBuildLoopRequiredFixes -State $state -World ([pscustomobject]@{ Issues = @() })
    if ($fixes -notmatch 'Restore gate A') { throw "fixes=$fixes" }
    $goal = New-BobFixGoal -MrbUrl ([string]$state.lastMrb) -Fixes $fixes
    if ($goal -notmatch 'Restore gate A') { throw "goal missing fixes" }
}

Invoke-Case 'BT0loop5 fail starts fix with required fixes' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
    $state.phase = 'wait_mrb'
    $state.currentKind = 'mrb'
    $body = @"
## Verdict
FAIL

## Required fixes
- Restore gate A
"@
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $true
        Prs          = @()
        Issues       = @(
            [pscustomobject]@{
                number = 8
                title  = 'MRB FAIL: slug abc1234deadbeef'
                url    = 'https://github.com/fixture/repo/issues/8'
                body   = $body
            }
        )
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'start_fix') { throw "action=$($d.action)" }
    if ($d.goal -notmatch 'Restore gate A') { throw "goal missing fixes: $($d.goal)" }
    if ($d.goal -match 'PASS-UAT') { throw 'FIX goal must not stamp UAT' }
    if ($d.pass.verdict -ne 'FAIL') { throw "pass verdict=$($d.pass.verdict)" }
}

Invoke-Case 'BT0loop6 pass-nits terminal' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd (Join-Path $bridgeRoot 'cwd')
    $state.phase = 'wait_mrb'
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $true
        Prs          = @()
        Issues       = @(
            [pscustomobject]@{
                number = 9
                title  = 'MRB PASS-nits: slug abc1234deadbeef'
                url    = 'https://github.com/fixture/repo/issues/9'
                body   = "## Verdict`nPASS-nits"
            }
        )
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'pass') { throw "action=$($d.action)" }
    if ($d.stdout -notmatch '^DONE: MRB PASS-nits') { throw "stdout=$($d.stdout)" }
    if ($d.stdout -match 'PASS-UAT') { throw 'driver must not stamp UAT' }
    if ($d.patch.phase -ne 'pass') { throw "phase=$($d.patch.phase)" }
}

Invoke-Case 'BT0loop7 retries exhausted' {
    param($bridgeRoot)
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 19 -Cwd (Join-Path $bridgeRoot 'cwd') -MaxJobRetries 3
    $state.phase = 'wait_pr'
    $state.jobAttempts = 3
    $state.currentPid = 99
    $world = [pscustomobject]@{
        Job          = [pscustomobject]@{ pid = 99 }
        ProcessAlive = $false
        Prs          = @()
        Issues       = @()
    }
    $d = Get-BobBuildLoopDecision -State $state -World $world
    if ($d.action -ne 'fail') { throw "action=$($d.action)" }
    if ($d.stdout -notmatch '^FAILED:') { throw "stdout=$($d.stdout)" }
}

Invoke-Case 'BT0loop8 loop once testworld no live gh' {
    param($bridgeRoot)
    $env:BOB_GH_EXE = Join-Path $bridgeRoot 'no-such-gh.exe'
    $cwd = Join-Path $bridgeRoot 'cwd'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $loop = Join-Path $RepoRoot 'tools\Start-BobBuildLoop.ps1'
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $starts = New-Object System.Collections.Generic.List[string]
    $r = & $loop -Issue 19 -Repo 'fixture/repo' -Cwd $cwd -Once -TestWorld $world -TestStartBuild {
        param($st, $goal)
        $starts.Add('build')
        [pscustomobject]@{ ok = $true; started = $true; jobId = 'job-build'; pid = 1; fuel = 'cursor-models'; branch = 'work/job-build' }
    }
    if ($r.action -ne 'start_build') { throw "action=$($r.action)" }
    if ($r.phase -ne 'wait_pr') { throw "phase=$($r.phase)" }
    $root = [IO.Path]::GetFullPath($env:BOB_BRIDGE_HOME)
    if (-not $r.statePath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "state escaped test root: $($r.statePath) (root $root)" }
    $liveBridge = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.grok\bob-bridge'))
    if ($r.statePath.StartsWith($liveBridge, [StringComparison]::OrdinalIgnoreCase)) { throw 'wrote live bob-bridge' }
    $board = Get-BobMrbBoard -Repo 'fixture/repo' -Issue 19 -Path $r.statePath
    if ([int]$board.issue -ne 19) { throw 'board issue missing' }
    if ($starts.Count -lt 1) { throw 'TestStartBuild not called' }
}

Invoke-Case 'BT0loop9 mrb handoff refuse does not abort driver' {
    param($bridgeRoot)
    $env:BOB_GH_EXE = Join-Path $bridgeRoot 'no-such-gh.exe'
    $cwd = Join-Path $bridgeRoot 'cwd'
    New-Item -ItemType Directory -Force -Path $cwd | Out-Null
    $loop = Join-Path $RepoRoot 'tools\Start-BobBuildLoop.ps1'
    $path = Get-BobBuildLoopStatePath -Repo 'fixture/repo' -Issue 44
    $state = New-BobBuildLoopState -Repo 'fixture/repo' -Issue 44 -Sha 'abc1234deadbeef' -Pr 'https://github.com/fixture/repo/pull/2' -Cwd $cwd -MaxJobRetries 3
    $state.phase = 'wait_mrb'
    $state.currentKind = 'mrb'
    Write-BobBuildLoopState -Path $path -State $state
    $world = [pscustomobject]@{
        Job          = $null
        ProcessAlive = $null
        Prs          = @()
        Issues       = @()
    }
    $mrbCalls = New-Object System.Collections.Generic.List[string]
    $r = & $loop -Issue 44 -Repo 'fixture/repo' -Cwd $cwd -Once -TestWorld $world -StatePath $path -TestStartMrb {
        param($st)
        [void]$mrbCalls.Add('mrb')
        [pscustomobject]@{ ok = $false; started = $false; jobId = $null; pid = $null; fuel = 'cursor-models'; startError = 'MRB handoff enqueue failed (enqueue refused)' }
    }
    if ($r.action -ne 'retry_job') { throw "expected retry_job after refused mrb start, got $($r.action)" }
    if (-not [string]$r.state.startError) { throw 'startError must persist on state' }
    if ($mrbCalls.Count -lt 1) { throw 'TestStartMrb not invoked on retry_job' }
}

Write-Host ''
Write-Host "BT0 summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
