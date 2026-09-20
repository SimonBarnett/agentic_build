# Start GitHub Copilot cloud agent on a SimonBarnett repo (user gh token).
# Bills GitHub Copilot credits, not Cursor weekly usage and not grok.exe.
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

$tmp = Join-Path $env:TEMP ('bob-copilot-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    if ($PSCmdlet.ParameterSetName -eq 'prompt') {
        $obj = [ordered]@{ prompt = $Prompt; base_ref = $BaseRef }
        ($obj | ConvertTo-Json) | Set-Content -Path $tmp -Encoding utf8
        $raw = & $gh api --method POST "agents/repos/$owner/$name/tasks" --input $tmp
    }
    else {
        $aa = [ordered]@{
            target_repo         = $Repo
            base_branch         = $BaseRef
            custom_instructions = $(if ($CustomInstructions) { $CustomInstructions } else { '' })
            custom_agent        = ''
            model               = ''
        }
        $obj = [ordered]@{
            assignees        = @('copilot-swe-agent[bot]')
            agent_assignment = $aa
        }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -Path $tmp -Encoding utf8
        $raw = & $gh api --method POST "repos/$owner/$name/issues/$Issue/assignees" --input $tmp
    }
}
finally {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
}

if ($LASTEXITCODE -ne 0) {
    throw "gh api failed: $raw"
}

$parsed = $raw | ConvertFrom-Json
[pscustomobject]@{
    ok     = $true
    repo   = $Repo
    mode   = $PSCmdlet.ParameterSetName
    id     = $(if ($parsed.id) { $parsed.id } elseif ($parsed.number) { $parsed.number } else { $null })
    url    = $(if ($parsed.html_url) { $parsed.html_url } elseif ($parsed.url) { $parsed.url } else { $null })
    state  = $(if ($parsed.state) { $parsed.state } else { 'started' })
    raw    = $parsed
}
