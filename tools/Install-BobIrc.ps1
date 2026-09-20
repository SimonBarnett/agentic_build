# Join #bobiverse (MODE2 free moot) as this machine's builder nick.
# Not a Windows service. Starts hidden irc_agent.py; OPEN (chair) or JOIN.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MachineId,
    [string]$RepoRoot,
    [string]$IrcRoot,
    [switch]$Chair
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
if (-not $IrcRoot) {
    if (Test-Path 'C:\ai\agentic_irc') { $IrcRoot = 'C:\ai\agentic_irc' }
    elseif (Test-Path 'D:\ai\agentic_irc') { $IrcRoot = 'D:\ai\agentic_irc' }
    else { $IrcRoot = Join-Path (Split-Path $RepoRoot -Parent) 'agentic_irc' }
}
$IrcRoot = [IO.Path]::GetFullPath($IrcRoot)
$cfgPath = Join-Path $RepoRoot 'config\bobiverse.json'
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$ircHome = Join-Path $env:USERPROFILE '.agentic-irc-bobiverse'
$nick = [string]$cfg.nicks.$MachineId
if (-not $nick) { $nick = 'bob-' + $MachineId }
$channel = [string]$cfg.channel
$mootId = [string]$cfg.mootId
$ircHost = [string]$cfg.host
$ircPort = 6697
if ($cfg.port) { $ircPort = [int]$cfg.port }
if (-not $ircHost -or $ircHost -eq 'irc.libera.chat') {
    throw 'config/bobiverse.json host must be the private IRC server (not irc.libera.chat)'
}
New-Item -ItemType Directory -Force -Path $ircHome | Out-Null

$py = $null
foreach ($c in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe')
    )) {
    if (Test-Path $c) { $py = $c; break }
}
if (-not $py) {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { $py = $cmd.Source }
}
if (-not $py) { throw 'python.exe not found (install Python 3.12+ for MODE2 irc_agent)' }

[Environment]::SetEnvironmentVariable('BOB_IRC_HOME', $ircHome, 'User')
[Environment]::SetEnvironmentVariable('AGENTIC_IRC_HOME', $ircHome, 'User')
[Environment]::SetEnvironmentVariable('BOB_IRC_NICK', $nick, 'User')
$env:BOB_IRC_HOME = $ircHome
$env:AGENTIC_IRC_HOME = $ircHome
$env:BOB_IRC_NICK = $nick

$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
if (Test-Path $psd1) {
    Import-Module $psd1 -Force
    Optimize-BobIrcOutbox -Home $ircHome
}

$ident = Join-Path $ircHome 'identity.json'
if (-not (Test-Path $ident)) {
    & $py (Join-Path $IrcRoot 'scripts\seal.py') genkey
    if ($LASTEXITCODE -ne 0) { throw 'seal.py genkey failed' }
}

$req = Join-Path $IrcRoot 'requirements.txt'
& $py -m pip install -q -r $req
if ($LASTEXITCODE -ne 0) { throw 'pip install cryptography failed' }

$agent = Join-Path $IrcRoot 'scripts\irc_agent.py'
$already = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine -match 'irc_agent\.py' -and $_.CommandLine -match [regex]::Escape($nick)
    })
if ($already.Count -eq 0) {
    $logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $env:AGENTIC_IRC_DEBUG = '1'
    $pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
    if (-not (Test-Path $pwFile)) {
        throw 'missing ~/.grok/ergo/connect.password (copy from ionos; never commit it)'
    }
    $env:AGENTIC_IRC_PASSWORD = (Get-Content $pwFile -Raw).Trim()
    Start-Process -FilePath $py -ArgumentList @(
        '-u', $agent,
        '--host', $ircHost,
        '--port', "$ircPort",
        '--nick', $nick,
        '--channel', $channel,
        '--home', $ircHome,
        '--announce-key',
        '--hello', "$MachineId-builder"
    ) -WorkingDirectory $IrcRoot -WindowStyle Hidden | Out-Null
}

Start-Sleep -Seconds 3
$mootPy = Join-Path $IrcRoot 'scripts\moot.py'
$isChair = $Chair -or ($MachineId -eq 'flamingo')
$stPath = Join-Path $ircHome (Join-Path 'moot' ($mootId + '.json'))
if ($isChair -and -not (Test-Path $stPath)) {
    & $py $mootPy --home $ircHome open --id $mootId --nick $nick --channel $channel --mode free --topic 'bobiverse fleet roster'
}
elseif (-not $isChair) {
    & $py $mootPy --home $ircHome join --id $mootId --nick $nick --channel $channel
}

Write-Host "Bobiverse:  $channel moot=$mootId nick=$nick"
Write-Host "Home:       $ircHome"
Write-Host "Python:     $py"
Write-Host "Agent:      irc_agent.py (hidden, log ~/.grok/long-running-background-tasks/bobiverse_irc.log)"
Write-Host "Moot:       $(if ($isChair) { 'OPEN free (chair)' } else { 'JOIN' })"
