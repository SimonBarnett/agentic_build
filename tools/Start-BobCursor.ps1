# Hand a git-task packet to Cursor Agent (cursor-models fuel).
# Never use ~/.grok/bin/agent.exe — that is grok.exe. Look for cursor-agent.
# Does not scrape Cursor cookies. Does not mark UAT. Bob chairs MRB.
[CmdletBinding()]
param(
    $Job,
    [string]$Repo,
    [string]$Branch,
    [string]$Docs,
    [string]$Plan,
    [string]$Mrb,
    [string]$Goal,
    [string]$JobId,
    [string]$Cwd,
    [string]$Model,
    [ValidateSet('mrb', 'build')][string]$Kind,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path $MyInvocation.MyCommand.Path }
$bobPsd1 = Join-Path (Split-Path $here -Parent) 'src\BobBridge.psd1'
if (-not (Get-Module -Name BobBridge)) {
    Import-Module $bobPsd1 -Force
}

function Get-BobCursorAgentExe {
    foreach ($c in @(
            (Join-Path $env:USERPROFILE '.local\bin\cursor-agent.exe'),
            (Join-Path $env:USERPROFILE '.local\bin\agent.exe'),
            (Join-Path $env:USERPROFILE '.cursor\bin\cursor-agent.exe'),
            (Join-Path $env:USERPROFILE '.cursor\bin\agent.exe'),
            (Join-Path $env:LOCALAPPDATA 'cursor-agent\cursor-agent.cmd'),
            (Join-Path $env:LOCALAPPDATA 'cursor-agent\cursor-agent.ps1'),
            (Join-Path $env:LOCALAPPDATA 'cursor-agent\cursor-agent.exe'),
            (Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.cmd')
        )) {
        if ($c -and (Test-Path $c)) {
            # Refuse grok.exe disguised as agent.exe
            $grok = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
            if ((Test-Path $grok) -and ((Get-Item $c).Length -eq (Get-Item $grok).Length)) { continue }
            return $c
        }
    }
    foreach ($name in @('cursor-agent.cmd', 'cursor-agent.exe', 'cursor-agent')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

if ($Job) {
    if (-not $Repo) { $Repo = [string]$Job.repo }
    if (-not $Branch) { $Branch = [string]$Job.branch }
    if (-not $Docs) { $Docs = [string]$Job.docs }
    if (-not $Plan) { $Plan = [string]$Job.plan }
    if (-not $Mrb) { $Mrb = [string]$Job.mrb }
    if (-not $Goal) { $Goal = [string]$Job.goal }
    if (-not $JobId) { $JobId = [string]$Job.id }
    if (-not $Cwd) { $Cwd = [string]$Job.cwd }
    if (-not $Model -and $Job.model) { $Model = [string]$Job.model }
}

$kindResolved = 'build'
if ($PSBoundParameters.ContainsKey('Kind')) {
    $kindResolved = $Kind
}
elseif ($Job -and $Job.kind) {
    $kindResolved = [string]$Job.kind
}

if (-not $JobId) { $JobId = [guid]::NewGuid().ToString() }
if (-not $Branch) { $Branch = ('work/{0}' -f $JobId) }
if (-not $Model) { $Model = Get-BobJobModel -Kind $kindResolved -Fuel cursor-models }

$packet = [ordered]@{
    task   = 'git'
    fuel   = 'cursor-models'
    jobId  = $JobId
    repo   = $Repo
    branch = $Branch
    docs   = $Docs
    plan   = $Plan
    mrb    = $Mrb
    cwd    = $Cwd
    goal   = $Goal
    kind   = $kindResolved
    model  = $Model
    note   = $(if ($kindResolved -eq 'mrb') {
            'Review the PR. PASS-nits: merge it (nits do not block). FAIL: do not merge; Required fixes only. Do not mark ready for human UAT.'
        } else {
            'Open a PR from the work branch. Never push main. Never merge. Do not mark ready for human UAT. Bob chairs UAT.'
        })
}

$outDir = $env:BOB_BRIDGE_HOME
if (-not $outDir) { $outDir = Join-Path $env:TEMP 'bob-cursor-handoff' }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$path = Join-Path $outDir ('cursor-git-' + $JobId + '.json')
$json = $packet | ConvertTo-Json -Depth 6
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($path, $json, $utf8)

$suppressLaunch = $NoLaunch
if (-not $suppressLaunch -and $env:BOB_NO_AGENT_LAUNCH -match '^(?i)(1|true|yes)$') { $suppressLaunch = $true }
if (-not $suppressLaunch -and (Get-Command Test-BobUsesFakeGrok -ErrorAction SilentlyContinue)) {
    if (Test-BobUsesFakeGrok) { $suppressLaunch = $true }
}
if (-not $suppressLaunch -and $env:BOB_GROK_EXE -match '(?i)Fake-Grok') { $suppressLaunch = $true }

$agent = Get-BobCursorAgentExe
$started = $false
$startError = $null
$logPath = $null
if ($suppressLaunch) {
    $startError = 'no_launch'
}
elseif ($agent) {
    $stExe = $agent
    $stArg = @('status')
    if ($agent -match '\.cmd$' -or $agent -match '\.ps1$') {
        $stExe = (Get-Command powershell.exe).Source
        $ps1 = $agent
        if ($agent -match '\.cmd$') { $ps1 = Join-Path (Split-Path $agent) 'cursor-agent.ps1' }
        $stArg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1, 'status')
    }
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $st = & $stExe @stArg 2>$null | Out-String
    }
    catch {
        $st = [string]$_
    }
    finally {
        $ErrorActionPreference = $savedEap
    }
    if ($st -match '(?i)not logged in') {
        $startError = 'cursor-agent not logged in (CURSOR_API_KEY or cursor-agent login)'
        $agent = $null
    }
}
if ($agent -and $Cwd -and -not $suppressLaunch) {
    $readBits = @()
    if ($Docs) { $readBits += $Docs }
    if ($Plan) { $readBits += $Plan }
    $readLine = $(if ($readBits.Count -gt 0) { "Read $($readBits -join ' and '). " } else { '' })
    $prompt = @"
Git task $JobId. Repo $Repo.
$readLine$Goal
Do not mark ready for human UAT. Bob chairs MRB ($Mrb).
Do not put password= or XAI_API_KEY= assignments in git.
"@
    $logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $logPath = Join-Path $logDir ('cursor-agent-' + $JobId + '.log')
    try {
        $promptFile = Join-Path $logDir ('cursor-agent-' + $JobId + '.prompt.txt')
        [IO.File]::WriteAllText($promptFile, $prompt, $utf8)
        $ps1 = $agent
        if ($agent -match '\.cmd$') { $ps1 = Join-Path (Split-Path $agent) 'cursor-agent.ps1' }
        $launch = Join-Path $logDir ('cursor-agent-' + $JobId + '.launch.ps1')
        $launchBody = @"
`$ErrorActionPreference = 'Stop'
`$prompt = [IO.File]::ReadAllText('$($promptFile.Replace("'","''"))')
Set-Location -LiteralPath '$($Cwd.Replace("'","''"))'
`$out = '$($logPath.Replace("'","''"))'
`$err = '$($logPath.Replace("'","''")).err'
& '$($ps1.Replace("'","''"))' -p --force --trust --output-format text --model '$($Model.Replace("'","''"))' -- `$prompt 1>`$out 2>`$err
"@
        [IO.File]::WriteAllText($launch, $launchBody, $utf8)
        $exe = (Get-Command powershell.exe).Source
        # Win32_Process.Create so the agent outlives this shell's Job Object
        # (Start-Process children died when the grok.exe command exited).
        $cmdLine = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $exe, $launch
        $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
            CommandLine      = $cmdLine
            CurrentDirectory = $Cwd
        }
        if ($created.ReturnValue -ne 0 -or -not $created.ProcessId) {
            throw "Win32_Process.Create return=$($created.ReturnValue)"
        }
        $started = $true
        $packet.pid = [int]$created.ProcessId
        # #70 MUST 2: shop-only worker irc_agent (w-io-<pid> on ionos, etc.)
        try {
            Start-BobWorkerIrcAgent -WorkerPid ([int]$packet.pid)
        }
        catch { }
    }
    catch {
        $startError = $_.Exception.Message
    }
}
elseif (-not $agent -and -not $suppressLaunch) {
    $startError = 'cursor-agent.exe not found (do not use ~/.grok/bin/agent.exe; that is grok)'
}

[pscustomobject]@{
    ok         = $true
    fuel       = 'cursor-models'
    jobId      = $JobId
    packetPath = $path
    agent      = $agent
    started    = $started
    startError = $startError
    logPath    = $logPath
    branch     = $Branch
    pid        = $(if ($packet.pid) { $packet.pid } else { $null })
}
