# One-shot digest chair on ionos (briefer). Builder seats use Install-BobIrc.ps1 without -Chair.
# Watch-Bobiverse must not become the chair.
[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$cfgPath = Join-Path $RepoRoot 'config\bobiverse.json'
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$chairHome = [string]$cfg.chairHome
if (-not $chairHome.Trim()) { $chairHome = 'ionos' }
$chairNick = [string]$cfg.chairNick
if ($chairNick.Trim()) {
    $env:BOB_IRC_NICK = $chairNick.Trim()
}
& (Join-Path $RepoRoot 'tools\Install-BobIrc.ps1') -MachineId $chairHome -RepoRoot $RepoRoot -Chair
