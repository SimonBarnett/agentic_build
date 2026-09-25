# DO NOT EDIT — per-machine wrapper from Install-BobFleet.ps1 (flamingo).
# flamingo #bobiverse moot wrapper. Same contract as _Watch-Bobiverse-ionos
# (Restart watcher). Sets BOB_MACHINE_ID; IRC home comes from Install-BobIrc.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Continue'
$env:BOB_MACHINE_ID = 'flamingo'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
& (Join-Path $PSScriptRoot 'Watch-Bobiverse.ps1') -PollSec $PollSec -RepoRoot $RepoRoot
