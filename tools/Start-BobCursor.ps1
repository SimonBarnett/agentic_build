# Hand a git-task packet to Cursor Agent (cursor-models fuel).
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
    [string]$Cwd
)

$ErrorActionPreference = 'Stop'

if ($Job) {
    if (-not $Repo) { $Repo = [string]$Job.repo }
    if (-not $Branch) { $Branch = [string]$Job.branch }
    if (-not $Docs) { $Docs = [string]$Job.docs }
    if (-not $Plan) { $Plan = [string]$Job.plan }
    if (-not $Mrb) { $Mrb = [string]$Job.mrb }
    if (-not $Goal) { $Goal = [string]$Job.goal }
    if (-not $JobId) { $JobId = [string]$Job.id }
    if (-not $Cwd) { $Cwd = [string]$Job.cwd }
}

if (-not $JobId) { $JobId = [guid]::NewGuid().ToString() }
if (-not $Branch) { $Branch = ('work/{0}' -f $JobId) }

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
    note   = 'Commit and push on the work branch. Do not mark ready for human UAT. Bob chairs MRB.'
}

$outDir = $env:BOB_BRIDGE_HOME
if (-not $outDir) { $outDir = Join-Path $env:TEMP 'bob-cursor-handoff' }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$path = Join-Path $outDir ('cursor-git-' + $JobId + '.json')
$json = $packet | ConvertTo-Json -Depth 6
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($path, $json, $utf8)

$agent = $null
foreach ($c in @(
        (Join-Path $env:USERPROFILE '.grok\bin\agent.exe'),
        (Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.exe')
    )) {
    if ($c -and (Test-Path $c)) { $agent = $c; break }
}
$cmd = Get-Command agent.exe -ErrorAction SilentlyContinue
if (-not $agent -and $cmd) { $agent = $cmd.Source }

$started = $false
$startError = $null
if ($agent -and $Cwd -and -not ($env:BOB_GROK_EXE -match '(?i)Fake-Grok')) {
    $prompt = @"
Git task $JobId. Repo $Repo branch $Branch.
Read $Docs and $Plan. Implement, commit, and push $Branch.
Do not mark ready for human UAT. Bob chairs MRB ($Mrb).
Goal: $Goal
"@
    try {
        Start-Process -FilePath $agent -ArgumentList @('-p', $prompt) -WorkingDirectory $Cwd -WindowStyle Hidden | Out-Null
        $started = $true
    }
    catch {
        $startError = $_.Exception.Message
    }
}

[pscustomobject]@{
    ok          = $true
    fuel        = 'cursor-models'
    jobId       = $JobId
    packetPath  = $path
    agent       = $agent
    started     = $started
    startError  = $startError
    branch      = $Branch
}
