# Post a lightweight MRB as a GitHub issue (no PDF).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][ValidateSet('FAIL', 'PASS-nits', 'PASS-UAT')][string]$Verdict,
    [Parameter(Mandatory)][string]$Body,
    [string]$Sha,
    [string]$FeatureIssue,
    [string]$BaseRef = 'main',
    [switch]$AllowPassUat
)

$ErrorActionPreference = 'Stop'

if ($Verdict -eq 'PASS-UAT' -and -not $AllowPassUat) {
    throw 'PASS-UAT is Bob chair only. Pass -AllowPassUat when stamping ready for human UAT.'
}

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

function Ensure-BobGhLabel {
    param(
        [Parameter(Mandatory)][string]$Gh,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Name,
        [string]$Color = 'ededed'
    )
    $out = & $Gh label create $Name --repo $Repo --color $Color --force 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { return }
    if ($out -match '(?i)already exists|name already exists') { return }
    $json = & $Gh label list --repo $Repo --limit 500 --json name 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $json) {
        $names = @($json | ConvertFrom-Json | ForEach-Object { [string]$_.name })
        if ($names -contains $Name) { return }
    }
    if ($out.Trim()) {
        Write-Warning "Ensure-BobGhLabel $Name on $Repo : $out"
    }
}

$gh = Get-BobGhExe
if (-not $gh) { throw 'gh.exe not found. winget install GitHub.cli ; gh auth login' }

$labels = @('mrb')
if ($Verdict -eq 'FAIL') { $labels += 'mrb-fail' }
else { $labels += 'mrb-pass' }

$fullTitle = "MRB ${Verdict}: $Title"
if ($Sha) { $fullTitle = "$fullTitle $Sha" }

$bodyText = $Body
if ($FeatureIssue) {
    $bodyText = "**Feature request:** $FeatureIssue`n`n" + $bodyText
}

foreach ($l in $labels) {
    $color = switch -Regex ($l) {
        'fail' { 'b60205'; break }
        'pass' { '0e8a16'; break }
        default { '5319e7' }
    }
    Ensure-BobGhLabel -Gh $gh -Repo $Repo -Name $l -Color $color
}

$labelArgs = @()
foreach ($l in $labels) { $labelArgs += @('--label', $l) }

$out = & $gh issue create --repo $Repo --title $fullTitle --body $bodyText @labelArgs
if ($LASTEXITCODE -ne 0) { throw "gh issue create failed: $out" }
[pscustomobject]@{ ok = $true; url = [string]$out; verdict = $Verdict; repo = $Repo; title = $fullTitle; sha = $Sha }
