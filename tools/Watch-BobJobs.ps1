# Pull worker for this machine. Logon task, not a Windows service.
# grok.exe runs as the Windows logon user (MSSQL integrated auth).
# Continuous mode spawns -Once children so inbox drains with no concurrent ceiling.
# Idle ticks still call Invoke-BobFleetTick so lastSeen stays fresh.
# This script may only call exported BobBridge cmdlets; private module functions are not in scope.
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
    $mid = $env:BOB_MACHINE_ID
    if (-not $mid) {
        $self = @(Get-BobMachines | Where-Object { [string]$_.hostname -eq $env:COMPUTERNAME }) | Select-Object -First 1
        if ($self) { $mid = [string]$self.id }
    }
    if (-not $mid) { return 0 }
    return @(Get-BobBuilds -Machine $mid -Lane inbox -ErrorAction SilentlyContinue).Count
}

$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir 'watch_bob_jobs.log'
function Write-JobsLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

$ps = (Get-Command powershell.exe).Source
$self = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
Write-JobsLog "poller start pid=$PID machine=$env:BOB_MACHINE_ID pollSec=$PollSec"

while ($true) {
    try {
        $n = Get-InboxCount
        if ($n -gt 0) {
            $arg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Once -RepoRoot `"$RepoRoot`""
            Start-Process -FilePath $ps -ArgumentList $arg -WindowStyle Hidden | Out-Null
            Start-Sleep -Seconds 2
            continue
        }
        Invoke-BobFleetTick | Out-Null
    }
    catch {
        Write-JobsLog ("tick error: " + $_.Exception.Message)
        Write-Warning $_
    }
    Start-Sleep -Seconds $PollSec
}
