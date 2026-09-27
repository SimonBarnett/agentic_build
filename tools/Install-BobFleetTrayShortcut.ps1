#Requires -Version 5.1
# Install Start Menu\Programs\Bob Systray (+ Desktop) shortcuts with robot .ico.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

$launcher = Join-Path $RepoRoot 'tools\Start-BobFleetTray.ps1'
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "missing $launcher"
}
$ico = Join-Path $RepoRoot 'assets\bob-systray.ico'
$ps = (Get-Command powershell.exe).Source

$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\Bob Systray'
if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) {
    $desktop = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT 'Desktop'
    $startMenu = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT 'StartMenu\Bob Systray'
}
New-Item -ItemType Directory -Force -Path $desktop, $startMenu | Out-Null

$entries = @(
    [pscustomobject]@{
        Name = 'Bob Systray.lnk'
        Args = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$launcher`" -RepoRoot `"$RepoRoot`""
        Desc = 'Start Bob Systray (git update if needed, then tray)'
    }
    [pscustomobject]@{
        Name = 'Restart Bob Systray.lnk'
        Args = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$launcher`" -RepoRoot `"$RepoRoot`" -ForceNew"
        Desc = 'Restart Bob Systray (git update + replace tray)'
    }
)

$paths = @()
foreach ($dir in @($desktop, $startMenu)) {
    foreach ($e in $entries) {
        $lnkPath = Join-Path $dir $e.Name
        if ($WhatIf) { $paths += $lnkPath; continue }
        if ($env:BOB_FLEET_REINSTALL_FAKE -match '^(?i)1|true|yes$') {
            Set-Content -LiteralPath ($lnkPath + '.target.txt') -Value "$ps $($e.Args)" -Encoding utf8
            $paths += ($lnkPath + '.target.txt')
            continue
        }
        $w = New-Object -ComObject WScript.Shell
        $s = $w.CreateShortcut($lnkPath)
        $s.TargetPath = $ps
        $s.Arguments = $e.Args
        $s.WorkingDirectory = $RepoRoot
        $s.WindowStyle = 7
        $s.Description = $e.Desc
        if (Test-Path -LiteralPath $ico) {
            $s.IconLocation = "$ico,0"
        }
        $s.Save()
        $paths += $lnkPath
    }
}

[pscustomobject]@{
    ok           = $true
    startMenuDir = $startMenu
    icon         = $(if (Test-Path -LiteralPath $ico) { $ico } else { $null })
    paths        = $paths
} | ConvertTo-Json -Compress
