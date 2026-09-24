# win-acme renewal hook: Ergo reads renewed PEMs from Ergo root; recycle BobIrcd.
# Point win-acme "Installation script" at this file (copy to C:\ai\ergo if required).
# Recycles the Ergo SCM service (no scheduled-task verbs). BobJeeves depends on
# BobIrcd, so this also starts the chair again when that service is installed.
[CmdletBinding()]
param(
    [string]$ServiceName = 'BobIrcd'
)

$ErrorActionPreference = 'Stop'
Restart-Service -Name $ServiceName -Force
$jeeves = Get-Service -Name 'BobJeeves' -ErrorAction SilentlyContinue
if ($jeeves) { Start-Service -Name 'BobJeeves' }
