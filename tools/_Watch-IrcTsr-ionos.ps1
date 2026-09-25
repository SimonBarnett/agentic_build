# DO NOT EDIT — per-machine wrapper from Install-BobFleet.ps1 (ionos).
$env:BOB_MACHINE_ID = 'ionos'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Watch-IrcTsr.ps1') -PollSec 30 -SilenceSec 60 -RestartAfterSec 600 -RepoRoot $root
