# DO NOT EDIT — generated template from Install-BobFleet.ps1 (customize per host only on box).
# Grok-talk inbox poller wrapper. Scheduled task _Watch-GrokTalk-<machineId> runs this
# or a per-machine copy. Not Watch-Bobiverse — no IRC moot loop here.
[CmdletBinding()]
param(
    [switch]$Once,
    [int]$PollSec = 15,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$inner = Join-Path $PSScriptRoot 'Watch-GrokTalk.ps1'
if (-not (Test-Path $inner)) { throw "missing $inner" }
if ($Once) {
    & $inner -Once -PollSec $PollSec -RepoRoot $RepoRoot
}
else {
    & $inner -PollSec $PollSec -RepoRoot $RepoRoot
}
