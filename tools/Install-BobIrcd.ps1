# Private Ergo for #bobiverse on this ionos box as a Windows service (NSSM).
# Requires C:\ai\ergo (Ergo 2.19.1+), ircd.yaml, and nssm.exe in Ergo root.
# Replaces the old AtLogOn task BobIrcd-ionos. Do not register that task again.
[CmdletBinding()]
param(
    [string]$ErgoRoot = 'C:\ai\ergo',
    [string]$ServiceName = 'BobIrcd'
)

$ErrorActionPreference = 'Stop'
$exe = Join-Path $ErgoRoot 'ergo.exe'
$conf = Join-Path $ErgoRoot 'ircd.yaml'
$nssm = Join-Path $ErgoRoot 'nssm.exe'
$logDir = Join-Path $ErgoRoot 'logs'
$stdout = Join-Path $logDir 'service.log'
if (-not (Test-Path $exe)) { throw "missing $exe" }
if (-not (Test-Path $conf)) { throw "missing $conf" }
if (-not (Test-Path $nssm)) { throw "missing $nssm (NSSM must live in Ergo root; do not copy from other products)" }

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$oldTask = 'BobIrcd-ionos'
try { Stop-ScheduledTask -TaskName $oldTask -ErrorAction SilentlyContinue } catch { }
Unregister-ScheduledTask -TaskName $oldTask -Confirm:$false -ErrorAction SilentlyContinue

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing -and $existing.Status -eq 'Running') {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$binPath = "`"$nssm`""
$display = 'Bobiverse IRC (Ergo)'
if (-not $existing) {
    & sc.exe create $ServiceName binPath= $binPath start= auto DisplayName= $display obj= LocalSystem
    if ($LASTEXITCODE -ne 0) { throw "sc create $ServiceName failed ($LASTEXITCODE)" }
} else {
    & sc.exe config $ServiceName binPath= $binPath start= auto DisplayName= $display obj= LocalSystem
    if ($LASTEXITCODE -ne 0) { throw "sc config $ServiceName failed ($LASTEXITCODE)" }
}
& sc.exe description $ServiceName 'Private Ergo ircd for #bobiverse (irc.ntsa.uk:6697 TLS)' | Out-Null
& sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/10000 | Out-Null

$paramKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"
if (-not (Test-Path $paramKey)) {
    New-Item -Path $paramKey -Force | Out-Null
}
New-ItemProperty -Path $paramKey -Name Application -Value $exe -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $paramKey -Name AppParameters -Value 'run --conf ircd.yaml' -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $paramKey -Name AppDirectory -Value $ErgoRoot -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $paramKey -Name AppStdout -Value $stdout -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $paramKey -Name AppStderr -Value $stdout -PropertyType ExpandString -Force | Out-Null

$exitKey = Join-Path $paramKey 'AppExit'
if (-not (Test-Path $exitKey)) {
    New-Item -Path $exitKey -Force | Out-Null
}
Set-ItemProperty -Path $exitKey -Name '(default)' -Value 'Restart'

if (-not (Get-NetFirewallRule -DisplayName 'Bobiverse IRC TLS 6697' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Bobiverse IRC TLS 6697' -Direction Inbound -Protocol TCP -LocalPort 6697 -Action Allow -Profile Any | Out-Null
}

Start-Service -Name $ServiceName
$ok = $false
foreach ($i in 1..20) {
    Start-Sleep -Seconds 1
    $svc = Get-Service -Name $ServiceName
    $proc = Get-Process ergo -ErrorAction SilentlyContinue
    if ($svc.Status -eq 'Running' -and $proc) { $ok = $true; break }
}
if (-not $ok) { throw "$ServiceName did not come up (service=$( (Get-Service $ServiceName).Status ); ergo process missing)" }

Write-Host "Service:  $ServiceName (Automatic, LocalSystem, NSSM)"
Write-Host "Listen:   TLS :6697"
Write-Host "Start:    Start-Service $ServiceName"
Write-Host "Recycle:  Restart-Service $ServiceName"
Write-Host "Old task: $oldTask unregistered"
