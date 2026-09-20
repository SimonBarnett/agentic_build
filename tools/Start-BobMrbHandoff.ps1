# Bob hands off a hostile MRB. Does not write the review in this session.
# Default fuel: cursor-models while remaining > 0, then grok-build.
# Copilot only with -AllowCopilot. Never Other Models.
[CmdletBinding()]
param(
    [int]$Issue,
    [string]$Repo = 'SimonBarnett/agentic_build',
    [string]$Sha,
    [string]$Docs,
    [string]$Plan,
    [string]$Cwd,
    [ValidateSet('cursor-models', 'grok-build')][string]$Fuel = 'cursor-models',
    [switch]$AllowCopilot,
    # Test-Pack only (see cursor-mrb-dev): inject picker result; skip live cursor-agent.
    [object]$TestGitWorkerResult,
    [switch]$TestSkipCursor
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'Bob-Gh.ps1')

if ($TestSkipCursor) {
    if ($Fuel -ne 'grok-build') {
        throw "TestSkipCursor is Test-Pack only and requires -Fuel grok-build (got '$Fuel')."
    }
    if (-not $PSBoundParameters.ContainsKey('TestGitWorkerResult')) {
        throw 'TestSkipCursor requires -TestGitWorkerResult (Test-Pack only).'
    }
}

$repoRoot = Split-Path $here -Parent
Import-Module (Join-Path $repoRoot 'src\BobBridge.psd1') -Force

function Assert-BobMrbWorkerCanPost {
    param(
        [Parameter(Mandatory)][string]$WorkerMachine
    )
    $thisId = Get-ThisMachineId
    if (-not $thisId) {
        throw 'MRB handoff preflight: cannot resolve this machine identity (set BOB_MACHINE_ID or machine.json). Refusing before spending Cursor/Grok on the review.'
    }
    $worker = ([string]$WorkerMachine).Trim().ToLowerInvariant()
    if ($worker -and ($worker -ne $thisId)) {
        throw "MRB handoff preflight: cannot verify worker '$WorkerMachine' can post to $Repo. Run the handoff on that machine or fix fleet gh readiness (issue #11)."
    }
}

$issueUrl = $(if ($Issue) { "https://github.com/$Repo/issues/$Issue" } else { "https://github.com/$Repo" })
$shaLine = $(if ($Sha) { "SHA $Sha. Review that commit only. Do not stage or commit unrelated dirty files in the checkout." } else { 'HEAD of origin/main on the product repo. Do not stage or commit unrelated dirty files in the checkout.' })
$mrbPostShaLine = $(if ($Sha) { "When you post the verdict, call tools/Start-BobMrb.ps1 with -Sha $Sha so the issue title carries that commit." } else { '' })
$docsLine = $(if ($Docs) { $Docs } else { 'docs/feature-request-*.md' })
$planLine = $(if ($Plan) { $Plan } else { 'docs/build-and-test-plan*.md' })

$prompt = @"
Hostile MRB of $issueUrl. Follow skill bob-hostile-mrb and the transaction in bob-build-loop (https://github.com/SimonBarnett/agentic_build .grok/skills).

$shaLine This is a PR head. Diff vs $docsLine and $planLine (and the parked PDF if one was supplied).
$mrbPostShaLine

Walk missing features: this FR's red acceptance = Required fixes on the MRB issue; unspecified holes / issues with no intake doc = park via bob-spec-intake (issue + markdown) and list under Missing features. Do not implement missing features in the MRB job.

Post a GitHub issue on $Repo titled 'MRB FAIL|PASS-nits: <slug> <sha>' with labels mrb + mrb-fail or mrb-pass. Body: Verdict, Feature request, Missing features, Blockers, Nits, Evidence, Required fixes, PR. No MRB PDF.

Verdict FAIL or PASS-nits only. Do not write the words ready for human UAT. Bob chairs that stamp.

PASS-nits: merge the PR (gh pr merge). Nits do not block the merge.
FAIL: do not merge. Required fixes only. Do not start the FIX worker yourself.

Work with Cursor Models (Cursor Grok / Composer) or grok.exe only. Do not use Other Models. Do not use Copilot. Do not burn Grok Bot weekly usage. Do not assign secrets in the issue (no password or XAI_API_KEY literals in git).
"@

if (-not $Cwd) {
    $leaf = ($Repo.Split('/')[-1])
    foreach ($c in @("C:\ai\$leaf", "D:\ai\$leaf", "C:\src\$leaf")) {
        if (Test-Path (Join-Path $c '.git')) { $Cwd = $c; break }
    }
}

$null = Test-BobGhIssuePosting -Repo $Repo

$enqueueFuel = $null

if ($Fuel -eq 'cursor-models' -and -not $TestSkipCursor) {
    $cursorModel = Get-BobJobModel -Kind mrb -Fuel 'cursor-models'
    $cursor = Join-Path $here 'Start-BobCursor.ps1'
    $r = & $cursor -Repo "https://github.com/$Repo" -Cwd $Cwd -Docs $Docs -Plan $Plan -Mrb $issueUrl -Goal $prompt -Kind mrb -Model $cursorModel
    if ($r.started) {
        $r | Add-Member -NotePropertyName handed -NotePropertyValue 'cursor-models' -Force
        return $r
    }
    Write-Warning "Cursor agent did not start ($($r.startError)); falling back to grok-build."
    $enqueueFuel = 'grok-build'
}
elseif ($Fuel -eq 'grok-build' -or $TestSkipCursor) {
    $enqueueFuel = 'grok-build'
}
else {
    throw "MRB handoff: unsupported fuel '$Fuel'."
}

if ($PSBoundParameters.ContainsKey('TestGitWorkerResult')) {
    $sel = $TestGitWorkerResult
}
else {
    $sel = Select-BobGitWorker -Fuel $enqueueFuel -AllowCopilot:$AllowCopilot -Repo "https://github.com/$Repo"
}
if ($sel.wait) {
    $why = "no eligible $enqueueFuel worker ($($sel.reason))"
    return [pscustomobject]@{
        ok         = $false
        started    = $false
        startError = $why
        jobId      = $null
        pid        = $null
        handed     = $enqueueFuel
    }
}
Assert-BobMrbWorkerCanPost -WorkerMachine ([string]$sel.machine)

if (-not $Cwd) { $Cwd = $repoRoot }
$mrbModel = Get-BobJobModel -Kind mrb -Fuel $enqueueFuel
$q = Start-BobBuild -Task git -Fuel $enqueueFuel -Kind mrb -Model $mrbModel -Machine $sel.machine -PinGitWorker -Cwd $Cwd -Goal $prompt -Repo "https://github.com/$Repo" -Docs $Docs -Plan $Plan -Mrb $issueUrl -AllowCopilot:$AllowCopilot
if (-not $q.ok -or $q.wait) {
    $why = $(if ($q.reason) { [string]$q.reason } else { 'enqueue refused' })
    return [pscustomobject]@{
        ok         = $false
        started    = $false
        startError = $why
        jobId      = $null
        pid        = $null
        handed     = $enqueueFuel
    }
}
$q | Add-Member -NotePropertyName handed -NotePropertyValue $enqueueFuel -Force
return $q
