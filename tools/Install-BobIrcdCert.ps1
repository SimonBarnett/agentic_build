# win-acme renewal hook: Ergo reads renewed PEMs from Ergo root; recycle BobIrcd only.
# Point win-acme "Installation script" at this file (copy to C:\ai\ergo if required).
# Recycles the Ergo SCM service only (no scheduled-task verbs).
[CmdletBinding()]
param(
    [string]$ServiceName = 'BobIrcd'
)

$ErrorActionPreference = 'Stop'
Restart-Service -Name $ServiceName -Force
