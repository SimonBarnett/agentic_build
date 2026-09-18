# Pull worker for this machine. Logon task, not a Windows service.
# grok.exe runs as the Windows logon user (MSSQL integrated auth).
[CmdletBinding()]
param(
    [switch]$Once,
    [int]$PollSec = 30,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
if (-not (Test-Path $psd1)) { throw "missing $psd1" }

Remove-Module BobBridge -ErrorAction SilentlyContinue
Import-Module $psd1 -Force

if ($Once) {
    $r = Invoke-BobFleetTick
    $r | ConvertTo-Json -Compress -Depth 8
    if (-not $r.ok -and $r.error -and $r.error -ne 'machine_unregistered') { exit 1 }
    exit 0
}

while ($true) {
    try { Invoke-BobFleetTick | Out-Null } catch { Write-Error $_ }
    Start-Sleep -Seconds $PollSec
}
