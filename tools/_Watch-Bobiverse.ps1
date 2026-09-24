# DO NOT EDIT — generated template from Install-BobFleet.ps1 (customize per host only on box).
# Generic #bobiverse moot wrapper. Restart watcher kills Watch-Bobiverse
# plus bobiverse irc_agent, starts _Watch-Bobiverse-<machineId> (this
# script or the scheduled task of that name), then relaunches the tray.
# No grok.exe. Does not touch Watch-BobJobs.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$inner = Join-Path $PSScriptRoot 'Watch-Bobiverse.ps1'
if (-not (Test-Path $inner)) { throw "missing $inner" }
& $inner -PollSec $PollSec -RepoRoot $RepoRoot
