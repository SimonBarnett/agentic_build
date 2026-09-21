# Generic Start-BobBuildLoop launcher (any repo/issue). Stdout DONE/FAILED only.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$Issue,
    [Parameter(Mandatory)][string]$Repo,
    [Parameter(Mandatory)][string]$Cwd,
    [string]$Docs,
    [string]$Plan,
    [string]$GoalPath,
    [string]$Sha,
    [string]$Pr,
    [string]$LogPath
)
$ErrorActionPreference = 'Stop'
$fill = "protocol=https`nhost=github.com`n`n"
$gcm = @(
    "$env:ProgramFiles\Git\mingw64\bin\git-credential-manager.exe",
    "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\git-credential-manager.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$cred = $null
if ($gcm) { $cred = $fill | & $gcm get 2>$null }
if (-not $cred) { $cred = $fill | git credential fill 2>$null }
foreach ($line in @($cred)) {
    if ($line -like 'password=*') {
        $env:GH_TOKEN = $line.Substring(9)
        $env:GITHUB_TOKEN = $env:GH_TOKEN
    }
}
if (-not $env:GH_TOKEN) { throw 'no GitHub token from GCM / git credential' }
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
if (-not (Test-Path $loop)) { throw "missing Start-BobBuildLoop.ps1 (not beside launcher and not under C:\\ai\\agentic_build\\tools)" }
$loopArgs = @{
    Repo  = $Repo
    Issue = $Issue
    Cwd   = $Cwd
}
if ($Docs) { $loopArgs['Docs'] = $Docs }
if ($Plan) { $loopArgs['Plan'] = $Plan }
if ($GoalPath) { $loopArgs['Goal'] = [IO.File]::ReadAllText($GoalPath) }
if ($Sha) { $loopArgs['Sha'] = $Sha }
if ($Pr) { $loopArgs['Pr'] = $Pr }
if ($LogPath) { $loopArgs['LogPath'] = $LogPath }
& $loop @loopArgs
exit $LASTEXITCODE
