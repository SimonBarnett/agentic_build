# Fake grok.exe for BT0*. Honours BOB_BRIDGE_HOME. Never touches real ~/.grok/sessions.
$ErrorActionPreference = 'Continue'

function Get-FakeHome {
    if ($env:BOB_BRIDGE_HOME -and $env:BOB_BRIDGE_HOME.Trim()) {
        return Join-Path $env:BOB_BRIDGE_HOME 'fake-grok-home'
    }
    return Join-Path $env:TEMP 'bob-fake-grok-home'
}

function Get-SessionDir {
    $d = Join-Path (Get-FakeHome) 'sessions'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}

function Save-Session {
    param([string]$Id, [string]$Prompt)
    $path = Join-Path (Get-SessionDir) ($Id + '.json')
    $obj = @{ id = $Id; prompt = $Prompt; updatedAt = [DateTime]::UtcNow.ToString('o') }
    [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Compress))
}

function Test-Session {
    param([string]$Id)
    Test-Path (Join-Path (Get-SessionDir) ($Id + '.json'))
}

function Write-JsonOut {
    param($Object, [int]$ExitCode = 0)
    [Console]::Out.WriteLine(($Object | ConvertTo-Json -Compress))
    exit $ExitCode
}

$argv = @($args)
$prompt = $null
$sessionId = $null
$resumeId = $null
$cwd = $null
$persistent = $false
$i = 0
$positional = New-Object System.Collections.Generic.List[string]

function Take-Value {
    param([int]$Index)
    if ($Index -lt $argv.Count) { return [string]$argv[$Index] }
    return $null
}

while ($i -lt $argv.Count) {
    $a = [string]$argv[$i]
    $i++
    switch ($a) {
        '-p' { $prompt = Take-Value $i; $i++; continue }
        '--single' { $prompt = Take-Value $i; $i++; continue }
        '-s' { $sessionId = Take-Value $i; $i++; continue }
        '--session-id' { $sessionId = Take-Value $i; $i++; continue }
        '-r' {
            $n = Take-Value $i
            if ($n -and $n -notmatch '^-') { $resumeId = $n; $i++ }
            continue
        }
        '--resume' {
            $n = Take-Value $i
            if ($n -and $n -notmatch '^-') { $resumeId = $n; $i++ }
            continue
        }
        '--cwd' { $cwd = Take-Value $i; $i++; continue }
        '--output-format' { $i++; continue }
        '--rules' { $i++; continue }
        '--persistent' {
            [Console]::Error.WriteLine('fake-grok: --persistent is not a real grok flag')
            exit 2
        }
        '--max-turns' { $i++; continue }
        '--version' { Write-Output 'fake-0.0.1'; exit 0 }
        '--no-auto-update' { continue }
        '--no-alt-screen' { continue }
        '--always-approve' { continue }
        '--yolo' { continue }
        '--json' { continue }
        default {
            if ($a -notmatch '^-') { [void]$positional.Add($a) }
        }
    }
}

if (-not $prompt -and $positional.Count -ge 1) {
    $knownCmd = @('version', 'sessions', 'export', 'agent', 'inspect')
    if ($knownCmd -notcontains [string]$positional[0]) {
        $prompt = ($positional -join ' ')
    }
}

if ($positional.Count -ge 1) {
    $cmd = $positional[0]
    switch ($cmd) {
        'version' {
            Write-Output 'fake-0.0.1'
            exit 0
        }
        'sessions' {
            $sd = Get-SessionDir
            $files = @(Get-ChildItem $sd -Filter '*.json' -ErrorAction SilentlyContinue)
            if ($files.Count -eq 0) { Write-Output '(no sessions)' }
            else { $files | ForEach-Object { Write-Output $_.BaseName } }
            exit 0
        }
        'export' {
            $id = $null
            $out = $null
            if ($positional.Count -ge 2) { $id = $positional[1] }
            if ($positional.Count -ge 3) { $out = $positional[2] }
            $md = "# fake transcript`r`n`r`nsession: $id`r`n"
            if ($out) {
                $dir = Split-Path $out -Parent
                if ($dir -and -not (Test-Path $dir)) {
                    New-Item -ItemType Directory -Force -Path $dir | Out-Null
                }
                [IO.File]::WriteAllText($out, $md)
            }
            else { Write-Output $md }
            exit 0
        }
        'agent' {
            [Console]::Error.WriteLine('wp3: agent stdio not in MVP')
            exit 2
        }
        'inspect' {
            Write-Output ((@{ ok = $true; fake = $true; cwd = $cwd; version = 'fake-0.0.1' } | ConvertTo-Json -Compress))
            exit 0
        }
    }
}

$singleTurn = $false
if ($argv -contains '-p' -or $argv -contains '--single') { $singleTurn = $true }

if (-not $singleTurn -and $prompt -and ($sessionId -or $env:BOB_REPO_PAIR_WORKER_DIR)) {
    $persistent = $true
}

if ($persistent) {
    if (-not $sessionId) { $sessionId = [guid]::NewGuid().ToString() }
    if ($prompt) { Save-Session -Id $sessionId -Prompt $prompt }
    $hbPath = $env:BOB_REPO_PAIR_HEARTBEAT_PATH
    $workerDir = $env:BOB_REPO_PAIR_WORKER_DIR
    $role = $env:BOB_REPO_PAIR_ROLE
    if (-not $role) { $role = 'dev' }
    $lastTask = $null
    while ($true) {
        if ($hbPath) {
            $hb = @{ seat = $role; sessionId = $sessionId; at = [DateTime]::UtcNow.ToString('o'); agentPid = $PID }
            [IO.File]::WriteAllText($hbPath, ($hb | ConvertTo-Json -Compress))
        }
        if ($workerDir) {
            $inbox = Join-Path $workerDir 'inbox\chair-task.txt'
            if (Test-Path -LiteralPath $inbox) {
                try {
                    $task = ([IO.File]::ReadAllText($inbox)).Trim()
                    if ($task -and $task -ne $lastTask) {
                        $lastTask = $task
                        $touch = Join-Path $workerDir 'inbox\chair-touched.txt'
                        [IO.File]::WriteAllText($touch, $task)
                        $exec = Join-Path $workerDir 'outbox\chair-executed.txt'
                        [IO.File]::WriteAllText($exec, $task)
                        if ($task -match '(?i)HARVEST') {
                            $skillsDir = Join-Path $workerDir '.grok\skills'
                            New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null
                            $stamp = Join-Path $skillsDir ('harvest-stamp-' + [guid]::NewGuid().ToString('n') + '.txt')
                            [IO.File]::WriteAllText($stamp, ([DateTime]::UtcNow.ToString('o')))
                            $harvestAck = Join-Path $workerDir 'inbox\harvest-ack.txt'
                            [IO.File]::WriteAllText($harvestAck, ('harvested ' + $stamp))
                        }
                    }
                }
                catch { }
            }
        }
        Start-Sleep -Seconds 3
    }
}

if ($null -eq $prompt) {
    [Console]::Error.WriteLine('fake-grok: no -p prompt')
    exit 2
}

$resumed = $false
if ($resumeId) {
    if (Test-Session -Id $resumeId) {
        $resumed = $true
        $sessionId = $resumeId
    }
    else {
        Write-JsonOut @{ sessionId = $resumeId; result = $null; stop_reason = 'Error'; resumed = $false; error = 'unknown session' } 1
    }
}

if (-not $sessionId) {
    $sessionId = [guid]::NewGuid().ToString()
}

Save-Session -Id $sessionId -Prompt $prompt

if ($prompt -eq 'FAIL') {
    Write-JsonOut @{
        sessionId   = $sessionId
        result      = $null
        stop_reason = 'Error'
        resumed     = $resumed
    } 1
}

if ($prompt -eq 'EMPTY' -or $prompt -eq 'NORESULT') {
    Write-JsonOut @{
        sessionId   = $sessionId
        stop_reason = 'EndTurn'
        resumed     = $resumed
    } 0
}

Write-JsonOut @{
    sessionId   = $sessionId
    result      = $prompt
    stop_reason = 'EndTurn'
    resumed     = $resumed
} 0
