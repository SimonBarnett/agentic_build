# Shared gh.exe discovery and MRB posting preflight (dot-sourced by Start-BobMrb*.ps1).
# Get-BobGhExe / Get-BobGhPostingReadiness live in src/Private/Get-BobGh.ps1 (issue #11 / #34).
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'src\Private\Get-BobGh.ps1')

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
        throw 'MRB handoff preflight: gh auth login required on this worker (or set GH_TOKEN / GITHUB_TOKEN with issues:write and pull_requests:write). Fail here before starting the MRB agent.'
    }
    $null = & $gh repo view $Repo --json name -q .name 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "MRB handoff preflight: cannot read repo $Repo with current gh auth (need issues:write and pull_requests:write). Fail here before starting the MRB agent."
    }
    return $gh
}

function Get-BobMrbTitleSlug {
    param([string]$Title)
    if (-not $Title) { return $null }
    if ($Title -notmatch '^(?i)MRB (?:FAIL|PASS-nits):\s+(.+?)\s+[0-9a-f]{7,40}\s*$') { return $null }
    return $Matches[1].Trim().ToLowerInvariant()
}

function Get-BobMrbPrUrlFromBody {
    param([string]$Body)
    if (-not $Body) { return $null }
    if ($Body -match '(?is)##\s+PR\s+[\r\n]+\s*(https://github\.com/[^\s]+/pull/\d+)') {
        return $Matches[1].Trim()
    }
    if ($Body -match '(?i)(https://github\.com/[^\s]+/pull/\d+)') {
        return $Matches[1].Trim()
    }
    return $null
}

function Get-BobMrbFeatureIssueNumbers {
    param([string]$Body)
    $fr = New-Object 'System.Collections.Generic.HashSet[int]'
    if (-not $Body) { return @() }
    if ($Body -match '(?i)\*\*Feature request:\*\*\s*https://github\.com/[^/\s]+/[^/\s]+/issues/(\d+)') {
        [void]$fr.Add([int]$Matches[1])
    }
    if ($Body -match '(?i)##\s+Feature request\s+[\r\n]+\s*https://github\.com/[^/\s]+/[^/\s]+/issues/(\d+)') {
        [void]$fr.Add([int]$Matches[1])
    }
    return @($fr)
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
