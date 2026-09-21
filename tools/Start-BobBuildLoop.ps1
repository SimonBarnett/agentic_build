# Dispatcher loop: start a git job, MRB it until PASS-nits, retry failed
# cursor/grok jobs. Stdout is DONE/FAILED only (monitor-safe). Does not stamp UAT.
# Test-Pack: -Once -TestWorld (no live GitHub, no live cursor-agent, no live bridge).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Issue,
    [string]$Repo = 'SimonBarnett/agentic_build',
    [string]$Docs,
    [string]$Plan,
    [string]$Cwd,
    [string]$Goal,
    [string]$Sha,
    [string]$Pr,
    [ValidateSet('cursor-models', 'grok-build')][string]$Fuel = 'cursor-models',
    [int]$MaxJobRetries = 3,
    [int]$MaxMrbFails = 8,
    [int]$PollSec = 30,
    [switch]$AllowCopilot,
    [switch]$Once,
    [object]$TestWorld,
    [scriptblock]$TestStartBuild,
    [scriptblock]$TestStartMrb,
    [scriptblock]$TestStartFix,
    [scriptblock]$TestComment,
    [string]$StatePath,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path $MyInvocation.MyCommand.Path }
. (Join-Path $here 'Bob-BuildLoop.ps1')
. (Join-Path $here 'Bob-Gh.ps1')

if ($PSBoundParameters.ContainsKey('TestWorld') -and -not $Once) {
    throw 'TestWorld is Test-Pack only and requires -Once.'
}

$repoSlug = Get-BobBuildLoopRepoSlug $Repo
$repoUrl = "https://github.com/$repoSlug"
if (-not $StatePath) { $StatePath = Get-BobBuildLoopStatePath -Repo $repoSlug -Issue $Issue }
if (-not $LogPath) {
    $logDir = Join-Path (Get-BobBuildLoopRoot) 'loops'
    $LogPath = Join-Path $logDir ('{0}-{1}.log' -f ($repoSlug -replace '[\\/]', '_'), $Issue)
    if (-not $TestWorld) {
        $liveLogDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
        New-Item -ItemType Directory -Force -Path $liveLogDir | Out-Null
        $LogPath = Join-Path $liveLogDir ('bob-build-loop-{0}-{1}.log' -f ($repoSlug -replace '[\\/]', '_'), $Issue)
    }
}

$live = -not $PSBoundParameters.ContainsKey('TestWorld')
if ($live) {
    $repoRoot = Split-Path $here -Parent
    Import-Module (Join-Path $repoRoot 'src\BobBridge.psd1') -Force
    if (-not $Cwd) {
        $leaf = $repoSlug.Split('/')[-1]
        foreach ($c in @("C:\ai\$leaf", "D:\ai\$leaf", "C:\src\$leaf")) {
            if (Test-Path (Join-Path $c '.git')) { $Cwd = $c; break }
        }
        if (-not $Cwd) { $Cwd = $repoRoot }
    }
}

$state = Read-BobBuildLoopState -Path $StatePath
if (-not $state) {
    $state = New-BobBuildLoopState -Repo $repoSlug -Issue $Issue -Docs $Docs -Plan $Plan -Cwd $Cwd -Goal $Goal -Sha $Sha -Pr $Pr -Fuel $Fuel -MaxJobRetries $MaxJobRetries -MaxMrbFails $MaxMrbFails
    Write-BobBuildLoopState -Path $StatePath -State $state
}

function Get-LoopWorld {
    param($State)
    $prs = @()
    $issues = @()
    $gh = Get-BobGhExe
    if ($gh) {
        $prJson = & $gh pr list --repo $State.repo --state open --limit 30 --json number,url,title,headRefName,headRefOid,createdAt 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $prJson.Trim()) {
            foreach ($p in @($prJson | ConvertFrom-Json)) {
                $prs += [pscustomobject]@{
                    number    = $p.number
                    url       = [string]$p.url
                    title     = [string]$p.title
                    branch    = [string]$p.headRefName
                    sha       = [string]$p.headRefOid
                    createdAt = [string]$p.createdAt
                }
            }
        }
        $isJson = & $gh issue list --repo $State.repo --state all --label mrb --limit 40 --json number,title,url,body,labels,createdAt 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $isJson.Trim()) {
            foreach ($i in @($isJson | ConvertFrom-Json)) {
                $issues += [pscustomobject]@{
                    number    = $i.number
                    title     = [string]$i.title
                    url       = [string]$i.url
                    body      = [string]$i.body
                    createdAt = [string]$i.createdAt
                }
            }
        }
    }
    $job = $null
    if ($State.currentJobId) {
        try {
            $j = Get-BobBuild -JobId ([string]$State.currentJobId)
            if ($j) {
                $cs = $null
                if ($j.completion) { $cs = [string]$j.completion.status }
                $job = [pscustomobject]@{
                    id                 = [string]$j.id
                    lane               = [string]$j.lane
                    state              = [string]$j.state
                    completionStatus   = $cs
                    fuel               = [string]$j.fuel
                    pid                = $State.currentPid
                    startError         = $null
                    started            = $null
                }
            }
        }
        catch { }
    }
    if (-not $job) {
        if ($State.startError -or $State.currentJobId -or $State.currentPid) {
            $started = $null
            if ($State.startError) { $started = $false }
            $job = [pscustomobject]@{
                id               = $(if ($State.currentJobId) { [string]$State.currentJobId } else { $null })
                lane             = $null
                state            = $null
                completionStatus = $null
                fuel             = [string]$State.fuel
                pid              = $State.currentPid
                startError       = $(if ($State.startError) { [string]$State.startError } else { $null })
                started          = $started
            }
        }
    }
    elseif ($State.startError) {
        $job | Add-Member -NotePropertyName startError -NotePropertyValue ([string]$State.startError) -Force
        $job | Add-Member -NotePropertyName started -NotePropertyValue $false -Force
    }
    $alive = $null
    if ($State.currentPid) { $alive = Test-BobBuildLoopPidAlive -ProcessId $State.currentPid }
    return [pscustomobject]@{
        Job          = $job
        ProcessAlive = $alive
        Prs          = $prs
        Issues       = $issues
    }
}

function Invoke-LoopComment {
    param($Backlink, $State)
    if (-not $Backlink) { return $null }
    if ($TestComment) {
        return & $TestComment $Backlink
    }
    if (-not $live) { return $Backlink }
    $gh = Get-BobGhExe
    if (-not $gh) {
        Write-BobBuildLoopLog -Path $LogPath -Message "comment skipped (no gh): $($Backlink.body)"
        return $Backlink
    }
    $bodyPath = Join-Path $env:TEMP ('bob-loop-comment-' + [guid]::NewGuid().ToString('N') + '.md')
    try {
        [IO.File]::WriteAllText($bodyPath, [string]$Backlink.body, [System.Text.UTF8Encoding]::new($false))
        $out = & $gh issue comment ([int]$Backlink.issue) --repo $State.repo --body-file $bodyPath 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-BobBuildLoopLog -Path $LogPath -Message "comment failed issue $($Backlink.issue): $out"
        }
        else {
            Write-BobBuildLoopLog -Path $LogPath -Message "commented issue $($Backlink.issue)"
        }
    }
    finally {
        if (Test-Path -LiteralPath $bodyPath) { Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue }
    }
    return $Backlink
}

function Invoke-LoopStartBuild {
    param($State, [string]$GoalText, [switch]$Fix)
    if ($Fix -and $TestStartFix) { return & $TestStartFix $State $GoalText }
    if (-not $Fix -and $TestStartBuild) { return & $TestStartBuild $State $GoalText }
    if (-not $live) {
        return [pscustomobject]@{ ok = $true; started = $true; jobId = [guid]::NewGuid().ToString(); pid = $null; fuel = [string]$State.fuel; branch = $null }
    }
    if (Get-Command Test-PromptSecrets -ErrorAction SilentlyContinue) {
        if (Test-PromptSecrets -Prompt $GoalText) {
            return [pscustomobject]@{ ok = $false; started = $false; startError = 'goal contains password= or XAI_API_KEY'; jobId = $null; pid = $null }
        }
    }
    $jobId = [guid]::NewGuid().ToString()
    $useFuel = [string]$State.fuel
    if (-not $useFuel) { $useFuel = 'cursor-models' }
    $mrbRef = $(if ($State.lastMrb) { [string]$State.lastMrb } else { "$repoUrl/issues/$($State.issue)" })
    if ($useFuel -eq 'cursor-models') {
        $cursor = Join-Path $here 'Start-BobCursor.ps1'
        $cArgs = @{
            Repo  = $repoUrl
            Cwd   = [string]$State.cwd
            Goal  = $GoalText
            Kind  = 'build'
            JobId = $jobId
            Mrb   = $mrbRef
        }
        if ($State.docs) { $cArgs['Docs'] = [string]$State.docs }
        if ($State.plan) { $cArgs['Plan'] = [string]$State.plan }
        $hand = & $cursor @cArgs
        if ($hand.started) {
            return [pscustomobject]@{
                ok      = $true
                started = $true
                jobId   = $jobId
                pid     = $hand.pid
                fuel    = 'cursor-models'
                branch  = [string]$hand.branch
            }
        }
        Write-BobBuildLoopLog -Path $LogPath -Message "cursor-models start missed ($($hand.startError)); grok-build"
        $useFuel = 'grok-build'
        $State | Add-Member -NotePropertyName fuel -NotePropertyValue 'grok-build' -Force
    }
    $bArgs = @{
        Task   = 'git'
        Fuel   = $useFuel
        Kind   = 'build'
        Cwd    = [string]$State.cwd
        Goal   = $GoalText
        Repo   = $repoUrl
        JobId  = $jobId
        Mrb    = $mrbRef
    }
    if ($Fix) { $bArgs['Fix'] = $true }
    if ($State.docs) { $bArgs['Docs'] = [string]$State.docs }
    if ($State.plan) { $bArgs['Plan'] = [string]$State.plan }
    if ($AllowCopilot) { $bArgs['AllowCopilot'] = $true }
    $q = Start-BobBuild @bArgs
    if (-not $q.ok -or $q.wait) {
        $why = $(if ($q.reason) { [string]$q.reason } else { 'enqueue refused' })
        return [pscustomobject]@{ ok = $false; started = $false; startError = $why; jobId = $jobId; pid = $null; fuel = $useFuel }
    }
    return [pscustomobject]@{
        ok      = $true
        started = $true
        jobId   = [string]$q.jobId
        pid     = $null
        fuel    = $useFuel
        branch  = [string]$q.branch
    }
}

function Invoke-LoopStartMrb {
    param($State)
    if ($TestStartMrb) { return & $TestStartMrb $State }
    if (-not $live) {
        return [pscustomobject]@{ ok = $true; started = $true; jobId = [guid]::NewGuid().ToString(); pid = $null; fuel = [string]$State.fuel }
    }
    $handoff = Join-Path $here 'Start-BobMrbHandoff.ps1'
    $hArgs = @{
        Issue = [int]$State.issue
        Repo  = [string]$State.repo
        Cwd   = [string]$State.cwd
        Fuel  = $(if ($State.fuel) { [string]$State.fuel } else { 'cursor-models' })
    }
    if ($State.currentSha) { $hArgs['Sha'] = [string]$State.currentSha }
    if ($State.currentPr) { $hArgs['Pr'] = [string]$State.currentPr }
    if ($State.docs) { $hArgs['Docs'] = [string]$State.docs }
    if ($State.plan) { $hArgs['Plan'] = [string]$State.plan }
    if ($AllowCopilot) { $hArgs['AllowCopilot'] = $true }
    try {
        $r = & $handoff @hArgs
    }
    catch {
        $why = $_.Exception.Message
        if (-not $why) { $why = 'MRB handoff refused' }
        return [pscustomobject]@{
            ok         = $false
            started    = $false
            jobId      = $null
            pid        = $null
            fuel       = [string]$State.fuel
            startError = $why
        }
    }
    $pid = $null
    if ($r.pid) { $pid = $r.pid }
    $jobId = $null
    if ($r.jobId) { $jobId = [string]$r.jobId }
    $started = $true
    if ($r.PSObject.Properties['started'] -and $r.started -eq $false) { $started = $false }
    $err = $null
    if ($r.startError) { $err = [string]$r.startError }
    if (-not $r.ok -and $r.PSObject.Properties['ok']) {
        $started = $false
        if (-not $err) { $err = 'MRB handoff refused' }
    }
    return [pscustomobject]@{
        ok         = [bool]$started
        started    = $started
        jobId      = $jobId
        pid        = $pid
        fuel       = $(if ($r.handed) { [string]$r.handed } else { [string]$State.fuel })
        startError = $err
    }
}

function Apply-StartResult {
    param($State, $Decision, $Started, [string]$WaitPhase)
    $attempts = 0
    if ($State.jobAttempts) { $attempts = [int]$State.jobAttempts }
    $State | Add-Member -NotePropertyName jobAttempts -NotePropertyValue ($attempts + 1) -Force
    if ($Started.fuel) { $State | Add-Member -NotePropertyName fuel -NotePropertyValue $Started.fuel -Force }
    if ($Started.branch) { $State | Add-Member -NotePropertyName currentBranch -NotePropertyValue $Started.branch -Force }
    $State | Add-Member -NotePropertyName currentJobId -NotePropertyValue $Started.jobId -Force
    $State | Add-Member -NotePropertyName currentPid -NotePropertyValue $Started.pid -Force
    if ($Started.started) {
        $State | Add-Member -NotePropertyName phase -NotePropertyValue $WaitPhase -Force
        $State | Add-Member -NotePropertyName startError -NotePropertyValue $null -Force
    }
    else {
        $State | Add-Member -NotePropertyName startError -NotePropertyValue $(if ($Started.startError) { [string]$Started.startError } else { 'start refused' }) -Force
        $State | Add-Member -NotePropertyName phase -NotePropertyValue $WaitPhase -Force
    }
    return $State
}

$result = $null
$terminal = $false
$stdout = $null
$exitCode = 0

while ($true) {
    $world = $null
    if ($PSBoundParameters.ContainsKey('TestWorld')) { $world = $TestWorld }
    else { $world = Get-LoopWorld -State $state }

    $decision = Get-BobBuildLoopDecision -State $state -World $world
    Write-BobBuildLoopLog -Path $LogPath -Message ("phase={0} action={1} reason={2}" -f [string]$state.phase, [string]$decision.action, [string]$decision.reason)

    if ($decision.patch) { $state = Merge-BobBuildLoopPatch -State $state -Patch $decision.patch }
    if ($decision.pass) { $state = Add-BobBuildLoopPass -State $state -Pass $decision.pass }
    $commented = $null
    if ($decision.backlink) { $commented = Invoke-LoopComment -Backlink $decision.backlink -State $state }

    $started = $null
    switch ([string]$decision.action) {
        'start_build' {
            $g = $decision.goal
            if (-not $g) { $g = New-BobBuildGoal -State $state }
            $started = Invoke-LoopStartBuild -State $state -GoalText $g
            $state = Apply-StartResult -State $state -Decision $decision -Started $started -WaitPhase 'wait_pr'
        }
        'start_fix' {
            $g = $decision.goal
            if (-not $g) { $g = New-BobFixGoal -MrbUrl ([string]$state.lastMrb) -Fixes '' }
            $started = Invoke-LoopStartBuild -State $state -GoalText $g -Fix
            $state = Apply-StartResult -State $state -Decision $decision -Started $started -WaitPhase 'wait_pr'
        }
        'start_mrb' {
            $started = Invoke-LoopStartMrb -State $state
            $state = Apply-StartResult -State $state -Decision $decision -Started $started -WaitPhase 'wait_mrb'
        }
        'retry_job' {
            $kind = [string]$decision.kind
            if (-not $kind) { $kind = [string]$state.currentKind }
            if ($kind -eq 'mrb') {
                $started = Invoke-LoopStartMrb -State $state
                $state = Apply-StartResult -State $state -Decision $decision -Started $started -WaitPhase 'wait_mrb'
            }
            else {
                $g = New-BobBuildGoal -State $state
                $fix = $false
                if ($state.lastMrb) {
                    $fixes = Resolve-BobBuildLoopRequiredFixes -State $state -World $world
                    $g = New-BobFixGoal -MrbUrl ([string]$state.lastMrb) -Fixes $fixes
                    $fix = $true
                }
                $started = Invoke-LoopStartBuild -State $state -GoalText $g -Fix:$fix
                $state = Apply-StartResult -State $state -Decision $decision -Started $started -WaitPhase 'wait_pr'
            }
        }
        'pass' {
            $terminal = $true
            $stdout = [string]$decision.stdout
            $exitCode = 0
            if ($live) {
                $auditJob = [string]$state.currentJobId
                if (-not $auditJob) { $auditJob = "loop-$Issue" }
                try {
                    Write-BobJobAuditLine -JobId $auditJob -Machine '' -Fuel ([string]$state.fuel) -Model '' -Kind 'mrb-pass' -PrUrl ([string]$state.currentPr) -MrbIssue ([string]$state.lastMrb) -Sha ([string]$state.currentSha) -Status 'pass-nits'
                }
                catch {
                    $auditErr = $_.Exception.Message
                    if (-not $auditErr) { $auditErr = $_.ToString() }
                    Write-BobBuildLoopLog -Path $LogPath -Message "job-audit pass-nits failed: $auditErr"
                    throw
                }
            }
        }
        'fail' {
            $terminal = $true
            $stdout = [string]$decision.stdout
            $exitCode = 1
        }
        'sleep' { }
        default {
            $terminal = $true
            $stdout = "FAILED: unknown action $($decision.action)"
            $exitCode = 1
        }
    }

    Write-BobBuildLoopState -Path $StatePath -State $state
    $result = [pscustomobject]@{
        ok         = ($exitCode -eq 0)
        action     = [string]$decision.action
        phase      = [string]$state.phase
        state      = $state
        decision   = $decision
        started    = $started
        backlink   = $commented
        statePath  = $StatePath
        logPath    = $LogPath
        stdout     = $stdout
        board      = (Get-BobMrbBoard -Repo $repoSlug -Issue $Issue -Path $StatePath)
    }

    if ($terminal) {
        if ($live -or -not $Once) {
            Write-Output $stdout
        }
        if ($Once) { return $result }
        exit $exitCode
    }

    if ($Once) { return $result }
    Start-Sleep -Seconds $PollSec
}
