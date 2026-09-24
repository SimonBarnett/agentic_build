# Close open MRB PASS-nits boards, their feature issues, and superseded MRB FAIL for the same slug.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo = 'SimonBarnett/agentic_irc',
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

$raw = & $gh issue list --repo $Repo --label mrb --state all --limit 100 --json number,title,state,body 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "gh issue list failed: $raw" }
$issues = @(ConvertFrom-BobGhJsonList $raw)

$passOpen = New-Object System.Collections.Generic.List[object]
$failOpen = New-Object System.Collections.Generic.List[object]
$passBodies = New-Object System.Collections.Generic.List[string]
$slugsWithPass = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($i in $issues) {
    $title = [string]$i.title
    $slug = Get-BobMrbTitleSlug $title
    if ($title -match '(?i)^MRB PASS-nits:') {
        if ($slug) { [void]$slugsWithPass.Add($slug) }
        if ([string]$i.state -eq 'OPEN') { [void]$passOpen.Add($i) }
        [void]$passBodies.Add([string]$i.body)
    }
    elseif ($title -match '(?i)^MRB FAIL:') {
        if ([string]$i.state -eq 'OPEN') { [void]$failOpen.Add($i) }
    }
}

$frToClose = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($body in $passBodies) {
    foreach ($n in Get-BobMrbFeatureIssueNumbers $body) {
        [void]$frToClose.Add($n)
    }
}

$bridge = Join-Path $env:USERPROFILE '.grok\bob-bridge\loops'
$repoLeaf = ($Repo -split '/')[-1]
if (Test-Path $bridge) {
    Get-ChildItem -Path $bridge -Filter "*_${repoLeaf}-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $b = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ([string]$b.repo -ne $Repo) { return }
            if ([string]$b.phase -eq 'pass' -and $b.issue) {
                [void]$frToClose.Add([int]$b.issue)
            }
        }
        catch { }
    }
}

$closed = New-Object System.Collections.Generic.List[string]

foreach ($p in $passOpen) {
    $n = [int]$p.number
    $msg = 'Bulk close: MRB PASS-nits board (merged).'
    if ($WhatIf) { [void]$closed.Add("would close PASS #$n"); continue }
    $r = Invoke-BobGhCloseIssueWithComment -Gh $gh -Repo $Repo -IssueNumber $n -Comment $msg
    if ($r.ok) { [void]$closed.Add("closed PASS #$n") }
}

foreach ($f in $failOpen) {
    $slug = Get-BobMrbTitleSlug ([string]$f.title)
    if (-not $slug -or -not $slugsWithPass.Contains($slug)) { continue }
    $n = [int]$f.number
    if ($WhatIf) { [void]$closed.Add("would close FAIL #$n ($slug)"); continue }
    $r = Invoke-BobGhCloseIssueWithComment -Gh $gh -Repo $Repo -IssueNumber $n -Comment 'Superseded by MRB PASS-nits for same feature.'
    if ($r.ok) { [void]$closed.Add("closed FAIL #$n") }
}

foreach ($n in @($frToClose)) {
    if ($n -le 0) { continue }
    $state = & $gh issue view $n --repo $Repo --json state -q .state 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $state.Trim() -ne 'OPEN') { continue }
    if ($WhatIf) { [void]$closed.Add("would close FR #$n"); continue }
    $r = Invoke-BobGhCloseIssueWithComment -Gh $gh -Repo $Repo -IssueNumber $n -Comment 'Build loop: MRB PASS-nits recorded; closing FR. Bob UAT stamp is separate.'
    if ($r.ok) { [void]$closed.Add("closed FR #$n") }
}

$closed | ForEach-Object { Write-Output $_ }
Write-Output ("done: {0} actions" -f $closed.Count)
