#Requires -Version 5.1
# FR #346: open Bob Fleet systray (single instance). Shortcut target.
# If a tray is already running, do not start a second — exit 0 (bring-forward best-effort).
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$ForceNew
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$tray = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
if (-not (Test-Path -LiteralPath $tray)) {
    throw "missing $tray"
}

$pat = '(?i)Watch-BobTray\.ps1'
$hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -match $pat
    })

if ($hits.Count -gt 0 -and -not $ForceNew) {
    # Single-instance: keep oldest; do not spawn another
    $keep = $hits | Sort-Object CreationDate | Select-Object -First 1
    # Best-effort: signal existing tray via a flag file it can poll (optional)
    $flagDir = Join-Path $env:USERPROFILE '.grok\bob-fleet'
    New-Item -ItemType Directory -Force -Path $flagDir | Out-Null
    Set-Content -LiteralPath (Join-Path $flagDir 'show-tip.req') -Value ((Get-Date).ToUniversalTime().ToString('o')) -Encoding utf8
    Write-Output ("Bob Fleet tray already running pid={0}" -f $keep.ProcessId)
    exit 0
}

$ps = (Get-Command powershell.exe).Source
Start-Process -FilePath $ps -ArgumentList @(
    '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
    '-File', $tray
) -WorkingDirectory $RepoRoot -WindowStyle Hidden | Out-Null
exit 0
