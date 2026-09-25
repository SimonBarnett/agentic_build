# WP4 — copy/register the adapter on this machine. No SCM / Windows service.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$BridgeHome
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

if (-not $BridgeHome) {
    if ($env:BOB_BRIDGE_HOME) { $BridgeHome = $env:BOB_BRIDGE_HOME }
    else { $BridgeHome = Join-Path $env:USERPROFILE '.grok\bob-bridge' }
}
New-Item -ItemType Directory -Force -Path $BridgeHome | Out-Null

$bundled = Join-Path $RepoRoot 'config\default.json'
$cfg = Join-Path $BridgeHome 'config.json'
if ((Test-Path $bundled) -and -not (Test-Path $cfg)) {
    Copy-Item $bundled $cfg
}

$grok = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
if (-not $env:BOB_GROK_EXE -and (Test-Path $grok)) {
    [Environment]::SetEnvironmentVariable('BOB_GROK_EXE', $grok, 'User')
    $env:BOB_GROK_EXE = $grok
}

Write-Host "Repo:        $RepoRoot"
Write-Host "Bridge home: $BridgeHome"
Write-Host "Grok exe:    $($env:BOB_GROK_EXE)"
Write-Host "Import with: Import-Module '$RepoRoot\src\BobBridge.psd1'"
Write-Host "Off-DEV:     powershell -NoProfile -File '$RepoRoot\tools\Test-Pack.ps1'"
Write-Host "No Windows service installed (oneshot MVP)."
