# Keep IRC TSR alive. Poll; restart if the runner died, listen child is gone,
# or the runner is older than RestartAfterSec (stuck/deaf).
# Does NOT start Watch-CursorIrc or cursor-<id> extras.
[CmdletBinding()]
param(
    [int]$PollSec = 45,
    [int]$RestartAfterSec = 600,
    [string]$MachineId,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
if (-not $MachineId) { $MachineId = $env:BOB_MACHINE_ID }
if (-not $MachineId) { $MachineId = 'ionos' }

$ircHome = Join-Path $env:USERPROFILE '.agentic-irc-cursor'
if ($env:AGENTIC_IRC_CURSOR_HOME -and $env:AGENTIC_IRC_CURSOR_HOME.Trim()) {
    $ircHome = $env:AGENTIC_IRC_CURSOR_HOME.Trim()
}
$pidPath = Join-Path $ircHome 'coordinator.pid'
try { $coord = [int](Get-Content $pidPath -Raw).Trim() } catch { $coord = 0 }
$nick = if ($coord -gt 0) { '{0}-{1}' -f $MachineId, $coord } else { '{0}-coord' -f $MachineId }

$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir "watch-irc-tsr-$nick.log"
$tsrPidFile = Join-Path $logDir "irc-tsr-$nick.pid"
$startScript = Join-Path $RepoRoot 'tools\Start-IrcTsr.ps1'

function Write-TsrWatchLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

function Get-TsrRunnerPid {
    if (-not (Test-Path $tsrPidFile)) { return 0 }
    try { return [int](Get-Content $tsrPidFile -Raw).Trim() } catch { return 0 }
}

function Test-TsrHealthy {
    $rid = Get-TsrRunnerPid
    if ($rid -le 0) { return $false }
    $proc = Get-Process -Id $rid -ErrorAction SilentlyContinue
    if (-not $proc) { return $false }
    $listen = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -and $_.CommandLine -match 'irc_listen\.py' -and $_.CommandLine -match [regex]::Escape($ircHome)
        })
    if ($listen.Count -eq 0) { return $false }
    if ($RestartAfterSec -gt 0 -and $proc.StartTime) {
        $age = [int]((Get-Date) - $proc.StartTime).TotalSeconds
        if ($age -ge $RestartAfterSec) { return $false }
    }
    return $true
}

Write-TsrWatchLog "watch start poll=${PollSec}s restartAfter=${RestartAfterSec}s nick=$nick"
while ($true) {
    try {
        if (-not (Test-TsrHealthy)) {
            Write-TsrWatchLog 'TSR down or stale; Start-IrcTsr'
            & $startScript -MachineId $MachineId -IrcHome $ircHome 2>&1 | Out-Null
        }
    }
    catch {
        Write-TsrWatchLog ('tick error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
