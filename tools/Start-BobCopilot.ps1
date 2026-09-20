# Grok hands off GitHub repo work to Copilot.
# Always opens a git issue (@copilot). Tries CCA assign/task when GitHub allows it.
[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'prompt', Mandatory)][string]$Prompt,
    [Parameter(ParameterSetName = 'issue', Mandatory)][int]$Issue,
    [string]$Repo = 'SimonBarnett/agentic_build',
    [string]$BaseRef = 'main',
    [string]$CustomInstructions
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

function Write-BobJson([string]$Path, $Obj) {
    $json = $Obj | ConvertTo-Json -Depth 8 -Compress
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Path, $json, $utf8)
}

$gh = Get-BobGhExe
if (-not $gh) {
    throw 'gh.exe not found. Install GitHub CLI (winget install GitHub.cli) and gh auth login as SimonBarnett.'
}

$owner, $name = $Repo.Split('/', 2)
if (-not $name) { throw "Repo must be owner/name, got $Repo" }

& $gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'gh auth login required (user token). Copilot agent tasks do not accept installation tokens.'
}

$issueUrl = $null
$issueNum = $null
$taskUrl = $null
$ccaError = $null
$assignError = $null

if ($PSCmdlet.ParameterSetName -eq 'prompt') {
    $title = $Prompt.Trim()
    if ($title.Length -gt 80) { $title = $title.Substring(0, 77) + '...' }
    $body = @"
@copilot

Handed off by Grok (flamingo). Skills: https://github.com/SimonBarnett/agentic_build (``.grok/skills``).

$Prompt
"@
    $issueUrl = (& $gh issue create --repo $Repo --title $title --body $body 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "gh issue create failed: $issueUrl" }
    if ($issueUrl -match '/issues/(\d+)') { $issueNum = [int]$Matches[1] }
}
else {
    $issueNum = $Issue
    $issueUrl = "https://github.com/$Repo/issues/$Issue"
    & $gh issue comment $Issue --repo $Repo --body "@copilot`n`nHanded off by Grok (flamingo).`n`n$CustomInstructions"
}

$tmp = Join-Path $env:TEMP ('bob-copilot-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    Write-BobJson $tmp ([ordered]@{ prompt = $(if ($Prompt) { $Prompt } else { "Work issue #$issueNum" }); base_ref = $BaseRef })
    $taskRaw = & $gh api --method POST "agents/repos/$owner/$name/tasks" --input $tmp 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        $task = $taskRaw | ConvertFrom-Json
        $taskUrl = $(if ($task.html_url) { [string]$task.html_url } else { $null })
    }
    else {
        $ccaError = $taskRaw.Trim()
    }
}
finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
}

if ($issueNum) {
    $tmp2 = Join-Path $env:TEMP ('bob-copilot-asg-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        Write-BobJson $tmp2 ([ordered]@{ assignees = @('copilot-swe-agent') })
        $asg = & $gh api --method POST "repos/$owner/$name/issues/$issueNum/assignees" --input $tmp2 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { $assignError = $asg.Trim() }
    }
    finally {
        Remove-Item -Force $tmp2 -ErrorAction SilentlyContinue
    }
}

[pscustomobject]@{
    ok           = $true
    handed_off   = $true
    repo         = $Repo
    issue        = $issueUrl
    issue_number = $issueNum
    task         = $taskUrl
    cca_error    = $ccaError
    assign_error = $assignError
    note         = $(if ($taskUrl) { 'CCA task started' } elseif ($ccaError -match 'CCA') { 'Issue opened with @copilot. Enable Copilot cloud agent on this repo (org policy Coming soon is not enough).' } else { 'Issue opened with @copilot' })
}
