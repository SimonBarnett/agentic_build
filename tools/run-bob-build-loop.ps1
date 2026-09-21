# Launch Start-BobBuildLoop with GH_TOKEN. Stdout is the driver's DONE/FAILED only.
# Prefer GCM get (git credential fill often fails when gh is the helper and not logged in).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Issue,
    [Parameter(Mandatory)][string]$Cwd,
    [string]$Docs,
    [string]$Plan,
    [string]$Goal,
    [string]$Sha,
    [string]$Pr,
    [string]$StatePath,
    [string]$LogPath,
    [string]$Repo = 'SimonBarnett/agentic_build'
)
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$pass = $null
$fill = "protocol=https`nhost=github.com`n`n"
$gcm = @(
    "$env:ProgramFiles\Git\mingw64\bin\git-credential-manager.exe",
    "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\git-credential-manager.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$savedEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    if ($gcm) {
        $cm = $fill | & $gcm get 2>$null
        foreach ($line in @($cm)) {
            if ($line -match '^password=(.+)$') { $pass = $Matches[1].Trim() }
        }
    }
    if (-not $pass) {
        $cm = cmd /c "echo protocol=https&echo host=github.com&echo.&echo." 2>$null | git credential-manager get 2>$null
        foreach ($line in @($cm -split "`r?`n")) {
            if ($line -match '^password=(.+)$') { $pass = $Matches[1].Trim() }
        }
    }
    if (-not $pass) {
        $cred = $fill | git credential fill 2>$null
        foreach ($line in @($cred)) {
            if ($line -match '^password=(.+)$') { $pass = $Matches[1].Trim() }
        }
    }
}
catch { }
$ErrorActionPreference = $savedEap
if (-not $pass) { Write-Output 'FAILED: no github token'; exit 1 }
$env:GH_TOKEN = $pass
$env:GITHUB_TOKEN = $pass
if (-not $env:BOB_MACHINE_ID) { $env:BOB_MACHINE_ID = 'ionos' }
$loop = Join-Path $PSScriptRoot 'Start-BobBuildLoop.ps1'
if (-not (Test-Path $loop)) {
    foreach ($c in @(
            'C:\ai\agentic_build\tools\Start-BobBuildLoop.ps1',
            'D:\ai\agentic_build\tools\Start-BobBuildLoop.ps1',
            'C:\src\agentic_build\tools\Start-BobBuildLoop.ps1'
        )) {
        if (Test-Path $c) { $loop = $c; break }
    }
}
if (-not (Test-Path $loop)) { Write-Output 'FAILED: Start-BobBuildLoop.ps1 missing'; exit 1 }
$a = @{
    Issue = $Issue
    Repo  = $Repo
    Cwd   = $Cwd
}
if ($Docs) { $a['Docs'] = $Docs }
if ($Plan) { $a['Plan'] = $Plan }
if ($Goal) { $a['Goal'] = $Goal }
if ($Sha) { $a['Sha'] = $Sha }
if ($Pr) { $a['Pr'] = $Pr }
if ($StatePath) { $a['StatePath'] = $StatePath }
if ($LogPath) { $a['LogPath'] = $LogPath }
& $loop @a
exit $LASTEXITCODE
