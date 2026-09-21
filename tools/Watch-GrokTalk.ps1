# Poll grok-inbox.jsonl and write grok-outbox.jsonl completions. Not inside Watch-Bobiverse.
# Short-lived grok.exe / Cursor / Grok Bot via Invoke-BobGrokTalkTick. Max 1 job per machine.
[CmdletBinding()]
param(
    [switch]$Once,
    [int]$PollSec = 15,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
if (-not (Test-Path $psd1)) { throw "missing $psd1" }

Remove-Module BobBridge -ErrorAction SilentlyContinue
Import-Module $psd1 -Force

$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir 'watch_grok_talk.log'
function Write-GrokTalkLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

if ($Once) {
    $r = Invoke-BobGrokTalkTick -Cwd $RepoRoot
    $r | ConvertTo-Json -Compress -Depth 6
    if ($r.error -eq 'no_fuel') { exit 2 }
    if (-not $r.ok -and $r.error) { exit 1 }
    exit 0
}

Write-GrokTalkLog "poller start pid=$PID pollSec=$PollSec"
while ($true) {
    try {
        $r = Invoke-BobGrokTalkTick -Cwd $RepoRoot
        if ($r.ok -and $r.job_id) {
            Write-GrokTalkLog "done job=$($r.job_id) fuel=$($r.fuel)"
        }
        elseif ($r.error -eq 'no_fuel') {
            Write-GrokTalkLog "no_fuel job=$($r.job_id) weekly=$($r.weekly) cursor=$($r.cursor)"
        }
        elseif ($r.error) {
            Write-GrokTalkLog "error=$($r.error) job=$($r.job_id) reason=$($r.reason)"
        }
    }
    catch {
        Write-GrokTalkLog ('tick error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSec
}
