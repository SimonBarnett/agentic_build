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
    }
}

# --- BT0 skills ---
Invoke-Case 'BT0 skills' {
    foreach ($n in @('grok-build-fleet', 'unstick-grok-bot', 'bob-build-loop', 'bob-spec-intake', 'bob-build-dispatch', 'bob-hostile-mrb', 'box-usage', 'harvest-agent-skills', 'bob-fleet-monitor', 'bob-fleet-tray')) {
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
}

# --- BT0l tray hover (NC-01..NC-05) ---
Invoke-Case 'BT0l tray hover' {
    param($bridgeRoot)
    $cwd = Join-Path $bridgeRoot 'cwd'
    $null = Register-BobMachine -Id testhost -CwdRoots $bridgeRoot

    $h = Get-BobTrayHover
    if ($null -ne $h.remaining_pct) { throw "idle remaining_pct=$($h.remaining_pct) expected null" }
    if ([string]$h.title -ne 'Bob (testhost)') { throw "title=$($h.title)" }
    if ([string]$h.scope -ne 'this-machine') { throw "scope=$($h.scope)" }
    if ([string]$h.machine -ne 'testhost') { throw "machine=$($h.machine)" }
    if ([string]$h.body -match '(?i)fleet') { throw "idle body still says fleet: $($h.body)" }
    if ([string]$h.body -notmatch 'no jobs on this machine') { throw "idle body missing this-machine copy: $($h.body)" }
    if ([string]$h.remaining_kind -ne 'context') { throw "kind=$($h.remaining_kind)" }

    $paint = Get-BobTrayBarPaint -RemainingPct $h.remaining_pct -BarWidth 392
    if ($paint.known) { throw 'null remaining must be unknown' }
    if ($paint.show_track) { throw 'null remaining must hide track' }
    if ($paint.show_fill) { throw 'null remaining must not fill' }
    if ($null -ne $paint.fill_width) { throw "null remaining fill_width=$($paint.fill_width) must not be numeric (would look depleted)" }
    if ($paint.pulse) { throw 'must not pulse when remaining unknown' }
    if ($paint.caption -notmatch 'n/a') { throw "caption=$($paint.caption)" }

    $zero = Get-BobTrayBarPaint -RemainingPct 0 -BarWidth 392
    if (-not $zero.known) { throw '0% from usage must be known' }
    if (-not $zero.show_track) { throw '0% must show empty track' }
    if ($zero.show_fill) { throw '0% must not draw a fill' }
    if ($zero.fill_width -ne 0) { throw "0% fill_width=$($zero.fill_width)" }
    if (-not $zero.pulse) { throw '0% must pulse context' }

    $mid = Get-BobTrayBarPaint -RemainingPct 50 -BarWidth 392
    if ($mid.fill_width -le 0) { throw "50% fill_width=$($mid.fill_width)" }
    if ($mid.pulse) { throw '50% must not pulse' }

    $low = Get-BobTrayBarPaint -RemainingPct 5 -BarWidth 392
    if (-not $low.pulse) { throw '5% must pulse' }

    $emptyStr = Get-BobTrayBarPaint -RemainingPct '' -BarWidth 392
    if ($null -ne $emptyStr.fill_width) { throw 'empty-string remaining must not fill' }
    if ($emptyStr.pulse) { throw 'empty-string remaining must not pulse' }

    $akNone = Get-BobTrayAlertKind -Alerts @() -RemainingPct $null
    if ($akNone -ne 'none') { throw "alert=$akNone" }
    $akCtx = Get-BobTrayAlertKind -Alerts @() -RemainingPct 5
    if ($akCtx -ne 'context') { throw "alert=$akCtx" }
    $akWatch = Get-BobTrayAlertKind -Alerts @('ACTION_REQUIRED: watcher_down watcher_up=False') -RemainingPct 5
    if ($akWatch -ne 'watcher') { throw "alert=$akWatch" }
    $akStall = Get-BobTrayAlertKind -Alerts @('ACTION_REQUIRED: agent_stall Bob idle_sec=900') -RemainingPct $null
    if ($akStall -ne 'stall') { throw "alert=$akStall" }

    $jobId = '9f96bc0e-1111-2222-3333-444455556666'
    $runDir = Join-Path $bridgeRoot 'fleet\running\testhost'
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $job = [pscustomobject]@{
        id        = $jobId
        machine   = 'testhost'
        cwd       = $cwd
        claimedAt = [DateTime]::UtcNow.ToString('o')
        state     = 'running'
    }
    [IO.File]::WriteAllText((Join-Path $runDir ($jobId + '.json')), ($job | ConvertTo-Json -Depth 6))

    $h2 = Get-BobTrayHover
    if ($h2.job_count -ne 1) { throw "job_count=$($h2.job_count)" }
    if ([string]$h2.body -match '(?i)fleet') { throw "running body says fleet: $($h2.body)" }
    if ([string]$h2.body -notmatch '9f96bc0e') { throw "hover body missing id8: $($h2.body)" }
    if ($null -ne $h2.remaining_pct) { throw 'running without usage.json must keep remaining_pct null' }
    $row = @($h2.jobs)[0]
    $line = '{0}   {1}   {2}   {3}   {4}' -f $row.machine, $row.id8, $row.repo, $row.duration, $row.state
    if ($line -notmatch '9f96bc0e') { throw "card line missing id8: $line" }
    $paint2 = Get-BobTrayBarPaint -RemainingPct $h2.remaining_pct -BarWidth 392
    if ($null -ne $paint2.fill_width) { throw 'running without usage.json must not set fill_width' }

    $traySrc = Get-Content (Join-Path $RepoRoot 'tools\Watch-BobTray.ps1') -Raw
    foreach ($bad in @('Bob fleet', 'No fleet jobs running', 'no fleet jobs running')) {
        if ($traySrc.Contains($bad)) { throw "Watch-BobTray still contains fleet UI copy: $bad" }
    }
    if ($traySrc -notmatch '\$_\.id8') { throw 'Watch-BobTray card line missing id8' }
    if ($traySrc -notmatch 'Get-BobTrayBarPaint') { throw 'Watch-BobTray paint path does not use Get-BobTrayBarPaint' }
    if ($traySrc -notmatch 'show_track') { throw 'Watch-BobTray paint path does not gate on show_track' }

    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch '(?i)weekly') { throw 'bob-fleet-tray skill must document weekly vs context' }
    if ($skillTray -notmatch 'alert:') { throw 'bob-fleet-tray skill must document badge sources' }
    $skillBox = Get-Content (Join-Path $RepoRoot '.grok\skills\box-usage\SKILL.md') -Raw
    if ($skillBox -notmatch '(?i)weekly') { throw 'box-usage skill must document weekly vs context' }
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
    if ($traySrc -notmatch '(?s)if \(-not \$tip\.Visible\).{0,800}Get-BobTrayTipPlacement') {
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
    if ($traySrc -notmatch "Show-BobTrayCard -Reason 'hover'") { throw 'MouseMove must show card on hover' }
    if ($traySrc -notmatch "Show-BobTrayCard -Reason 'click'") { throw 'left-click must show card (overflow fallback)' }
    if ($traySrc -notmatch "Show-BobTrayCard -Reason 'probe'") { throw 'icon-rect probe must show card when cursor is over icon' }
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
    if ($traySrc -notmatch '(?s)if \(-not \$tip\.Visible\).{0,800}Get-BobTrayTipPlacement') {
        throw 'Get-BobTrayTipPlacement must run only when tip is not visible'
    }
    if ($traySrc -match '\$x = \$pt\.X - \$tip\.Width') { throw 'Watch-BobTray still derives Location from cursor X every move' }
    foreach ($bad in @('Bob fleet', 'No fleet jobs running', 'no fleet jobs running')) {
        if ($traySrc.Contains($bad)) { throw "Watch-BobTray still contains fleet UI copy: $bad" }
    }

    $skillTray = Get-Content (Join-Path $RepoRoot '.grok\skills\bob-fleet-tray\SKILL.md') -Raw
    if ($skillTray -notmatch '(?i)left-click') { throw 'bob-fleet-tray skill must document left-click card show' }
    if ($skillTray -notmatch 'ShowParkedAt') { throw 'bob-fleet-tray skill must document ShowParkedAt' }
    if ($skillTray -notmatch '(?i)watch_bob_tray\.log') { throw 'bob-fleet-tray skill must name the tray log' }

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
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;
    }
    public class TipForm : Form {
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
        public bool ShowParkedAt(int x, int y) {
            this.Left = x; this.Top = y;
            if (!this.IsHandleCreated) this.CreateHandle();
            Shell.SetWindowPos(this.Handle, Shell.HWND_TOPMOST, x, y, this.Width, this.Height,
                Shell.SWP_NOACTIVATE | Shell.SWP_SHOWWINDOW);
            this.Visible = true;
            if (!this.Visible) {
                Shell.ShowWindow(this.Handle, Shell.SW_SHOWNA);
                this.Visible = true;
            }
            return this.Visible;
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
        }
        finally {
            try { $f.Hide() } catch { }
            $f.Dispose()
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

Write-Host ''
Write-Host "BT0 summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
