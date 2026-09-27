#Requires -Version 5.1
# CAST IRON: deterministic git update + install for Bob Systray start/restart.
# No LLM / no agent. Scripts + git only.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Branch = 'main',
    [switch]$Force,
    [switch]$WhatIf,
    [switch]$SkipDialog,
    [string]$GitExe = 'git'
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)

function Write-BobSystrayUpdateLog([string]$m) {
    $dir = Join-Path $env:USERPROFILE 'Desktop\Watch-AgentHealth'
    if ($env:BOB_WATCH_SEAT_PROFILE_ROOT) {
        $dir = Join-Path $env:BOB_WATCH_SEAT_PROFILE_ROOT 'Desktop\Watch-AgentHealth'
    }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $path = Join-Path $dir 'tray-reinstall.log'
    Add-Content -LiteralPath $path -Value ('{0:o} systray-update {1}' -f [datetime]::UtcNow, $m) -Encoding utf8
}

function Invoke-BobSystrayGit {
    param([string[]]$ArgumentList, [string]$WorkDir)
    if ($env:BOB_FLEET_REINSTALL_FAKE -match '^(?i)1|true|yes$') {
        $fakeBehind = ($env:BOB_SYSTRAY_FAKE_BEHIND -match '^(?i)1|true|yes$')
        if (($ArgumentList -join ' ') -match 'rev-list') {
            $n = $(if ($fakeBehind -or $Force) { '1' } else { '0' })
            return [pscustomobject]@{ ExitCode = 0; StdOut = $n; StdErr = '' }
        }
        return [pscustomobject]@{ ExitCode = 0; StdOut = 'fake'; StdErr = '' }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $GitExe
    $psi.Arguments = ($ArgumentList -join ' ')
    $psi.WorkingDirectory = $WorkDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; StdOut = $out; StdErr = $err }
}

function Test-BobSystrayGitBehind {
    param([string]$Root, [string]$Ref)
    $fetch = Invoke-BobSystrayGit -WorkDir $Root -ArgumentList @('fetch', 'origin', $Ref)
    if ($fetch.ExitCode -ne 0) {
        Write-BobSystrayUpdateLog ("fetch failed: {0}" -f $fetch.StdErr.Trim())
        return [pscustomobject]@{ Behind = $false; Count = 0; Error = $fetch.StdErr.Trim(); Ok = $false }
    }
    $rl = Invoke-BobSystrayGit -WorkDir $Root -ArgumentList @('rev-list', '--count', "HEAD..origin/$Ref")
    if ($rl.ExitCode -ne 0) {
        return [pscustomobject]@{ Behind = $false; Count = 0; Error = $rl.StdErr.Trim(); Ok = $false }
    }
    $n = 0
    [void][int]::TryParse(([string]$rl.StdOut).Trim(), [ref]$n)
    return [pscustomobject]@{ Behind = ($n -gt 0); Count = $n; Error = $null; Ok = $true }
}

$state = Test-BobSystrayGitBehind -Root $RepoRoot -Ref $Branch
if ($Force) { $state.Behind = $true; if ($state.Count -le 0) { $state.Count = 1 } }

$result = [ordered]@{
    ok        = $true
    updated   = $false
    behind    = [bool]$state.Behind
    count     = [int]$state.Count
    dialog    = $false
    error     = $null
    summary   = 'already current'
}

if (-not $state.Ok -and -not $Force) {
    $result.ok = $false
    $result.error = $state.Error
    $result.summary = 'git fetch/rev-list failed'
    Write-BobSystrayUpdateLog $result.summary
    $result | ConvertTo-Json -Compress
    exit 1
}

if (-not $state.Behind) {
    Write-BobSystrayUpdateLog 'already current - skip install'
    $result | ConvertTo-Json -Compress
    exit 0
}

Write-BobSystrayUpdateLog ("behind={0} - install" -f $state.Count)
$dlgProc = $null
$doneFlag = Join-Path $env:TEMP ('bob-systray-update-done-{0}-{1}.flag' -f $PID, [guid]::NewGuid().ToString('N'))
try {
    if (-not $SkipDialog -and -not $WhatIf -and -not ($env:BOB_SYSTRAY_UPDATE_HEADLESS -match '^(?i)1|true|yes$')) {
        $dlg = Join-Path $PSScriptRoot 'Show-BobSystrayUpdatingDialog.ps1'
        if (Test-Path -LiteralPath $dlg) {
            Remove-Item -LiteralPath $doneFlag -Force -ErrorAction SilentlyContinue
            $ps = (Get-Command powershell.exe).Source
            $dlgProc = Start-Process -FilePath $ps -ArgumentList @(
                '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
                '-File', $dlg, '-DoneFlag', $doneFlag
            ) -PassThru -WindowStyle Normal
            $result.dialog = $true
        }
    }

    if ($WhatIf) {
        $result.updated = $true
        $result.summary = 'would-update'
    }
    else {
        $reinstall = Join-Path $PSScriptRoot 'Invoke-BobFleetReinstall.ps1'
        if (-not (Test-Path -LiteralPath $reinstall)) {
            throw "missing $reinstall"
        }
        $ps = (Get-Command powershell.exe).Source
        # Do not pass -RelaunchTray (switch default false). Start-BobFleetTray owns relaunch.
        $out = & $ps -NoProfile -ExecutionPolicy Bypass -File $reinstall `
            -RepoRoot $RepoRoot -SkipRestart 2>&1
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        $result.updated = $true
        $jsonLine = @($out | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
        if ($jsonLine) {
            try {
                $rep = $jsonLine | ConvertFrom-Json
                $result.summary = [string]$rep.summary
                if (-not $result.summary) { $result.summary = "reinstall exit=$code" }
                if ($rep.ok -eq $false) { $result.ok = $false }
            }
            catch {
                $result.summary = "reinstall exit=$code"
            }
        }
        else {
            $result.summary = "reinstall exit=$code"
            if ($code -ne 0) { $result.ok = $false }
        }
        # Refresh Start Menu Bob Systray shortcuts after install
        $shortHelper = Join-Path $PSScriptRoot 'Install-BobFleetTrayShortcut.ps1'
        if (Test-Path -LiteralPath $shortHelper) {
            try { & $shortHelper -RepoRoot $RepoRoot | Out-Null } catch { }
        }
    }
}
catch {
    $result.ok = $false
    $result.error = $_.Exception.Message
    $result.summary = 'update failed: ' + $_.Exception.Message
    Write-BobSystrayUpdateLog $result.summary
}
finally {
    try {
        Set-Content -LiteralPath $doneFlag -Value ((Get-Date).ToUniversalTime().ToString('o')) -Encoding ascii
    }
    catch { }
    if ($dlgProc -and -not $dlgProc.HasExited) {
        try { $dlgProc.WaitForExit(15000) | Out-Null } catch { }
        if (-not $dlgProc.HasExited) {
            try { $dlgProc.Kill() } catch { }
        }
    }
    Remove-Item -LiteralPath $doneFlag -Force -ErrorAction SilentlyContinue
}

Write-BobSystrayUpdateLog $result.summary
$result | ConvertTo-Json -Compress
if (-not $result.ok) { exit 1 }
exit 0
