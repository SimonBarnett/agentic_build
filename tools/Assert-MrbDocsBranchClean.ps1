# FR #348: flag feature PRs that got docs(MRB commits on the reviewed branch.
param(
    [Parameter(Mandatory)][string]$OwnerRepo,
    [Parameter(Mandatory)][int]$Pr,
    [string]$MrbStartedAt = '',
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { throw 'python required' }
$script = Join-Path $PSScriptRoot 'mrb_docs_branch_guard.py'
$argv = @($script, '--repo', $OwnerRepo, '--pr', "$Pr")
if ($MrbStartedAt) { $argv += @('--mrb-started-at', $MrbStartedAt) }
if ($Json) { $argv += '--json' }
& python @argv
exit $LASTEXITCODE
