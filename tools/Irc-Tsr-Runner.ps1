param(
    [Parameter(Mandatory)][string]$IrcHome,
    [Parameter(Mandatory)][string]$IrcRoot,
    [Parameter(Mandatory)][string]$Nick
)
$ErrorActionPreference = 'Continue'
$env:PYTHONIOENCODING = 'utf-8'
$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
$tsrLog = Join-Path $logDir "irc-tsr-$Nick.log"
$wakeLog = Join-Path $logDir "irc-tsr-$Nick-wake.jsonl"
$py = 'C:\Python\Python312\python.exe'
if (-not (Test-Path $py)) { $py = 'python' }
$listen = Join-Path $IrcRoot 'scripts\irc_listen.py'

function Write-IrcTsrProcessHeartbeat {
    Add-Content -Path $wakeLog -Value ('{0:o} PROCESS_HEARTBEAT' -f [datetime]::UtcNow)
}

Add-Content -Path $tsrLog -Value ('{0:o} TSR runner start nick={1} home={2}' -f [datetime]::UtcNow, $Nick, $IrcHome)
Write-IrcTsrProcessHeartbeat

$heartbeatJob = Start-Job -ScriptBlock {
    param($WakePath)
    while ($true) {
        Add-Content -Path $WakePath -Value ('{0:o} PROCESS_HEARTBEAT' -f [datetime]::UtcNow)
        Start-Sleep -Seconds 30
    }
} -ArgumentList $wakeLog

try {
    & $py -u $listen --home $IrcHome 2>&1 | ForEach-Object {
        $line = ($_ | Out-String).TrimEnd()
        if (-not $line) { return }
        if ($line -match '^FROM ') {
            $payload = @{ prompt = "IRC TSR: handle and reply on wire: $line"; line = $line; nick = $Nick } | ConvertTo-Json -Compress
            Add-Content -Path $wakeLog -Value $line
            Write-Output ('AGENT_LOOP_WAKE_irc-tsr ' + $payload)
        }
    }
}
finally {
    Stop-Job -Job $heartbeatJob -Force -ErrorAction SilentlyContinue
    Remove-Job -Job $heartbeatJob -Force -ErrorAction SilentlyContinue
}
