# One-shot closer for finished MRB PASS-nits boards (issue #140 / FAIL #170).
# Fail-closed: requires a merged PR URL; never claims "merged" unless verified.
# Does not close unfinished FRs or FAIL boards that are still the live board.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$MergedPrUrl,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path $MyInvocation.MyCommand.Path }
. (Join-Path $here 'Bob-BuildLoop.ps1')
. (Join-Path $here 'Bob-Gh.ps1')

if (-not $Repo) { throw '-Repo is mandatory (no default; do not hard-code a sister repo)' }
if (-not $MergedPrUrl) { throw '-MergedPrUrl is mandatory' }

$prNum = 0
if ($MergedPrUrl -match '(?i)/pull/(\d+)') { $prNum = [int]$Matches[1] }
if ($prNum -le 0) { throw "MergedPrUrl must be a github.com/.../pull/N URL (got $MergedPrUrl)" }

$gh = Get-BobGhExe
if (-not $gh) { throw 'gh.exe not found' }

if (-not (Test-BobGhPrIsMerged -Gh $gh -Repo $Repo -PrNumber $prNum)) {
    throw "PR #$prNum on $Repo is not merged; refusing to close boards (fail-closed)"
}

$raw = & $gh issue list --repo $Repo --label mrb --state all --limit 100 --json number,title,state,body 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "gh issue list failed: $raw" }
$issues = @(ConvertFrom-BobGhJsonList $raw)

# Only OPEN PASS boards that name this merged PR in the body (this-FR scoping).
$passOpenForPr = New-Object System.Collections.Generic.List[object]
$slugsForPr = New-Object 'System.Collections.Generic.HashSet[string]'
$frToClose = New-Object 'System.Collections.Generic.HashSet[int]'
$failOpen = New-Object System.Collections.Generic.List[object]

foreach ($i in $issues) {
    $title = [string]$i.title
    $body = [string]$i.body
    $state = [string]$i.state
    $slug = Get-BobMrbTitleSlug $title
    if ($title -match '(?i)^MRB FAIL:') {
        if ($state -eq 'OPEN') { [void]$failOpen.Add($i) }
        continue
    }
    if ($title -notmatch '(?i)^MRB PASS-nits:') { continue }
    if ($state -ne 'OPEN') { continue }
    $bodyUrl = Get-BobMrbPrUrlFromBody $body
    $mentions = ($body -match [regex]::Escape($MergedPrUrl)) -or (
        $bodyUrl -and ($bodyUrl.TrimEnd('/') -eq $MergedPrUrl.TrimEnd('/'))
    ) -or ($body -match ("(?i)/pull/{0}\b" -f $prNum))
    if (-not $mentions) { continue }
    [void]$passOpenForPr.Add($i)
    if ($slug) { [void]$slugsForPr.Add($slug) }
    foreach ($n in Get-BobMrbFeatureIssueNumbers $body) {
        [void]$frToClose.Add([int]$n)
    }
}

if ($passOpenForPr.Count -eq 0) {
    Write-Output "done: 0 actions (no open PASS-nits board names $MergedPrUrl)"
    return
}

$commentPass = "Bulk close: MRB PASS-nits board after merge of $MergedPrUrl"
$commentFail = "Superseded by MRB PASS-nits for same feature after merge of $MergedPrUrl"
$commentFr = "Build loop: MRB PASS-nits recorded; closing FR after merge of $MergedPrUrl. Bob UAT stamp is separate."

$closed = New-Object System.Collections.Generic.List[string]

foreach ($p in $passOpenForPr) {
    $n = [int]$p.number
    if ($WhatIf) { [void]$closed.Add("would close PASS #$n"); continue }
    $r = Invoke-BobGhCloseIssueWithComment -Gh $gh -Repo $Repo -IssueNumber $n -Comment $commentPass
    if ($r.ok) { [void]$closed.Add("closed PASS #$n") }
    else { throw "close PASS #$n failed: $($r.message)" }
}

foreach ($f in $failOpen) {
    $slug = Get-BobMrbTitleSlug ([string]$f.title)
    if (-not $slug -or -not $slugsForPr.Contains($slug)) { continue }
    $n = [int]$f.number
    if ($WhatIf) { [void]$closed.Add("would close FAIL #$n ($slug)"); continue }
    $r = Invoke-BobGhCloseIssueWithComment -Gh $gh -Repo $Repo -IssueNumber $n -Comment $commentFail
    if ($r.ok) { [void]$closed.Add("closed FAIL #$n") }
    else { throw "close FAIL #$n failed: $($r.message)" }
}

foreach ($n in @($frToClose)) {
    if ($n -le 0) { continue }
    $viewRaw = & $gh issue view $n --repo $Repo --json state 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { continue }
    $st = $null
    try { $st = [string](($viewRaw | ConvertFrom-Json).state) } catch { $st = $null }
    if ($st -ne 'OPEN') { continue }
    if ($WhatIf) { [void]$closed.Add("would close FR #$n"); continue }
    $r = Invoke-BobGhCloseIssueWithComment -Gh $gh -Repo $Repo -IssueNumber $n -Comment $commentFr
    if ($r.ok) { [void]$closed.Add("closed FR #$n") }
    else { throw "close FR #$n failed: $($r.message)" }
}

$closed | ForEach-Object { Write-Output $_ }
Write-Output ("done: {0} actions" -f $closed.Count)
