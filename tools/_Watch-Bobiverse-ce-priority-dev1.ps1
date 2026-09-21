# DO NOT EDIT — per-machine wrapper from Install-BobFleet.ps1 (ce-priority-dev1).
# ce-priority-dev1 #bobiverse moot wrapper. Same contract as _Watch-Bobiverse-ionos.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Continue'
$env:BOB_MACHINE_ID = 'ce-priority-dev1'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
& (Join-Path $PSScriptRoot 'Watch-Bobiverse.ps1') -PollSec $PollSec -RepoRoot $RepoRoot
