# DO NOT EDIT — generated template from Install-BobFleet.ps1 (customize per host only on box).
# IRC TSR watchdog wrapper. Scheduled task _Watch-IrcTsr-<machineId> runs this
# or a per-machine copy. Not Watch-Bobiverse — no grok reasoning here.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [int]$SilenceSec = 60,
    [int]$RestartAfterSec = 600,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$inner = Join-Path $PSScriptRoot 'Watch-IrcTsr.ps1'
if (-not (Test-Path $inner)) { throw "missing $inner" }
& $inner -PollSec $PollSec -SilenceSec $SilenceSec -RestartAfterSec $RestartAfterSec -RepoRoot $RepoRoot
