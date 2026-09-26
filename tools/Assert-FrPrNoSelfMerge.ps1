#Requires -Version 5.1
# FR #343: flag self-merge-too-fast on a GitHub PR (report-only / CI).
# Exit 0 = ok or not merged; exit 2 = flag; exit 1 = tool error.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OwnerRepo,
    [Parameter(Mandatory = $true)][int]$Pr,
    [double]$Minutes = 30,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$py = Join-Path $here 'fr_self_merge_guard.py'
if (-not (Test-Path -LiteralPath $py)) { throw "missing $py" }

$python = $null
foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        'python'
    )) {
    if ($c -eq 'python') { $python = $c; break }
    if (Test-Path -LiteralPath $c) { $python = $c; break }
}

$argList = @($py, '--repo', $OwnerRepo, '--pr', "$Pr", '--minutes', "$Minutes")
if ($Json) { $argList += '--json' }
& $python @argList
exit $LASTEXITCODE
