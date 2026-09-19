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
    foreach ($n in @('grok-build-fleet', 'unstick-grok-bot')) {
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

Write-Host ''
Write-Host "BT0 summary: $($script:Pass) pass / $($script:Fail) fail"
if ($script:Fail -gt 0) { exit 1 }
exit 0
