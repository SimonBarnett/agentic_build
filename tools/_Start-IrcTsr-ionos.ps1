# DO NOT EDIT — per-machine wrapper from Install-BobFleet.ps1 (ionos).
$env:BOB_MACHINE_ID = 'ionos'
& (Join-Path $PSScriptRoot 'Start-IrcTsr.ps1') -MachineId ionos
