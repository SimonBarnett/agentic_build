# Digest chair Jeeves as SCM service BobJeeves (NSSM), Automatic, depends on BobIrcd.
# Boot: BobIrcd then BobJeeves. Restart-Service BobIrcd does not start dependents;
# follow with Start-Service BobJeeves.
# --home is ~\.agentic-irc-jeeves. The service sets BOB_DIGEST_HOME to
# ~\.agentic-irc-bobiverse (chair-outbox from bobcallback). Never the same path.
# nssm.exe lives in the Ergo root. Do not copy it from another product.
[CmdletBinding()]
param(
    [string]$ErgoRoot = 'C:\ai\ergo',
    [string]$ServiceName = 'BobJeeves',
    [string]$DependsOn = 'BobIrcd',
    [string]$RepoRoot,
    [string]$IrcRoot,
    [string]$JeevesHome,
    [string]$DigestHome,
    [string]$Nick,
    [string]$IrcHost,
    [int]$IrcPort = 0
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$cfgPath = Join-Path $RepoRoot 'config\bobiverse.json'
$cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
if (-not $Nick) { $Nick = [string]$cfg.chairNick }
if (-not $Nick.Trim()) { $Nick = 'Jeeves' }
$Nick = $Nick.Trim()
if (-not $IrcHost) { $IrcHost = [string]$cfg.host }
if (-not $IrcHost) { $IrcHost = 'irc.ntsa.uk' }
if ($IrcPort -le 0) {
    $IrcPort = 6697
    if ($cfg.port) { $IrcPort = [int]$cfg.port }
}
if (-not $JeevesHome) { $JeevesHome = Join-Path $env:USERPROFILE '.agentic-irc-jeeves' }
if (-not $DigestHome) { $DigestHome = Join-Path $env:USERPROFILE '.agentic-irc-bobiverse' }
$JeevesHome = [IO.Path]::GetFullPath($JeevesHome)
$DigestHome = [IO.Path]::GetFullPath($DigestHome)
if ($JeevesHome.TrimEnd('\') -eq $DigestHome.TrimEnd('\')) {
    throw 'Jeeves home must not be the bobiverse digest home (BOB_DIGEST_HOME)'
}
if (-not $IrcRoot) {
    if (Test-Path 'C:\ai\agentic_irc') { $IrcRoot = 'C:\ai\agentic_irc' }
    elseif (Test-Path 'D:\ai\agentic_irc') { $IrcRoot = 'D:\ai\agentic_irc' }
    else { $IrcRoot = Join-Path (Split-Path $RepoRoot -Parent) 'agentic_irc' }
}
$IrcRoot = [IO.Path]::GetFullPath($IrcRoot)
$agent = Join-Path $IrcRoot 'scripts\irc_agent.py'
if (-not (Test-Path -LiteralPath $agent)) { throw "missing $agent" }

$py = $null
foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe')
    )) {
    if (Test-Path -LiteralPath $c) { $py = $c; break }
}
if (-not $py) {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { $py = $cmd.Source }
}
if (-not $py) { throw 'python.exe not found (install Python 3.12+ for Jeeves)' }

$pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
if (-not (Test-Path -LiteralPath $pwFile)) {
    throw 'missing ~/.grok/ergo/connect.password (never commit it)'
}

$dep = Get-Service -Name $DependsOn -ErrorAction SilentlyContinue
if (-not $dep) { throw "$DependsOn is not installed. Run tools/Install-BobIrcd.ps1 first." }

$nssm = Join-Path $ErgoRoot 'nssm.exe'
if (-not (Test-Path -LiteralPath $nssm)) {
    throw "missing $nssm (NSSM must live in Ergo root; do not copy from other products)"
}
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$startScript = Join-Path $RepoRoot 'tools\Start-BobJeeves.ps1'
if (-not (Test-Path -LiteralPath $startScript)) { throw "missing $startScript" }
$logDir = Join-Path $JeevesHome 'logs'
New-Item -ItemType Directory -Force -Path $logDir, $DigestHome | Out-Null
$stdout = Join-Path $logDir 'service.log'

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing -and $existing.Status -eq 'Running') {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$binPath = "`"$nssm`""
$display = 'Bobiverse Jeeves (digest chair)'
if (-not $existing) {
    & sc.exe create $ServiceName binPath= $binPath start= auto depend= $DependsOn DisplayName= $display obj= LocalSystem
    if ($LASTEXITCODE -ne 0) { throw "sc create $ServiceName failed ($LASTEXITCODE)" }
} else {
    & sc.exe config $ServiceName binPath= $binPath start= auto depend= $DependsOn DisplayName= $display obj= LocalSystem
    if ($LASTEXITCODE -ne 0) { throw "sc config $ServiceName failed ($LASTEXITCODE)" }
}
& sc.exe description $ServiceName 'Digest chair Jeeves for #bobiverse. Depends on BobIrcd. Sets BOB_DIGEST_HOME.' | Out-Null
& sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/10000 | Out-Null

$appParams = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -JeevesHome `"$JeevesHome`" -DigestHome `"$DigestHome`" -PasswordFile `"$pwFile`" -IrcRoot `"$IrcRoot`" -Python `"$py`" -Nick `"$Nick`" -IrcHost `"$IrcHost`" -IrcPort $IrcPort"
$paramKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"
if (-not (Test-Path $paramKey)) { New-Item -Path $paramKey -Force | Out-Null }
New-ItemProperty -Path $paramKey -Name Application -Value $ps -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $paramKey -Name AppParameters -Value $appParams -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $paramKey -Name AppDirectory -Value $IrcRoot -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $paramKey -Name AppStdout -Value $stdout -PropertyType ExpandString -Force | Out-Null
New-ItemProperty -Path $paramKey -Name AppStderr -Value $stdout -PropertyType ExpandString -Force | Out-Null
$exitKey = Join-Path $paramKey 'AppExit'
if (-not (Test-Path $exitKey)) { New-Item -Path $exitKey -Force | Out-Null }
Set-ItemProperty -Path $exitKey -Name '(default)' -Value 'Restart'

Start-Service -Name $ServiceName
$ok = $false
foreach ($i in 1..20) {
    Start-Sleep -Seconds 1
    $svc = Get-Service -Name $ServiceName
    if ($svc.Status -eq 'Running') { $ok = $true; break }
}
if (-not $ok) { throw "$ServiceName did not come up (service=$( (Get-Service $ServiceName).Status ))" }

Write-Host "Service:  $ServiceName (Automatic, depends on $DependsOn, LocalSystem, NSSM)"
Write-Host "Nick:     $Nick"
Write-Host "Home:     $JeevesHome"
Write-Host "Digest:   BOB_DIGEST_HOME=$DigestHome"
Write-Host "Start:    Start-Service $ServiceName"
Write-Host "Recycle:  Restart-Service $DependsOn; Start-Service $ServiceName"
