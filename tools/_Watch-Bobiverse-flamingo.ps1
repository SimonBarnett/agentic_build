# flamingo #bobiverse moot wrapper. Same contract as _Watch-Bobiverse-ionos.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [string]$RepoRoot
)
$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
& (Join-Path $PSScriptRoot 'Watch-Bobiverse.ps1') -PollSec $PollSec -RepoRoot $RepoRoot
