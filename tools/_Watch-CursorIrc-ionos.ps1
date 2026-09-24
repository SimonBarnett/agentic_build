# DO NOT EDIT — per-machine wrapper from Install-BobFleet.ps1 (ionos).
$env:BOB_MACHINE_ID = 'ionos'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Watch-CursorIrc.ps1') -RepoRoot $root
