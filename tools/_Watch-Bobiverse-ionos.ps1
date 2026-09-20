# ionos #bobiverse moot wrapper. Restart watcher: kill Watch-Bobiverse
# + bobiverse irc_agent, start this (or scheduled task
# _Watch-Bobiverse-ionos), then restart the tray.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
& (Join-Path $PSScriptRoot 'Watch-Bobiverse.ps1') -PollSec $PollSec -RepoRoot $RepoRoot
