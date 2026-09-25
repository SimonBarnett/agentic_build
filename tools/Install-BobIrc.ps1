# Join #bobiverse (MODE2 free moot) as this machine's builder nick.
# Not a Windows service. Starts hidden irc_agent.py; OPEN (chair) or JOIN.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MachineId,
    [string]$RepoRoot,
    [string]$IrcRoot,
    [switch]$Chair,
    [switch]$UpdateUserEnv
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
. (Join-Path $RepoRoot 'tools\BobInstallHelpers.ps1')
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
$mootChannel = [string]$cfg.channel
if (-not $mootChannel) { $mootChannel = '#bobiverse' }
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

# Non-secret config only; existing different values are kept unless -UpdateUserEnv.
[void](Set-BobInstallUserEnv -Name 'BOB_IRC_HOME' -Value $ircHome -Update:$UpdateUserEnv)
[void](Set-BobInstallUserEnv -Name 'AGENTIC_IRC_HOME' -Value $ircHome -Update:$UpdateUserEnv)
[void](Set-BobInstallUserEnv -Name 'BOB_IRC_NICK' -Value $nick -Update:$UpdateUserEnv)

$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
$agentChannels = $mootChannel
if (Test-Path $psd1) {
    Import-Module $psd1 -Force
    Compact-BobIrcOutbox -Home $ircHome
    $agentChannels = Get-BobIrcBuilderChannels -MachineId $MachineId
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
# FR #328: singleton ensure via supervisor (start if missing, cull extras). Does not restart a healthy single agent.
. (Join-Path $RepoRoot 'tools\Bob-IrcAgentSupervisor.ps1')
$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$savedIrcEnv = @{ pw = $env:AGENTIC_IRC_PASSWORD; dbg = $env:AGENTIC_IRC_DEBUG }
$env:AGENTIC_IRC_DEBUG = '1'
$pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
if (-not (Test-Path $pwFile)) {
    throw 'missing ~/.grok/ergo/connect.password (copy from ionos; never commit it)'
}
$env:AGENTIC_IRC_PASSWORD = (Get-Content $pwFile -Raw).Trim()
try {
    $ensureResult = Invoke-BobIrcAgentEnsure -Nick $nick -IrcHome $ircHome -Python $py -AgentPath $agent `
        -IrcRoot $IrcRoot -IrcHost $ircHost -IrcPort $ircPort -Channels $agentChannels -Hello "$MachineId-builder"
    Write-Host "Bob irc_agent ensure: $ensureResult"
    $health = Get-BobIrcAgentHealth -Nick $nick -IrcHome $ircHome -IrcRoot $IrcRoot
    Write-Host (Write-BobIrcAgentHealthLine -Health $health)
}
finally {
    $env:AGENTIC_IRC_PASSWORD = $savedIrcEnv.pw
    $env:AGENTIC_IRC_DEBUG = $savedIrcEnv.dbg
}

Start-Sleep -Seconds 3
$mootPy = Join-Path $IrcRoot 'scripts\moot.py'
$isChair = $Chair -or ($MachineId -eq 'flamingo')
$stPath = Join-Path $ircHome (Join-Path 'moot' ($mootId + '.json'))
if ($isChair -and -not (Test-Path $stPath)) {
    & $py $mootPy --home $ircHome open --id $mootId --nick $nick --channel $mootChannel --mode free --topic 'bobiverse fleet roster'
}
elseif (-not $isChair) {
    & $py $mootPy --home $ircHome join --id $mootId --nick $nick --channel $mootChannel
}

Write-Host "Bobiverse:  $mootChannel (+ shop via agent) moot=$mootId nick=$nick"
Write-Host "Home:       $ircHome"
Write-Host "Python:     $py"
Write-Host "Agent:      irc_agent.py (hidden, log ~/.grok/long-running-background-tasks/bobiverse_irc.log)"
Write-Host "Moot:       $(if ($isChair) { 'OPEN free (chair)' } else { 'JOIN' })"
Write-BobInstallEnvReport 'Install-BobIrc'
