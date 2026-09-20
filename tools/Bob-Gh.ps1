# Shared gh.exe discovery and MRB posting preflight (dot-sourced by Start-BobMrb*.ps1).
$ErrorActionPreference = 'Stop'

function Get-BobGhExe {
    if ($env:BOB_GH_EXE) {
        if (Test-Path -LiteralPath $env:BOB_GH_EXE) { return $env:BOB_GH_EXE }
        return $null
    }
    foreach ($c in @(
            (Join-Path ${env:ProgramFiles} 'GitHub CLI\gh.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe'),
            (Join-Path $env:LOCALAPPDATA 'GitHubCLI\gh.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
        )) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $cmd = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Test-BobGhIssuePosting {
    param(
        [Parameter(Mandatory)][string]$Repo
    )
    $gh = Get-BobGhExe
    if (-not $gh) {
        throw 'MRB handoff preflight: gh.exe not found (winget install GitHub.cli). Fix GitHub CLI before spending Cursor/Grok on the review.'
    }
    & $gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'MRB handoff preflight: gh auth login required on this worker (or set GH_TOKEN / GITHUB_TOKEN with issues:write). Fail here before starting the reasoning model.'
    }
    $null = & $gh repo view $Repo --json name -q .name 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "MRB handoff preflight: cannot read repo $Repo with current gh auth (need issues:write). Fail here before starting the reasoning model."
    }
    return $gh
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
    if ($env:BOB_FAKE_GH_QUIET -ne '1') {
        if ($out.Trim()) {
            Write-Warning "Set-BobGhLabelReady $Name on $Repo : $out"
        }
        else {
            Write-Warning "Set-BobGhLabelReady $Name on $Repo : label create failed (exit $createExit)"
        }
    }
    return $false
}
