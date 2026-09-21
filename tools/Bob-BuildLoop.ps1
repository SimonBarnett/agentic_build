# Build/MRB loop primitives. Dot-sourced by Start-BobBuildLoop.ps1 and Test-Pack.
# No live GitHub, no live cursor-agent, no live bob-bridge on load.

$ErrorActionPreference = 'Stop'

function Get-BobBuildLoopRoot {
    if ($env:BOB_BRIDGE_HOME -and $env:BOB_BRIDGE_HOME.Trim()) {
        return [IO.Path]::GetFullPath($env:BOB_BRIDGE_HOME)
    }
    return [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.grok\bob-bridge'))
}

function Get-BobBuildLoopRepoSlug {
    param([string]$Repo)
    if (-not $Repo) { return $Repo }
    $r = $Repo.Trim().TrimEnd('/')
    if ($r -match 'github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?$') {
        return $Matches[1]
    }
    if ($r.EndsWith('.git')) { $r = $r.Substring(0, $r.Length - 4) }
    return $r
}

function Get-BobBuildLoopStatePath {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$Issue
    )
    $slug = (Get-BobBuildLoopRepoSlug $Repo) -replace '[\\/]', '_'
    $dir = Join-Path (Get-BobBuildLoopRoot) 'loops'
    return Join-Path $dir ('{0}-{1}.json' -f $slug, $Issue)
}

function New-BobBuildLoopState {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$Issue,
        [string]$Docs,
        [string]$Plan,
        [string]$Cwd,
        [string]$Goal,
        [string]$Sha,
        [string]$Pr,
        [string]$Fuel = 'cursor-models',
        [int]$MaxJobRetries = 3,
        [int]$MaxMrbFails = 8
    )
    $now = [DateTime]::UtcNow.ToString('o')
    $kind = 'build'
    if ($Sha) { $kind = 'mrb' }
    return [pscustomobject]@{
        repo           = Get-BobBuildLoopRepoSlug $Repo
        issue          = $Issue
        docs           = $Docs
        plan           = $Plan
        cwd            = $Cwd
        goal           = $Goal
        fuel           = $Fuel
        currentSha     = $Sha
        currentPr      = $Pr
        currentKind    = $kind
        currentJobId   = $null
        currentPid     = $null
        currentBranch  = $null
        priorMrbIssue  = $null
        lastMrb        = $null
        phase          = 'idle'
        jobAttempts    = 0
        mrbFails       = 0
        maxJobRetries  = $MaxJobRetries
        maxMrbFails    = $MaxMrbFails
        watchAfter     = $now
        seenPrs        = @()
        passes         = @()
        failReason     = $null
        startError     = $null
        requiredFixes  = $null
        createdAt      = $now
        updatedAt      = $now
    }
}

function Read-BobBuildLoopState {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = [IO.File]::ReadAllText($Path)
    if (-not $raw.Trim()) { return $null }
    return $raw | ConvertFrom-Json
}

function Write-BobBuildLoopState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$State
    )
    $State | Add-Member -NotePropertyName updatedAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Path, ($State | ConvertTo-Json -Depth 12), $utf8)
}

function Get-BobMrbBoard {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$Issue,
        [string]$Path
    )
    if (-not $Path) { $Path = Get-BobBuildLoopStatePath -Repo $Repo -Issue $Issue }
    $s = Read-BobBuildLoopState -Path $Path
    if (-not $s) { return $null }
    $passes = @($s.passes)
    $last = $null
    if ($passes.Count -gt 0) { $last = $passes[$passes.Count - 1] }
    return [pscustomobject]@{
        repo     = [string]$s.repo
        issue    = [int]$s.issue
        phase    = [string]$s.phase
        sha      = $(if ($last) { [string]$last.sha } else { [string]$s.currentSha })
        verdict  = $(if ($last) { [string]$last.verdict } else { $null })
        mrb      = $(if ($last) { [string]$last.mrb } else { [string]$s.lastMrb })
        pr       = $(if ($last) { [string]$last.pr } else { [string]$s.currentPr })
        passes   = $passes
        state    = $s
        path     = $Path
    }
}

function Get-BobMrbRequiredFixes {
    param([string]$Body)
    if (-not $Body) { return '' }
    $lines = $Body -split '\r?\n'
    $capturing = $false
    $buf = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -match '^#{1,6}\s+Required fixes\s*$') {
            $capturing = $true
            continue
        }
        if ($capturing -and $line -match '^#{1,6}\s+\S') { break }
        if ($capturing) { [void]$buf.Add($line) }
    }
    return (($buf -join "`n").Trim())
}

function Resolve-BobBuildLoopRequiredFixes {
    param($State, $World)
    if ($State.requiredFixes) { return [string]$State.requiredFixes }
    if ($State.lastMrb -and $World -and $World.Issues) {
        foreach ($i in @($World.Issues)) {
            if ([string]$i.url -eq [string]$State.lastMrb) {
                return Get-BobMrbRequiredFixes ([string]$i.body)
            }
        }
    }
    return ''
}

function New-BobMrbBacklinkComment {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Sha
    )
    $shaBit = ''
    if ($Sha) { $shaBit = " (SHA $Sha)" }
    return "Next board: $Url$shaBit"
}

function New-BobFixPrComment {
    param(
        [Parameter(Mandatory)][string]$Url,
        [string]$Sha
    )
    $shaBit = ''
    if ($Sha) { $shaBit = " (SHA $Sha)" }
    return "FIX PR: $Url$shaBit"
}

function New-BobFixGoal {
    param(
        [Parameter(Mandatory)][string]$MrbUrl,
        [string]$Fixes
    )
    $block = $Fixes
    if (-not $block) {
        $block = "Read the Required fixes section on $MrbUrl. Implement those only."
    }
    return @"
Required fixes from $MrbUrl only.

$block

Open a new PR from a new work branch. Never push main. Never merge. Do not write ready for human UAT. Do not review your own PR.
"@
}

function New-BobBuildGoal {
    param($State)
    if ($State.goal -and [string]$State.goal) { return [string]$State.goal }
    $docs = $(if ($State.docs) { [string]$State.docs } else { 'docs/feature-request-*.md' })
    $plan = $(if ($State.plan) { [string]$State.plan } else { 'docs/build-and-test-plan*.md' })
    return "Implement GitHub issue #$($State.issue) on $($State.repo). Read $docs and $plan. Open a PR from the work branch. Never push main. Never merge. Do not write ready for human UAT."
}

function ConvertFrom-BobGhJsonList {
    param([string]$Raw)
    if (-not $Raw -or -not $Raw.Trim()) { return @() }
    $parsed = $Raw | ConvertFrom-Json
    $items = @($parsed)
    if ($items.Count -eq 1 -and $null -ne $items[0].PSObject.Properties['number'] -and ($items[0].number -is [System.Array])) {
        $o = $items[0]
        $nums = @($o.number)
        $out = @()
        $i = 0
        while ($i -lt $nums.Count) {
            $out += [pscustomobject]@{
                number      = $nums[$i]
                url         = @($o.url)[$i]
                title       = @($o.title)[$i]
                headRefName = @($o.headRefName)[$i]
                headRefOid  = @($o.headRefOid)[$i]
                createdAt   = @($o.createdAt)[$i]
            }
            $i++
        }
        return $out
    }
    return $items
}

function Get-BobBuildLoopShaNeedle {
    param([string]$Sha)
    if (-not $Sha) { return $null }
    $s = $Sha.Trim().ToLowerInvariant()
    if ($s -match '([0-9a-f]{7,40})') { $s = $Matches[1] }
    $short = $s
    if ($s.Length -ge 7) { $short = $s.Substring(0, 7) }
    return [pscustomobject]@{ full = $s; short = $short }
}

function Test-BobMrbTitleMatch {
    param(
        [string]$Title,
        [string]$Sha
    )
    if (-not $Title) { return $false }
    if ($Title -notmatch '^(?i)MRB (FAIL|PASS-nits):') { return $false }
    if (-not $Sha) { return $true }
    $n = Get-BobBuildLoopShaNeedle $Sha
    $t = $Title.ToLowerInvariant()
    return ($t.Contains($n.full) -or $t.Contains($n.short))
}

function Get-BobMrbVerdictFromTitle {
    param([string]$Title)
    if ($Title -match '^(?i)MRB PASS-nits:') { return 'PASS-nits' }
    if ($Title -match '^(?i)MRB FAIL:') { return 'FAIL' }
    return $null
}

function Select-BobBuildLoopPr {
    param($State, $Prs)
    $list = @($Prs)
    if ($State.currentSha) {
        $n = Get-BobBuildLoopShaNeedle $State.currentSha
        foreach ($p in $list) {
            $sha = ([string]$p.sha).ToLowerInvariant()
            if (-not $sha) { continue }
            if ($sha -eq $n.full -or $sha.StartsWith($n.short) -or $n.full.StartsWith($sha)) { return $p }
        }
    }
    if ($State.currentBranch) {
        foreach ($p in $list) {
            if ([string]$p.branch -eq [string]$State.currentBranch) { return $p }
        }
    }
    $seen = @()
    foreach ($u in @($State.seenPrs)) { $seen += [string]$u }
    $candidates = @()
    $issue = 0
    if ($State.issue) { $issue = [int]$State.issue }
    foreach ($p in $list) {
        $url = [string]$p.url
        if ($url -and ($url -match ' ')) { continue }
        if ($url -and ($seen -contains $url)) { continue }
        $created = [string]$p.createdAt
        $after = [string]$State.watchAfter
        if ($after -and $created -and ($created -lt $after)) { continue }
        $candidates += $p
    }
    if ($issue -gt 0) {
        $want = @($issue)
        if ($State.priorMrbIssue) {
            try { $want += [int]$State.priorMrbIssue } catch { }
        }
        $named = @()
        foreach ($p in $candidates) {
            $t = [string]$p.title
            foreach ($w in $want) {
                if ($t -match "(?i)issue\s*#$w\b" -or $t -match "#$w\b") {
                    $named += $p
                    break
                }
            }
        }
        if ($named.Count -gt 0) { $candidates = $named }
        else { return $null }
    }
    if ($candidates.Count -eq 0) { return $null }
    return $candidates | Sort-Object { [string]$_.createdAt } | Select-Object -Last 1
}

function Select-BobBuildLoopMrbIssue {
    param($State, $Issues)
    foreach ($i in @($Issues)) {
        if (Test-BobMrbTitleMatch -Title ([string]$i.title) -Sha ([string]$State.currentSha)) {
            return $i
        }
    }
    return $null
}

function Test-BobBuildLoopNoArtifact {
    param($State, $World)
    if ($State.startError) { return $true }
    $job = $World.Job
    if ($job -and [string]$job.startError) { return $true }
    if ($job -and $null -ne $job.started -and $job.started -eq $false) { return $true }

    $hasPid = $false
    $pidVal = $null
    if ($State.currentPid) { $hasPid = $true; $pidVal = $State.currentPid }
    elseif ($job -and $job.pid) { $hasPid = $true; $pidVal = $job.pid }

    if ($hasPid) {
        if ($World.PSObject.Properties['ProcessAlive'] -and $World.ProcessAlive -eq $false) { return $true }
        return $false
    }

    $fuel = [string]$State.fuel
    if ($fuel -eq 'cursor-models') {
        if (-not $job) { return $true }
        $cs = [string]$job.completionStatus
        if ($cs -and $cs -ne 'ok') { return $true }
        $st = [string]$job.state
        if ($st -in @('failed', 'blocked', 'stopped')) { return $true }
        return $false
    }

    if ($job -and [string]$job.lane -eq 'outbox') {
        $st = [string]$job.state
        $cs = [string]$job.completionStatus
        if ($st -in @('failed', 'blocked', 'stopped')) { return $true }
        if ($cs -and $cs -ne 'ok') { return $true }
        if ($st -eq 'done' -or $cs -eq 'ok') { return $true }
    }
    return $false
}

function New-BobBuildLoopDecision {
    param(
        [Parameter(Mandatory)][string]$Action,
        [hashtable]$Patch,
        $Backlink,
        $Pass,
        [string]$Goal,
        [string]$Stdout,
        [string]$Reason,
        [string]$Kind
    )
    return [pscustomobject]@{
        action  = $Action
        patch   = $Patch
        backlink = $Backlink
        pass    = $Pass
        goal    = $Goal
        stdout  = $Stdout
        reason  = $Reason
        kind    = $Kind
    }
}

function Get-BobBuildLoopPassStdout {
    param($State, $Mrb)
    $sha = [string]$State.currentSha
    $pr = [string]$State.currentPr
    $n = $(if ($Mrb -and $Mrb.number) { $Mrb.number } else { '' })
    $url = $(if ($Mrb -and $Mrb.url) { [string]$Mrb.url } else { [string]$State.lastMrb })
    return "DONE: MRB PASS-nits issue #$n SHA $sha PR $pr $url"
}

function Get-BobBuildLoopRetryOrFail {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Reason
    )
    $attempts = 0
    if ($State.jobAttempts) { $attempts = [int]$State.jobAttempts }
    $max = 3
    if ($State.maxJobRetries) { $max = [int]$State.maxJobRetries }
    if ($attempts -ge $max) {
        $msg = "FAILED: exhausted $max $Kind attempts: $Reason"
        return New-BobBuildLoopDecision -Action fail -Patch @{
            phase      = 'failed'
            failReason = $msg
        } -Stdout $msg -Reason $Reason -Kind $Kind
    }
    return New-BobBuildLoopDecision -Action retry_job -Reason $Reason -Kind $Kind
}

function Get-BobBuildLoopDecision {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$World
    )
    $phase = [string]$State.phase
    if ($phase -eq 'pass') {
        return New-BobBuildLoopDecision -Action pass -Stdout (Get-BobBuildLoopPassStdout -State $State -Mrb $null)
    }
    if ($phase -eq 'failed') {
        $msg = [string]$State.failReason
        if (-not $msg) { $msg = 'FAILED: loop already failed' }
        return New-BobBuildLoopDecision -Action fail -Stdout $msg
    }

    $pr = Select-BobBuildLoopPr -State $State -Prs $World.Prs
    $mrb = $null
    if ($phase -eq 'wait_mrb' -or $State.currentSha) {
        $mrb = Select-BobBuildLoopMrbIssue -State $State -Issues $World.Issues
    }

    switch ($phase) {
        'idle' {
            if ($State.currentSha) {
                return New-BobBuildLoopDecision -Action start_mrb -Patch @{
                    currentKind = 'mrb'
                } -Kind 'mrb'
            }
            return New-BobBuildLoopDecision -Action start_build -Patch @{
                currentKind = 'build'
            } -Goal (New-BobBuildGoal -State $State) -Kind 'build'
        }
        'wait_pr' {
            if ($pr) {
                $seen = @()
                foreach ($u in @($State.seenPrs)) { $seen += [string]$u }
                $url = [string]$pr.url
                if ($url -and ($seen -notcontains $url)) { $seen += $url }
                $backlink = $null
                if ($State.priorMrbIssue) {
                    $backlink = [pscustomobject]@{
                        issue = [int]$State.priorMrbIssue
                        body  = (New-BobFixPrComment -Url $url -Sha ([string]$pr.sha))
                    }
                }
                return New-BobBuildLoopDecision -Action start_mrb -Patch @{
                    currentKind   = 'mrb'
                    currentSha    = [string]$pr.sha
                    currentPr     = $url
                    currentBranch = [string]$pr.branch
                    jobAttempts   = 0
                    seenPrs       = $seen
                } -Backlink $backlink -Kind 'mrb'
            }
            if (Test-BobBuildLoopNoArtifact -State $State -World $World) {
                return Get-BobBuildLoopRetryOrFail -State $State -Kind 'build' -Reason 'PR worker exited without a PR'
            }
            return New-BobBuildLoopDecision -Action sleep
        }
        'wait_mrb' {
            if ($mrb) {
                $verdict = Get-BobMrbVerdictFromTitle ([string]$mrb.title)
                $passRow = [pscustomobject]@{
                    sha     = [string]$State.currentSha
                    pr      = [string]$State.currentPr
                    mrb     = [string]$mrb.url
                    verdict = $verdict
                    issue   = [int]$mrb.number
                }
                $backlink = $null
                if ($State.priorMrbIssue -and ([int]$State.priorMrbIssue -ne [int]$mrb.number)) {
                    $backlink = [pscustomobject]@{
                        issue = [int]$State.priorMrbIssue
                        body  = (New-BobMrbBacklinkComment -Url ([string]$mrb.url) -Sha ([string]$State.currentSha))
                    }
                }
                if ($verdict -eq 'PASS-nits') {
                    return New-BobBuildLoopDecision -Action pass -Patch @{
                        phase       = 'pass'
                        lastMrb     = [string]$mrb.url
                        jobAttempts = 0
                    } -Pass $passRow -Backlink $backlink -Stdout (Get-BobBuildLoopPassStdout -State $State -Mrb $mrb)
                }
                if ($verdict -eq 'FAIL') {
                    $fails = 0
                    if ($State.mrbFails) { $fails = [int]$State.mrbFails }
                    $maxFails = 8
                    if ($State.maxMrbFails) { $maxFails = [int]$State.maxMrbFails }
                    if ($fails -ge $maxFails) {
                        $msg = "FAILED: exhausted $maxFails MRB FAIL cycles"
                        return New-BobBuildLoopDecision -Action fail -Patch @{
                            phase      = 'failed'
                            failReason = $msg
                            lastMrb    = [string]$mrb.url
                        } -Pass $passRow -Backlink $backlink -Stdout $msg
                    }
                    $fixes = Get-BobMrbRequiredFixes ([string]$mrb.body)
                    $goal = New-BobFixGoal -MrbUrl ([string]$mrb.url) -Fixes $fixes
                    return New-BobBuildLoopDecision -Action start_fix -Patch @{
                        currentKind   = 'build'
                        priorMrbIssue = [int]$mrb.number
                        lastMrb       = [string]$mrb.url
                        requiredFixes = $fixes
                        jobAttempts   = 0
                        mrbFails      = ($fails + 1)
                        currentSha    = $null
                        currentPr     = $null
                        currentPid    = $null
                        currentJobId  = $null
                        currentBranch = $null
                        watchAfter    = [DateTime]::UtcNow.ToString('o')
                    } -Pass $passRow -Backlink $backlink -Goal $goal -Kind 'build'
                }
            }
            if (Test-BobBuildLoopNoArtifact -State $State -World $World) {
                return Get-BobBuildLoopRetryOrFail -State $State -Kind 'mrb' -Reason 'MRB worker exited without an MRB issue'
            }
            return New-BobBuildLoopDecision -Action sleep
        }
        default {
            return New-BobBuildLoopDecision -Action fail -Patch @{
                phase      = 'failed'
                failReason = "FAILED: unknown phase $phase"
            } -Stdout "FAILED: unknown phase $phase"
        }
    }
}

function Merge-BobBuildLoopPatch {
    param($State, $Patch)
    if (-not $Patch) { return $State }
    foreach ($k in @($Patch.Keys)) {
        $State | Add-Member -NotePropertyName $k -NotePropertyValue $Patch[$k] -Force
    }
    return $State
}

function Add-BobBuildLoopPass {
    param($State, $Pass)
    if (-not $Pass) { return $State }
    $passes = @($State.passes)
    $passes += $Pass
    $State | Add-Member -NotePropertyName passes -NotePropertyValue @($passes) -Force
    return $State
}

function Test-BobBuildLoopPidAlive {
    param($ProcessId)
    if (-not $ProcessId) { return $null }
    try {
        Get-Process -Id ([int]$ProcessId) -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Write-BobBuildLoopLog {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message
    )
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $line = '{0:o} {1}' -f [DateTime]::UtcNow, $Message
    try {
        Add-Content -LiteralPath $Path -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        try {
            $alt = $Path + '.' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.log'
            Add-Content -LiteralPath $alt -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch { }
    }
}
