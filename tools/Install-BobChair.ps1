# Durable digest chair on ionos. Watch-Bobiverse must not start the chair.
# IRC home is ~\.agentic-irc-jeeves. BOB_DIGEST_HOME is ~\.agentic-irc-bobiverse.
# Registers service BobJeeves (depends on BobIrcd). Does not start a builder seat.
# FR #330: canonical install is SimonBarnett/gh-Jeeves (python -m jeeves).
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$AllowLegacyAgenticIrc
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

$ghCandidates = @(
    (Join-Path (Split-Path $RepoRoot -Parent) 'gh-Jeeves\tools\Install-BobJeeves.ps1'),
    'C:\ai\gh-Jeeves\tools\Install-BobJeeves.ps1',
    'D:\ai\gh-Jeeves\tools\Install-BobJeeves.ps1'
)
$ghInstall = $null
foreach ($c in $ghCandidates) {
    if (Test-Path -LiteralPath $c) { $ghInstall = $c; break }
}
if ($ghInstall -and -not $AllowLegacyAgenticIrc) {
    Write-Warning @"
FR #330: canonical BobJeeves is gh-Jeeves (python -m jeeves).
Found: $ghInstall
Run:
  powershell -NoProfile -File `"$ghInstall`" -Apply -Production
Legacy NSSM path: re-run this script with -AllowLegacyAgenticIrc
"@
    throw 'Refusing Install-BobChair while gh-Jeeves is present (pass -AllowLegacyAgenticIrc to override).'
}

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
& (Join-Path $RepoRoot 'tools\Install-BobJeeves.ps1') -RepoRoot $RepoRoot -Nick $chairNick -JeevesHome $jeevesHome -DigestHome $digestHome -AllowLegacyAgenticIrc:$AllowLegacyAgenticIrc
