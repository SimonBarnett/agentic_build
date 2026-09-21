# Launch Start-BobBuildLoop with GH_TOKEN. Stdout is the driver's DONE/FAILED only.
# Prefer: git credential-manager get (git credential fill often fails non-interactively).
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
$savedEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $cm = cmd /c "echo protocol=https&echo host=github.com&echo.&echo." 2>$null | git credential-manager get 2>$null
    foreach ($line in @($cm -split "`r?`n")) {
        if ($line -match '^password=(.+)$') { $pass = $Matches[1].Trim() }
    }
}
catch { }
if (-not $pass) {
    try {
        $credIn = "protocol=https`nhost=github.com`n`n"
        $cred = $credIn | git credential fill 2>$null
        foreach ($line in @($cred -split "`n")) {
            if ($line -match '^password=(.+)$') { $pass = $Matches[1].Trim() }
        }
    }
    catch { }
}
$ErrorActionPreference = $savedEap
if (-not $pass) { Write-Output 'FAILED: no github token'; exit 1 }
$env:GH_TOKEN = $pass
$env:GITHUB_TOKEN = $pass
if (-not $env:BOB_MACHINE_ID) { $env:BOB_MACHINE_ID = 'ionos' }
$loop = Join-Path $PSScriptRoot 'Start-BobBuildLoop.ps1'
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
