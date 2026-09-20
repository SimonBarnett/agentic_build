# Post a lightweight MRB as a GitHub issue (no PDF).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][ValidateSet('FAIL', 'PASS-nits', 'PASS-UAT')][string]$Verdict,
    [Parameter(Mandatory)][string]$Body,
    [string]$FeatureIssue,
    [string]$BaseRef = 'main'
)

$ErrorActionPreference = 'Stop'

function Get-BobGhExe {
    foreach ($c in @(
            (Join-Path ${env:ProgramFiles} 'GitHub CLI\gh.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe'),
            (Join-Path $env:LOCALAPPDATA 'GitHubCLI\gh.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
        )) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $cmd = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$gh = Get-BobGhExe
if (-not $gh) { throw 'gh.exe not found. winget install GitHub.cli ; gh auth login' }

$labels = @('mrb')
if ($Verdict -eq 'FAIL') { $labels += 'mrb-fail' }
else { $labels += 'mrb-pass' }

$fullTitle = "MRB ${Verdict}: $Title"
$bodyText = $Body
if ($FeatureIssue) {
    $bodyText = "**Feature request:** $FeatureIssue`n`n" + $bodyText
}

$labelArgs = @()
foreach ($l in $labels) { $labelArgs += @('--label', $l) }

$out = & $gh issue create --repo $Repo --title $fullTitle --body $bodyText @labelArgs
if ($LASTEXITCODE -ne 0) { throw "gh issue create failed: $out" }
[pscustomobject]@{ ok = $true; url = [string]$out; verdict = $Verdict; repo = $Repo }
