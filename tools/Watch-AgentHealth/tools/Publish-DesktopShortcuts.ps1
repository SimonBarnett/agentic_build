# Publish Desktop + repo shortcuts for AgentMonitor.
# CAST IRON: every link launches -New (skills + prompt). IconLocation = agent .exe.
[CmdletBinding()]
param(
    [string]$MonitorDir,
    [switch]$DesktopOnly
)

$ErrorActionPreference = 'Stop'
if (-not $MonitorDir) { $MonitorDir = $PSScriptRoot + '\..' }
$MonitorDir = (Resolve-Path -LiteralPath $MonitorDir).Path
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutsDir = Join-Path $MonitorDir 'shortcuts'
New-Item -ItemType Directory -Force -Path $shortcutsDir | Out-Null

function Resolve-AgentExe([string]$Kind) {
    if ($Kind -eq 'cursor') {
        foreach ($p in @(
                (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'),
                (Join-Path $env:LOCALAPPDATA 'Programs\Cursor\Cursor.exe'),
                (Join-Path ${env:ProgramFiles} 'Cursor\Cursor.exe')
            )) {
            if ($p -and (Test-Path -LiteralPath $p)) { return $p }
        }
    }
    else {
        foreach ($p in @(
                (Join-Path $env:LOCALAPPDATA 'Programs\Grok Bot\Grok Bot.exe'),
                (Join-Path $env:LOCALAPPDATA 'Programs\GrokBot\Grok Bot.exe')
            )) {
            if ($p -and (Test-Path -LiteralPath $p)) { return $p }
        }
    }
    return $null
}

function Write-AgentLnk {
    param(
        [string]$Path,
        [string]$Kind,
        [string]$Label
    )
    $ps1 = Join-Path $MonitorDir 'Watch-AgentHealth.ps1'
    $vbs = Join-Path $MonitorDir 'Run-Hidden.vbs'
    $exe = Resolve-AgentExe $Kind
    $kindFlag = if ($Kind -eq 'grok') { '-Grok' } else { '-Cursor' }
    $args = "//nologo `"$vbs`" `"$ps1`" -WatchWorker $kindFlag -New -Windows off"
    $w = New-Object -ComObject WScript.Shell
    $s = $w.CreateShortcut($Path)
    $s.TargetPath = (Join-Path $env:WINDIR 'System32\wscript.exe')
    $s.Arguments = $args
    $s.WorkingDirectory = $MonitorDir
    $s.Description = "Watch-AgentHealth $Label (always new session)"
    $s.WindowStyle = 7
    if ($exe) { $s.IconLocation = "$exe,0" }
    else {
        $fallback = Join-Path $env:WINDIR 'System32\shell32.dll,13'
        $s.IconLocation = $fallback
    }
    $s.Save()
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($s)
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($w)
}

$defs = @(
    @{ name = 'Watch AgentHealth - Cursor New.lnk'; kind = 'cursor'; label = 'Cursor New' }
    @{ name = 'Watch AgentHealth - Cursor Resume.lnk'; kind = 'cursor'; label = 'Cursor (legacy Resume name, still New)' }
    @{ name = 'Watch AgentHealth - Grok New.lnk'; kind = 'grok'; label = 'Grok New' }
    @{ name = 'Watch AgentHealth - Grok Resume.lnk'; kind = 'grok'; label = 'Grok (legacy Resume name, still New)' }
    @{ name = 'Watch-Agent Cursor New.lnk'; kind = 'cursor'; label = 'Cursor New' }
    @{ name = 'Watch-Agent Cursor Resume.lnk'; kind = 'cursor'; label = 'Cursor (legacy Resume name, still New)' }
    @{ name = 'Watch-Agent Grok New.lnk'; kind = 'grok'; label = 'Grok New' }
    @{ name = 'Watch-Agent Grok Resume.lnk'; kind = 'grok'; label = 'Grok (legacy Resume name, still New)' }
    @{ name = 'Watch-AgentHealth-Grok-Resume.lnk'; kind = 'grok'; label = 'Grok (legacy Resume name, still New)' }
)

foreach ($d in $defs) {
    $repoLnk = Join-Path $shortcutsDir $d.name
    Write-AgentLnk -Path $repoLnk -Kind $d.kind -Label $d.label
    $deskLnk = Join-Path $desktop $d.name
    Write-AgentLnk -Path $deskLnk -Kind $d.kind -Label $d.label
}

Write-Host "Published $($defs.Count) shortcuts (always -New; IconLocation=agent exe) -> $desktop and $shortcutsDir"
