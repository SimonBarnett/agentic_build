# Pull worker for this machine. Logon task, not a Windows service.
# grok.exe runs as the Windows logon user (MSSQL integrated auth).
# Continuous mode spawns -Once children so inbox drains with no concurrent ceiling.
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

function Get-InboxCount {
    $mid = Get-ThisMachineId
    if (-not $mid) { return 0 }
    $inboxDir = Join-Path (Join-Path (Get-BridgeRoot) 'fleet') (Join-Path 'inbox' $mid)
    if (-not (Test-Path $inboxDir)) { return 0 }
    return @(Get-ChildItem $inboxDir -Filter '*.json' -ErrorAction SilentlyContinue).Count
}

$ps = (Get-Command powershell.exe).Source
$self = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'

while ($true) {
    try {
        $n = Get-InboxCount
        if ($n -gt 0) {
            $arg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Once -RepoRoot `"$RepoRoot`""
            Start-Process -FilePath $ps -ArgumentList $arg -WindowStyle Hidden | Out-Null
            Start-Sleep -Seconds 2
            continue
        }
    }
    catch { Write-Error $_ }
    Start-Sleep -Seconds $PollSec
}