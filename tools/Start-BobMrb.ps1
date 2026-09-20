# Post a lightweight MRB as a GitHub issue (no PDF).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][ValidateSet('FAIL', 'PASS-nits', 'PASS-UAT')][string]$Verdict,
    [Parameter(Mandatory)][string]$Body,
    [string]$Sha,
    [string]$FeatureIssue,
    [switch]$AllowPassUat
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bob-Gh.ps1')

if ($Verdict -eq 'PASS-UAT' -and -not $AllowPassUat) {
    throw 'PASS-UAT is Bob chair only. Pass -AllowPassUat when stamping ready for human UAT.'
}

$gh = Get-BobGhExe
if (-not $gh) { throw 'gh.exe not found. winget install GitHub.cli ; gh auth login' }

$wantedLabels = @('mrb')
if ($Verdict -eq 'FAIL') { $wantedLabels += 'mrb-fail' }
else { $wantedLabels += 'mrb-pass' }

$appliedLabels = New-Object System.Collections.Generic.List[string]
$droppedLabels = New-Object System.Collections.Generic.List[string]
foreach ($l in $wantedLabels) {
    $color = switch -Regex ($l) {
        'fail' { 'b60205'; break }
        'pass' { '0e8a16'; break }
        default { '5319e7' }
    }
    if (Set-BobGhLabelReady -Gh $gh -Repo $Repo -Name $l -Color $color) {
        [void]$appliedLabels.Add($l)
    }
    else {
        [void]$droppedLabels.Add($l)
    }
}

$fullTitle = "MRB ${Verdict}: $Title"
if ($Sha) { $fullTitle = "$fullTitle $Sha" }

$bodyText = $Body
if ($FeatureIssue) {
    $bodyText = "**Feature request:** $FeatureIssue`n`n" + $bodyText
}
if ($droppedLabels.Count -gt 0) {
    $dropNote = '**Labels not applied (create failed):** ' + ($droppedLabels -join ', ')
    $bodyText = "$dropNote`n`n" + $bodyText
}

$bodyPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), ('bob-mrb-body-' + [guid]::NewGuid().ToString('N') + '.md'))
try {
    [IO.File]::WriteAllText($bodyPath, $bodyText, [System.Text.UTF8Encoding]::new($false))
    $labelArgs = @()
    foreach ($l in $appliedLabels) { $labelArgs += @('--label', $l) }
    $out = & $gh issue create --repo $Repo --title $fullTitle --body-file $bodyPath @labelArgs
    if ($LASTEXITCODE -ne 0) { throw "gh issue create failed: $out" }
}
finally {
    if (Test-Path -LiteralPath $bodyPath) { Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue }
}

[pscustomobject]@{
    ok             = $true
    url            = [string]$out
    verdict        = $Verdict
    repo           = $Repo
    title          = $fullTitle
    sha            = $Sha
    labelsApplied  = @($appliedLabels)
    labelsDropped  = @($droppedLabels)
}
