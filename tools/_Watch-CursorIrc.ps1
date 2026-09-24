# DO NOT EDIT — generated template from Install-BobFleet.ps1 (customize per host only on box).
# Cursor IRC seat wrapper (irc_agent + Start-IrcTsr). Task _Watch-CursorIrc-<machineId>.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$inner = Join-Path $PSScriptRoot 'Watch-CursorIrc.ps1'
if (-not (Test-Path $inner)) { throw "missing $inner" }
& $inner -PollSec $PollSec -RepoRoot $RepoRoot
