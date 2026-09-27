#Requires -Version 5.1
# Bob Systray launcher (Start Menu / Desktop shortcut target).
# CAST IRON: always check git for updates and install via scripts (no LLM)
# before starting the tray. Show Updating dialog when behind origin.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$ForceNew,
    [switch]$SkipUpdate,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$tray = Join-Path $RepoRoot 'tools\Watch-BobTray.ps1'
if (-not (Test-Path -LiteralPath $tray)) {
    throw "missing $tray"
}

# --- deterministic update gate (start + restart) ---
if (-not $SkipUpdate) {
    $updater = Join-Path $RepoRoot 'tools\Update-BobSystrayFromGit.ps1'
    if (Test-Path -LiteralPath $updater) {
        $ps = (Get-Command powershell.exe).Source
        $updArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $updater, '-RepoRoot', $RepoRoot)
        if ($WhatIf) { $updArgs += '-WhatIf' }
        $updOut = & $ps @updArgs 2>&1
        $updCode = $LASTEXITCODE
        if ($null -eq $updCode) { $updCode = 0 }
        Write-Output (@($updOut) -join "`n")
        # Non-zero update: still attempt tray start from current tree (dialog already closed).
        if ($updCode -ne 0) {
            Write-Warning "Bob Systray update exited $updCode — starting tray from current tree"
        }
    }
}

$pat = '(?i)Watch-BobTray\.ps1'
$hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -match $pat
    })

if ($ForceNew -and $hits.Count -gt 0) {
    foreach ($h in $hits) {
        try { Stop-Process -Id ([int]$h.ProcessId) -Force -ErrorAction SilentlyContinue } catch { }
    }
    Start-Sleep -Milliseconds 500
    $hits = @()
}

if ($hits.Count -gt 0 -and -not $ForceNew) {
    $keep = $hits | Sort-Object CreationDate | Select-Object -First 1
    $flagDir = Join-Path $env:USERPROFILE '.grok\bob-fleet'
    New-Item -ItemType Directory -Force -Path $flagDir | Out-Null
    Set-Content -LiteralPath (Join-Path $flagDir 'show-tip.req') -Value ((Get-Date).ToUniversalTime().ToString('o')) -Encoding utf8
    Write-Output ("Bob Systray already running pid={0}" -f $keep.ProcessId)
    exit 0
}

if ($WhatIf) {
    Write-Output 'would-start-tray'
    exit 0
}

$ps = (Get-Command powershell.exe).Source
Start-Process -FilePath $ps -ArgumentList @(
    '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
    '-File', $tray
) -WorkingDirectory $RepoRoot -WindowStyle Hidden | Out-Null
exit 0
