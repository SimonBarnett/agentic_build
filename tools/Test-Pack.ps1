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
        $env:BOB_SKIP_LIVE_GROK = $null
        $env:BOB_CAPACITY_FILE = $null
    }
}

# --- BT0 skills ---
Invoke-Case 'BT0 skills' {
    foreach ($n in @('grok-build-fleet', 'unstick-grok-bot', 'bob-build-loop', 'bob-spec-intake', 'bob-build-dispatch', 'bob-hostile-mrb', 'box-usage', 'harvest-agent-skills', 'bob-fleet-monitor', 'bob-fleet-tray', 'start-bob-copilot', 'start-bob-cursor', 'bob-irc', 'reinstall-agentic-build-skills', 'setup-remote-grok-bot')) {
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
    if ([string]$cfg.nicks.flamingo -ne 'bob-flamingo') { throw 'flamingo nick' }

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
    if ($watchBv -match 'grok\.exe') { throw 'Watch-Bobiverse must not invoke grok.exe' }
    if ($watchBv -match 'Start-BobWorker|Invoke-BobFleetTick|Send-BobPrompt') { throw 'Watch-Bobiverse must not start a Grok reasoning job' }
    if ($watchBv -notmatch 'Write-BobIrcStatus') { throw 'Watch-Bobiverse must POINT via Write-BobIrcStatus' }
    if ($watchBv -notmatch 'Import-BobIrcPeerTranscript') { throw 'Watch-Bobiverse must poll peer POINT lines' }
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

    $pinJob = Start-BobBuild -Task git -Machine testhost -Fuel grok-build -Goal ping -Cwd (Join-Path $bridgeRoot 'cwd')
    if ($pinJob.machine -ne 'testhost' -or $pinJob.fuel -ne 'grok-build') {
        throw "pin job $($pinJob.machine)/$($pinJob.fuel)"
    }

    $fix = Start-BobBuild -Task git -Fix -Goal ping -Cwd (Join-Path $bridgeRoot 'cwd')
    if ($fix.fuel -ne 'cursor-models') { throw "FIX picker fuel=$($fix.fuel) (must re-run, not stick on grok-build)" }

    $env:BOB_CAPACITY_FILE = $null
}

Write-Host ''
Write-Host "BT0 summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
