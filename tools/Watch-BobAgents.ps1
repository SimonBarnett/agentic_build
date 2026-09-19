# Stall detector for this machine. Prints ACTION_REQUIRED / FAILED only.
# Logon-task watcher + Grok Bot WIP hangs. Not a Windows service.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [int]$StallSec = 600,
    [int]$HeartbeatStaleSec = 90,
    [string]$RepoRoot,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
if (-not (Test-Path $psd1)) { throw "missing $psd1" }

if (-not $LogPath) {
    $logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $LogPath = Join-Path $logDir ("watch_bob_agents_{0}.log" -f $PID)
}

Remove-Module BobBridge -ErrorAction SilentlyContinue
Import-Module $psd1 -Force

function Write-Diag([string]$m) {
    $line = '{0:o} {1}' -f [datetime]::UtcNow, $m
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
}

$seen = @{
    watcher_down = $false
    grokbot_down = $false
    inbox        = @{}
    running      = @{}
    stall        = @{}
}

Write-Diag "start poll=$PollSec stall=$StallSec heartbeat=$HeartbeatStaleSec"

while ($true) {
    try {
        foreach ($msg in @(Get-BobStallAlerts -Seen $seen -StallSec $StallSec -HeartbeatStaleSec $HeartbeatStaleSec)) {
            Write-Diag $msg
            Write-Output $msg
        }
    }
    catch {
        Write-Diag ("tick error: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
