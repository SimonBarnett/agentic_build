# Close superseded open PRs and stale MRB/issue noise so GitHub lists stay current.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [int[]]$ProtectPrNumbers = @(),
    [switch]$SkipIssueClose,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path $MyInvocation.MyCommand.Path }
. (Join-Path $here 'Bob-BuildLoop.ps1')
. (Join-Path $here 'Bob-Gh.ps1')

$gh = Get-BobGhExe
if (-not $gh) { throw 'gh.exe not found' }

$closed = New-Object System.Collections.Generic.List[string]
$protect = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($n in @($ProtectPrNumbers)) {
    if ($n -gt 0) { [void]$protect.Add([int]$n) }
}

$bridge = Join-Path $env:USERPROFILE '.grok\bob-bridge\loops'
$repoLeaf = ($Repo -split '/')[-1]
$mergedWinners = New-Object 'System.Collections.Generic.HashSet[int]'
if (Test-Path $bridge) {
    Get-ChildItem -Path $bridge -Filter "*_${repoLeaf}-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $b = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ([string]$b.repo -ne $Repo) { return }
            if ($b.currentPr) {
                $pn = Get-BobGhPrNumberFromUrl ([string]$b.currentPr)
                if ($pn -gt 0) {
                    $ph = [string]$b.phase
                    if ($ph -and $ph -notin @('pass', 'failed')) {
                        [void]$protect.Add($pn)
                    }
                    if ($ph -eq 'pass') {
                        [void]$mergedWinners.Add($pn)
                    }
                }
            }
        }
        catch { }
    }
}

if (-not $SkipIssueClose) {
    $issueScript = Join-Path $here 'Close-BobMrbPassedIssues.ps1'
    if (Test-Path $issueScript) {
        $ic = @()
        if ($WhatIf) { $ic = & $issueScript -Repo $Repo -WhatIf 2>&1 }
        else { $ic = & $issueScript -Repo $Repo 2>&1 }
        foreach ($line in @($ic)) { [void]$closed.Add([string]$line) }
    }
}

$mrbRaw = & $gh issue list --repo $Repo --label mrb-pass --state all --limit 100 --json body 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $mrbRaw.Trim()) {
    foreach ($row in @(ConvertFrom-BobGhJsonList $mrbRaw)) {
        $u = Get-BobMrbPrUrlFromBody ([string]$row.body)
        if (-not $u) { continue }
        $pn = Get-BobGhPrNumberFromUrl $u
        if ($pn -gt 0 -and (Test-BobGhPrIsMerged -Gh $gh -Repo $Repo -PrNumber $pn)) {
            [void]$mergedWinners.Add($pn)
        }
    }
}

function Get-BobPrIssueKey {
    param([string]$Title, [string]$Branch)
    if ($Title -match '(?i)issue\s*#(\d+)') { return ('issue:{0}' -f $Matches[1]) }
    if ($Title -match '\(#(\d+)\)') { return ('issue:{0}' -f $Matches[1]) }
    if ($Title -match '(?i)#(\d+)\b') { return ('issue:{0}' -f $Matches[1]) }
    if ($Branch -match '(?i)issue-(\d+)') { return ('issue:{0}' -f $Matches[1]) }
    if ($Branch -match '(?i)-i(\d+)(?:$|[-/])') { return ('issue:{0}' -f $Matches[1]) }
    return $null
}

$prRaw = & $gh pr list --repo $Repo --state open --limit 100 --json number,title,headRefName 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "gh pr list failed: $prRaw" }
$openPrs = @(ConvertFrom-BobGhJsonList $prRaw)

$byKey = @{}
foreach ($p in $openPrs) {
    $n = [int]$p.number
    $key = Get-BobPrIssueKey -Title ([string]$p.title) -Branch ([string]$p.headRefName)
    if (-not $key) { $key = ('branch:{0}' -f ([string]$p.headRefName).ToLowerInvariant()) }
    if (-not $byKey.ContainsKey($key)) { $byKey[$key] = New-Object System.Collections.Generic.List[int] }
    [void]$byKey[$key].Add($n)
}

foreach ($k in @($byKey.Keys)) {
    $nums = @($byKey[$k] | Sort-Object -Descending)
    if ($nums.Count -le 1) { continue }
    [void]$protect.Add([int]$nums[0])
}

function Invoke-BobGhClosePrWithComment {
    param(
        [Parameter(Mandatory)][string]$Gh,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][int]$PrNumber,
        [Parameter(Mandatory)][string]$Comment
    )
    if ($PrNumber -le 0) { return [pscustomobject]@{ ok = $true } }
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Gh pr close $PrNumber --repo $Repo --comment $Comment 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ ok = $false; message = $out.Trim() }
        }
        return [pscustomobject]@{ ok = $true }
    }
    finally {
        $ErrorActionPreference = $savedEap
    }
}

foreach ($p in $openPrs) {
    $n = [int]$p.number
    if ($protect.Contains($n)) { continue }

    $key = Get-BobPrIssueKey -Title ([string]$p.title) -Branch ([string]$p.headRefName)
    $reason = $null

    if ($key -and $byKey.ContainsKey($key)) {
        $nums = @($byKey[$key] | Sort-Object -Descending)
        if ($nums.Count -gt 1 -and $n -ne $nums[0]) {
            $reason = ('Superseded by newer open PR #{0} for {1}.' -f $nums[0], $key)
        }
    }

    if (-not $reason -and $key -and $key -match '^issue:(\d+)$') {
        $issueNum = [int]$Matches[1]
        $st = & $gh issue view $issueNum --repo $Repo --json state -q .state 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $st.Trim() -eq 'CLOSED') {
            $winner = @($mergedWinners | Sort-Object -Descending | Select-Object -First 1)
            if ($winner.Count -eq 0 -or $n -ne $winner[0]) {
                $reason = ('Feature issue #{0} is closed; this PR is stale.' -f $issueNum)
            }
        }
    }

    if (-not $reason) { continue }

    if ($WhatIf) {
        [void]$closed.Add(('would close PR #{0}: {1}' -f $n, $reason))
        continue
    }
    $r = Invoke-BobGhClosePrWithComment -Gh $gh -Repo $Repo -PrNumber $n -Comment $reason
    if ($r.ok) { [void]$closed.Add(('closed PR #{0}' -f $n)) }
    else { [void]$closed.Add(('FAILED PR #{0}: {1}' -f $n, $r.message)) }
}

$closed | ForEach-Object { Write-Output $_ }
Write-Output ('done: {0} actions' -f $closed.Count)
