function Get-BobProductRepo {
    param([string]$Repo)
    if ($Repo) {
        $s = [string]$Repo.Trim()
        if ($s -match '(?i)github\.com[/:]([^/]+/[^/\s#?]+)') { return $Matches[1] }
        return ($s -replace '^https://github.com/', '').Trim('/')
    }
    if ($env:BOB_PRODUCT_REPO) {
        return (Get-BobProductRepo -Repo $env:BOB_PRODUCT_REPO)
    }
    return 'SimonBarnett/agentic_build'
}

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

function New-BobGhPostingSnapshot {
    param(
        [bool]$Present,
        [bool]$Authenticated,
        [bool]$IssuePostingReady,
        [string]$Reason
    )
    return [pscustomobject]@{
        present               = $Present
        authenticated         = $Authenticated
        issue_posting_ready   = $IssuePostingReady
        reason                = $Reason
        probedAt              = [DateTime]::UtcNow.ToString('o')
    }
}

function Get-BobGhPostingReadiness {
    [CmdletBinding()]
    param(
        [string]$Repo
    )
    $repoSlug = Get-BobProductRepo -Repo $Repo
    $gh = Get-BobGhExe
    if (-not $gh) {
        return (New-BobGhPostingSnapshot -Present $false -Authenticated $false -IssuePostingReady $false -Reason `
                'gh.exe not found (Install-BobFleet / winget install GitHub.cli, then gh auth login or GH_TOKEN with issues:write and pull_requests:write)')
    }
    & $gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return (New-BobGhPostingSnapshot -Present $true -Authenticated $false -IssuePostingReady $false -Reason `
                'gh auth failed (gh auth login on this worker, or set GH_TOKEN / GITHUB_TOKEN with issues:write and pull_requests:write)')
    }
    $null = & $gh repo view $repoSlug --json name -q .name 2>&1
    if ($LASTEXITCODE -ne 0) {
        return (New-BobGhPostingSnapshot -Present $true -Authenticated $true -IssuePostingReady $false -Reason `
                "cannot read repo $repoSlug with current gh auth (need issues:write and pull_requests:write on the product repo)")
    }
    return (New-BobGhPostingSnapshot -Present $true -Authenticated $true -IssuePostingReady $true -Reason 'ok')
}

function Update-BobMachineGhPosting {
    param(
        $Record,
        [string]$Repo
    )
    if (-not $Record) { return $Record }
    $snap = Get-BobGhPostingReadiness -Repo $Repo
    $Record | Add-Member -NotePropertyName gh_posting -NotePropertyValue $snap -Force
    return $Record
}

function Test-BobMachineIssuePostingReady {
    param($Machine)
    if ($null -eq $Machine) { return $false }
    if ($null -ne $Machine.issue_posting_ready -and [string]$Machine.issue_posting_ready -ne '') {
        try { return [bool]$Machine.issue_posting_ready } catch { }
    }
    $gp = $Machine.gh_posting
    if ($gp -and $null -ne $gp.issue_posting_ready) {
        try { return [bool]$gp.issue_posting_ready } catch { }
    }
    return $false
}

function Install-BobGitHubCliIfMissing {
    [CmdletBinding()]
    param(
        [string]$Repo
    )
    if ($env:BOB_SKIP_GH_INSTALL -eq '1') {
        $snap = Get-BobGhPostingReadiness -Repo $Repo
        return [pscustomobject]@{
            action     = 'skipped'
            message    = 'BOB_SKIP_GH_INSTALL=1'
            gh_posting = $snap
        }
    }
    $existing = Get-BobGhExe
    if ($existing) {
        $snap = Get-BobGhPostingReadiness -Repo $Repo
        return [pscustomobject]@{
            action     = 'present'
            message    = "gh at $existing"
            gh_posting = $snap
        }
    }
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        $snap = Get-BobGhPostingReadiness -Repo $Repo
        return [pscustomobject]@{
            action     = 'not-ready'
            message    = 'winget unavailable; install GitHub CLI manually (winget install GitHub.cli), then gh auth login or set GH_TOKEN'
            gh_posting = $snap
        }
    }
    $wingetOut = & winget install --id GitHub.cli -e --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
    $installed = Get-BobGhExe
    if (-not $installed) {
        $snap = Get-BobGhPostingReadiness -Repo $Repo
        $detail = if ($wingetOut.Trim()) { $wingetOut.Trim() } else { 'winget finished but gh.exe still not found' }
        return [pscustomobject]@{
            action     = 'not-ready'
            message    = $detail
            gh_posting = $snap
        }
    }
    $snap2 = Get-BobGhPostingReadiness -Repo $Repo
    return [pscustomobject]@{
        action     = 'installed'
        message    = "installed via winget at $installed"
        gh_posting = $snap2
    }
}
