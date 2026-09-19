# Enqueue one harvest job on this machine. Hourly scheduled task, not a Windows service.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ReplyChannel = 'Bob'
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
Import-Module (Join-Path $RepoRoot 'src\BobBridge.psd1') -Force

$mid = $env:BOB_MACHINE_ID
if (-not $mid) {
    $rec = Get-Content (Join-Path $env:USERPROFILE '.grok\bob-bridge\machine.json') -Raw | ConvertFrom-Json
    $mid = [string]$rec.id
}
if (-not $mid) { throw 'machine id missing; run Install-BobFleet first' }

$pending = @(Get-BobBuilds -Machine $mid | Where-Object {
        $_.lane -in @('inbox', 'running') -and
        ([string]$_.goal -match 'harvest-agent-skills')
    })
if ($pending.Count -gt 0) {
    Write-Output ("skip harvest already in {0} {1}" -f $pending[0].lane, $pending[0].id)
    exit 0
}

$goal = @'
Follow .grok/skills/harvest-agent-skills/SKILL.md on this repo.

Scan ~/.grok/skills, ~/.grok/long-running-background-tasks, and docs/ for repeatable procedures that are not already a project skill. If you find one, add SKILL.md, update tools/Test-Pack.ps1 BT0 skills, run Test-Pack, append docs/skill-harvest-log.md, commit and push origin/main.

If nothing is worth promoting: write a one-line note to %USERPROFILE%\.grok\long-running-background-tasks\skill-harvest.log (create dir if needed) and exit. Do not commit. Do not start other fleet jobs.
'@

$job = Start-BobBuild `
    -Machine $mid `
    -Cwd $RepoRoot `
    -Profile generic `
    -ReplyChannel $ReplyChannel `
    -Goal $goal `
    -Constraints @(
        'Do not force-push; do not commit secrets',
        'Do not set or request an API key environment variable assignment',
        'No empty commits',
        'Do not claim ready for human UAT'
    ) `
    -Success 'Either a skill commit is on origin/main with docs note, or the local harvest log says no candidates'

$job | ConvertTo-Json -Compress -Depth 6
if (-not $job.ok) { exit 1 }
exit 0
