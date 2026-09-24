# Durable digest chair on ionos. Watch-Bobiverse must not start the chair.
# IRC home is ~\.agentic-irc-jeeves. BOB_DIGEST_HOME is ~\.agentic-irc-bobiverse.
# Registers service BobJeeves (depends on BobIrcd). Does not start a builder seat.
[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$cfgPath = Join-Path $RepoRoot 'config\bobiverse.json'
$cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
$chairNick = [string]$cfg.chairNick
if (-not $chairNick.Trim()) { $chairNick = 'Jeeves' }
$chairNick = $chairNick.Trim()
$jeevesHome = Join-Path $env:USERPROFILE '.agentic-irc-jeeves'
$digestHome = Join-Path $env:USERPROFILE '.agentic-irc-bobiverse'
if ($jeevesHome.TrimEnd('\') -eq $digestHome.TrimEnd('\')) {
    throw 'Jeeves home must not be the bobiverse digest home'
}
$env:BOB_DIGEST_HOME = $digestHome
& (Join-Path $RepoRoot 'tools\Install-BobJeeves.ps1') -RepoRoot $RepoRoot -Nick $chairNick -JeevesHome $jeevesHome -DigestHome $digestHome
