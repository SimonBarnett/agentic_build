# Shared gh.exe discovery and MRB posting preflight (dot-sourced by Start-BobMrb*.ps1).
$ErrorActionPreference = 'Stop'

$bobGhPrivate = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Private\Get-BobGh.ps1'
if (-not (Test-Path -LiteralPath $bobGhPrivate)) {
    throw "missing $bobGhPrivate"
}
. $bobGhPrivate

function Test-BobGhIssuePosting {
    param(
        [Parameter(Mandatory)][string]$Repo
    )
    $snap = Get-BobGhPostingReadiness -Repo $Repo
    if (-not $snap.present) {
        throw 'MRB handoff preflight: gh.exe not found (winget install GitHub.cli). Fix GitHub CLI before spending Cursor/Grok on the review.'
    }
    if (-not $snap.authenticated) {
        throw 'MRB handoff preflight: gh auth login required on this worker (or set GH_TOKEN / GITHUB_TOKEN with issues:write and pull_requests:write). Fail here before starting the MRB agent.'
    }
    if (-not $snap.issue_posting_ready) {
        throw "MRB handoff preflight: cannot read repo $(Get-BobProductRepo -Repo $Repo) with current gh auth (need issues:write and pull_requests:write). Fail here before starting the MRB agent."
    }
    return Get-BobGhExe
}

function Set-BobGhLabelReady {
    param(
        [Parameter(Mandatory)][string]$Gh,
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Name,
        [string]$Color = 'ededed'
    )
    $out = & $Gh label create $Name --repo $Repo --color $Color --force 2>&1 | Out-String
    $createExit = $LASTEXITCODE
    if ($createExit -eq 0) { return $true }
    if ($out -match '(?i)already exists|name already exists') { return $true }
    $json = & $Gh label list --repo $Repo --limit 500 --json name 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $json) {
        $names = @($json | ConvertFrom-Json | ForEach-Object { [string]$_.name })
        if ($names -contains $Name) { return $true }
    }
    if ($out.Trim()) {
        Write-Warning "Set-BobGhLabelReady $Name on $Repo : $out"
    }
    else {
        Write-Warning "Set-BobGhLabelReady $Name on $Repo : label create failed (exit $createExit)"
    }
    return $false
}
