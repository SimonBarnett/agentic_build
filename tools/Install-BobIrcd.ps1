# Private Ergo for #bobiverse on this ionos box. Not a Windows service.
# Requires C:\ai\ergo (Ergo 2.19.1+) and ircd.yaml already present.
[CmdletBinding()]
param(
    [string]$ErgoRoot = 'C:\ai\ergo'
)

$ErrorActionPreference = 'Stop'
$exe = Join-Path $ErgoRoot 'ergo.exe'
$conf = Join-Path $ErgoRoot 'ircd.yaml'
if (-not (Test-Path $exe)) { throw "missing $exe" }
if (-not (Test-Path $conf)) { throw "missing $conf" }

$taskName = 'BobIrcd-ionos'
$action = New-ScheduledTaskAction -Execute $exe -Argument 'run --conf ircd.yaml' -WorkingDirectory $ErgoRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
try { Start-ScheduledTask -TaskName $taskName } catch { }

if (-not (Get-NetFirewallRule -DisplayName 'Bobiverse IRC TLS 6697' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Bobiverse IRC TLS 6697' -Direction Inbound -Protocol TCP -LocalPort 6697 -Action Allow -Profile Any | Out-Null
}

Write-Host "Task:     $taskName"
Write-Host "Listen:   TLS :6697"
Write-Host "DNS:      add A irc.ntsa.uk -> 217.154.57.228 then issue a public cert (docs/bobiverse-ionos-ircd.md)"
