# Bob hands off a hostile MRB. Does not write the review in this session.
# Default fuel: cursor-models, then grok-build. Copilot only with -AllowCopilot.
[CmdletBinding()]
param(
    [int]$Issue,
    [string]$Repo = 'SimonBarnett/agentic_build',
    [string]$Sha,
    [string]$Docs,
    [string]$Plan,
    [string]$Cwd,
    [ValidateSet('cursor-models', 'grok-build')][string]$Fuel = 'cursor-models',
    [switch]$AllowCopilot
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here 'Bob-Gh.ps1')

function Assert-BobMrbWorkerCanPost {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$WorkerMachine
    )
    $thisId = $null
    try {
        $repoRoot = Split-Path $here -Parent
        Import-Module (Join-Path $repoRoot 'src\BobBridge.psd1') -Force -ErrorAction Stop
        $thisId = Get-ThisMachineId
    }
    catch { }
    $worker = ([string]$WorkerMachine).Trim().ToLowerInvariant()
    if ($thisId -and $worker -and ($worker -ne $thisId)) {
        throw "MRB handoff preflight: cannot verify worker '$WorkerMachine' can post to $Repo. Run the handoff on that machine or fix fleet gh readiness (issue #11)."
    }
    $null = Test-BobGhIssuePosting -Repo $Repo
}

if ($Fuel -eq 'cursor-models') {
    $null = Test-BobGhIssuePosting -Repo $Repo
}

$issueUrl = $(if ($Issue) { "https://github.com/$Repo/issues/$Issue" } else { "https://github.com/$Repo" })
$shaLine = $(if ($Sha) { "SHA $Sha. Review that commit only. Do not stage or commit unrelated dirty files in the checkout." } else { 'HEAD of origin/main on the product repo. Do not stage or commit unrelated dirty files in the checkout.' })
$docsLine = $(if ($Docs) { $Docs } else { 'docs/feature-request-*.md' })
$planLine = $(if ($Plan) { $Plan } else { 'docs/build-and-test-plan*.md' })

$prompt = @"
Hostile MRB of $issueUrl. Follow skill bob-hostile-mrb (https://github.com/SimonBarnett/agentic_build .grok/skills).

$shaLine Diff vs $docsLine and $planLine (and the parked PDF if one was supplied).

Walk missing features: this FR's red acceptance = Required fixes on the MRB issue; unspecified holes / issues with no intake doc = park via bob-spec-intake (issue + markdown) and list under Missing features. Do not implement missing features in the MRB job.

Post a GitHub issue on $Repo titled 'MRB FAIL|PASS-nits: <slug> <sha>' with labels mrb + mrb-fail or mrb-pass. Body: Verdict, Feature request, Missing features, Blockers, Nits, Evidence, Required fixes. No MRB PDF.

Verdict FAIL or PASS-nits only. Do not write the words ready for human UAT. Bob chairs that stamp.

Work with Cursor Models or Grok Build only. Do not use Copilot. Do not burn Grok Bot weekly usage. Do not put password= or XAI_API_KEY= assignments in the issue.
"@

if (-not $Cwd) {
    $leaf = ($Repo.Split('/')[-1])
    foreach ($c in @("C:\ai\$leaf", "D:\ai\$leaf", "C:\src\$leaf")) {
        if (Test-Path (Join-Path $c '.git')) { $Cwd = $c; break }
    }
}

$repoRoot = Split-Path $here -Parent
Import-Module (Join-Path $repoRoot 'src\BobBridge.psd1') -Force
$mrbModel = Get-BobJobModel -Kind mrb -Fuel $Fuel

if ($Fuel -eq 'cursor-models') {
    $cursor = Join-Path $here 'Start-BobCursor.ps1'
    $r = & $cursor -Repo "https://github.com/$Repo" -Cwd $Cwd -Docs $Docs -Plan $Plan -Mrb $issueUrl -Goal $prompt -Kind mrb -Model $mrbModel
    if ($r.started) {
        $r | Add-Member -NotePropertyName handed -NotePropertyValue 'cursor-models' -Force
        return $r
    }
    Write-Warning "Cursor agent did not start ($($r.startError)); falling back to grok-build."
    $Fuel = 'grok-build'
    $mrbModel = Get-BobJobModel -Kind mrb -Fuel grok-build
}

$sel = Select-BobGitWorker -Fuel grok-build -AllowCopilot:$AllowCopilot -Repo "https://github.com/$Repo"
if ($sel.wait) {
    throw "MRB handoff preflight: no eligible grok-build worker ($($sel.reason)). Fix capacity before spending Grok on the review."
}
Assert-BobMrbWorkerCanPost -Repo $Repo -WorkerMachine ([string]$sel.machine)

if (-not $Cwd) { $Cwd = $repoRoot }
$q = Start-BobBuild -Task git -Fuel grok-build -Kind mrb -Model $mrbModel -Machine $sel.machine -Cwd $Cwd -Goal $prompt -Repo "https://github.com/$Repo" -Docs $Docs -Plan $Plan -AllowCopilot:$AllowCopilot
$q | Add-Member -NotePropertyName handed -NotePropertyValue 'grok-build' -Force
return $q
