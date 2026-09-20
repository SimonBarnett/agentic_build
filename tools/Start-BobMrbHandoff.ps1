# Bob hands off a hostile MRB. Does not write the review in this session.
# Default: GitHub issue @copilot (start-bob-copilot). -Fleet uses Start-BobBuild -Task git.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Issue,
    [string]$Repo = 'SimonBarnett/agentic_build',
    [string]$Sha,
    [string]$Docs,
    [string]$Plan,
    [string]$Cwd,
    [switch]$Fleet
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$issueUrl = "https://github.com/$Repo/issues/$Issue"
$shaLine = $(if ($Sha) { "SHA $Sha." } else { 'HEAD of the product repo.' })
$docsLine = $(if ($Docs) { $Docs } else { 'docs/feature-request-*.md' })
$planLine = $(if ($Plan) { $Plan } else { 'docs/build-and-test-plan.md' })

$prompt = @"
Hostile MRB on $issueUrl. Follow skill bob-hostile-mrb (https://github.com/SimonBarnett/agentic_build .grok/skills).

$shaLine Diff vs $docsLine and $planLine.

Walk missing features: this FR's red acceptance = Required fixes on this issue; unspecified holes / issues with no intake doc = park via bob-spec-intake (issue + markdown) and list under Missing features. Do not implement missing features in the MRB job.

Post with tools/Start-BobMrb.ps1 (or gh issue comment on $issueUrl). Body: Verdict, Feature request, Missing features, Blockers, Nits, Evidence, Required fixes. No MRB PDF.

Verdict FAIL or PASS-nits only. Do not write the words ready for human UAT. Bob chairs that stamp.

Do not burn Grok Bot weekly usage. Do not put password= or XAI_API_KEY= assignments in the issue.
"@

if (-not $Fleet) {
    $copilot = Join-Path $here 'Start-BobCopilot.ps1'
    try {
        $r = & $copilot -Issue $Issue -Repo $Repo -CustomInstructions $prompt
        $r | Add-Member -NotePropertyName handed -NotePropertyValue 'copilot' -Force
        return $r
    }
    catch {
        Write-Warning "Copilot handoff failed ($($_.Exception.Message)); trying fleet git-task."
        $Fleet = $true
    }
}

$repoRoot = Split-Path $here -Parent
$psd1 = Join-Path $repoRoot 'src\BobBridge.psd1'
Import-Module $psd1 -Force
if (-not $Cwd) { $Cwd = $repoRoot }
$q = Start-BobBuild -Task git -Cwd $Cwd -Goal $prompt -Repo "https://github.com/$Repo" -Mrb $issueUrl -Docs $Docs -Plan $Plan
$q | Add-Member -NotePropertyName handed -NotePropertyValue 'fleet' -Force
return $q
