# Install / initialise the AgentMonitor watch-seat on this box. Not a Windows
# service. Triggered by the Bob Fleet tray "Agents" menu when a watch-seat
# agent (Cursor / Grok) is not yet installed, or run by hand / skill harvest.
# Deploys github.com/SimonBarnett/AgentMonitor into Desktop\Watch-AgentHealth
# (the Desktop shortcut target) and copies its watch-seat skills into
# ~\.grok\skills. Skill: agent-monitor-setup.
[CmdletBinding()]
param(
    [ValidateSet('cursor', 'grok', 'both')]
    [string]$Agent = 'both',
    [string]$Repo = 'https://github.com/SimonBarnett/AgentMonitor',
    [string]$DesktopDir
)

$ErrorActionPreference = 'Stop'
if (-not $DesktopDir) { $DesktopDir = [Environment]::GetFolderPath('Desktop') }
$dest = Join-Path $DesktopDir 'Watch-AgentHealth'

function Write-SetupLog([string]$m) {
    $logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    Add-Content -Path (Join-Path $logDir 'install_agent_monitor.log') `
        -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
    Write-Host $m
}

$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) { throw 'git is required to install AgentMonitor' }

if (Test-Path (Join-Path $dest '.git')) {
    Write-SetupLog "update AgentMonitor in $dest"
    & git -C $dest fetch --quiet origin
    & git -C $dest reset --hard origin/HEAD --quiet
}
else {
    New-Item -ItemType Directory -Force -Path $DesktopDir | Out-Null
    if (Test-Path $dest) {
        $bak = "$dest.bak-$([datetime]::Now.ToString('yyyyMMddHHmmss'))"
        Write-SetupLog "existing $dest -> $bak"
        Rename-Item -Path $dest -NewName $bak
    }
    Write-SetupLog "clone $Repo -> $dest"
    & git clone --quiet $Repo $dest
}

# Copy the AgentMonitor watch-seat skills into ~\.grok\skills so grok.exe /
# cursor discover them (agent-monitor, watch-seat).
$skillsSrc = Join-Path $dest '.grok\skills'
$skillsDst = Join-Path $env:USERPROFILE '.grok\skills'
if (Test-Path $skillsSrc) {
    New-Item -ItemType Directory -Force -Path $skillsDst | Out-Null
    foreach ($d in @(Get-ChildItem $skillsSrc -Directory -ErrorAction SilentlyContinue)) {
        $src = Join-Path $d.FullName 'SKILL.md'
        if (-not (Test-Path $src)) { continue }
        $target = Join-Path $skillsDst $d.Name
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Copy-Item -Path $src -Destination (Join-Path $target 'SKILL.md') -Force
        Write-SetupLog "skill $($d.Name) -> $target"
    }
}

$cmd = Join-Path $dest 'Watch-AgentHealth.cmd'
if (-not (Test-Path $cmd)) { throw "AgentMonitor deploy incomplete: missing $cmd" }

# Desktop + repo shortcuts: always -New; IconLocation = agent .exe (visible icons).
$pub = Join-Path $dest 'tools\Publish-DesktopShortcuts.ps1'
if (Test-Path -LiteralPath $pub) {
    Write-SetupLog 'publish Desktop shortcuts (always -New, exe icons)'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pub -MonitorDir $dest
}
else {
    Write-SetupLog 'Publish-DesktopShortcuts.ps1 missing - skip shortcut refresh'
}

Write-SetupLog ("AgentMonitor ready (agent=$Agent). Launch: `"$cmd`" <cursor|grok> [new|resume] [off] — default is new")
