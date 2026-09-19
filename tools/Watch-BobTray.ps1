# Hidden fleet watcher + system tray icon. Flashes on ACTION_REQUIRED.
# Replaces the blank Interactive PowerShell window. Not a Windows service.
# Requires powershell.exe -STA.
[CmdletBinding()]
param(
    [int]$PollSec = 30,
    [int]$StallSec = 600,
    [int]$HeartbeatStaleSec = 90,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Continue'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$psd1 = Join-Path $RepoRoot 'src\BobBridge.psd1'
if (-not (Test-Path $psd1)) { throw "missing $psd1" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Name Native -Namespace BobTray -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
'@
$hwnd = [BobTray.Native]::GetConsoleWindow()
if ($hwnd -ne [IntPtr]::Zero) { [void][BobTray.Native]::ShowWindow($hwnd, 0) }

Remove-Module BobBridge -ErrorAction SilentlyContinue
Import-Module $psd1 -Force

$watchJobs = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir 'watch_bob_tray.log'

function Write-TrayLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

function New-DotIcon([System.Drawing.Color]$fill) {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush $fill
    $g.FillEllipse($brush, 1, 1, 13, 13)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(40, 40, 40)), 1
    $g.DrawEllipse($pen, 1, 1, 13, 13)
    $h = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($h)
    $clone = $icon.Clone()
    $brush.Dispose(); $pen.Dispose(); $g.Dispose(); $bmp.Dispose()
    return $clone
}

$iconIdle = New-DotIcon ([System.Drawing.Color]::FromArgb(46, 160, 67))
$iconAlertA = New-DotIcon ([System.Drawing.Color]::FromArgb(220, 50, 47))
$iconAlertB = New-DotIcon ([System.Drawing.Color]::FromArgb(255, 180, 0))

$script:attention = $false
$script:flashOn = $false
$script:lastAlerts = @()
$script:jobsPid = $null
$script:jobsOwned = $false
$script:hoverBody = 'Bob fleet'
$script:remainingPct = 100
$seen = @{
    watcher_down = $false
    grokbot_down = $false
    inbox        = @{}
    running      = @{}
    stall        = @{}
}

function Test-JobsWatcherUp {
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'Watch-BobJobs\.ps1' -and
            $_.CommandLine -notmatch '(?i)-Once\b'
        })
    return $hits
}

function Start-JobsWatcher {
    $hits = Test-JobsWatcherUp
    if ($hits.Count -gt 0) {
        $script:jobsPid = [int]$hits[0].ProcessId
        $script:jobsOwned = $false
        return
    }
    $p = Start-Process -FilePath (Get-Command powershell.exe).Source `
        -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $watchJobs) `
        -WorkingDirectory $RepoRoot -WindowStyle Hidden -PassThru
    $script:jobsPid = $p.Id
    $script:jobsOwned = $true
    Write-TrayLog "started Watch-BobJobs pid=$($p.Id)"
}

function Set-Attention([string[]]$alerts) {
    $script:lastAlerts = @($alerts)
    $script:attention = $true
    $text = ($alerts | Select-Object -First 1)
    if ($text.Length -gt 60) { $text = $text.Substring(0, 60) }
    try { $notify.Text = $text } catch { }
    try {
        $notify.BalloonTipTitle = 'Bob fleet'
        $notify.BalloonTipText = (($alerts | Select-Object -First 3) -join "`n")
        $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
        $notify.ShowBalloonTip(8000)
    }
    catch { }
    Write-TrayLog ($alerts -join ' | ')
}

function Update-Hover {
    try {
        $h = Get-BobTrayHover
        $script:hoverBody = [string]$h.body
        if ($h.remaining_pct -ne $null) { $script:remainingPct = [int]$h.remaining_pct }
        $short = [string]$h.short
        if ($script:attention) { $short = '! ' + $short }
        if ($short.Length -gt 63) { $short = $short.Substring(0, 63) }
        $notify.Text = $short
        if ($tipLabel) { $tipLabel.Text = $script:hoverBody }
    }
    catch {
        Write-TrayLog ("hover error: " + $_.Exception.Message)
    }
}

function Clear-Attention {
    $script:attention = $false
    $script:flashOn = $false
    $notify.Icon = $iconIdle
    Update-Hover
}

$tip = New-Object System.Windows.Forms.Form
$tip.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$tip.ControlBox = $false
$tip.ShowInTaskbar = $false
$tip.TopMost = $true
$tip.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$tip.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
$tip.ForeColor = [System.Drawing.Color]::White
$tipLabel = New-Object System.Windows.Forms.Label
$tipLabel.AutoSize = $true
$tipLabel.MaximumSize = New-Object System.Drawing.Size 420, 0
$tipLabel.Font = New-Object System.Drawing.Font 'Consolas', 9
$tipLabel.ForeColor = [System.Drawing.Color]::White
$tipLabel.Padding = New-Object System.Windows.Forms.Padding 8
$tipLabel.Text = 'Bob fleet'
$tip.Controls.Add($tipLabel)
$hideTip = New-Object System.Windows.Forms.Timer
$hideTip.Interval = 2800
$hideTip.Add_Tick({ $tip.Hide(); $hideTip.Stop() })

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = $iconIdle
$notify.Visible = $true
$notify.Text = 'Bob fleet'
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miStatus = $menu.Items.Add('Status')
$miAck = $menu.Items.Add('Acknowledge')
$miLog = $menu.Items.Add('Open log')
[void]$menu.Items.Add('-')
$miExit = $menu.Items.Add('Exit watcher')
$notify.ContextMenuStrip = $menu

$miStatus.Add_Click({
        Update-Hover
        $notify.BalloonTipTitle = 'Bob fleet'
        $body = $script:hoverBody
        if ($body.Length -gt 250) { $body = $body.Substring(0, 250) }
        $notify.BalloonTipText = $body
        $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $notify.ShowBalloonTip(8000)
    })
$miAck.Add_Click({ Clear-Attention })
$miLog.Add_Click({ if (Test-Path $logPath) { Start-Process notepad.exe $logPath } })
$ctx = New-Object System.Windows.Forms.ApplicationContext
$miExit.Add_Click({ $ctx.ExitThread() })
$notify.Add_MouseClick({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            if ($script:attention) { Clear-Attention } else { $miStatus.PerformClick() }
        }
    })
$notify.Add_MouseMove({
        Update-Hover
        $tipLabel.Text = $script:hoverBody
        $tip.Width = $tipLabel.PreferredWidth + 16
        $tip.Height = $tipLabel.PreferredHeight + 16
        $pt = [System.Windows.Forms.Cursor]::Position
        $x = $pt.X - $tip.Width
        $y = $pt.Y - $tip.Height - 12
        if ($x -lt 0) { $x = 8 }
        if ($y -lt 0) { $y = 8 }
        $tip.Location = New-Object System.Drawing.Point $x, $y
        if (-not $tip.Visible) { $tip.Show() }
        $hideTip.Stop(); $hideTip.Start()
    })

$flash = New-Object System.Windows.Forms.Timer
$flash.Interval = 450
$flash.Add_Tick({
        if (-not $script:attention) {
            if ($notify.Icon -ne $iconIdle) { $notify.Icon = $iconIdle }
            return
        }
        $script:flashOn = -not $script:flashOn
        $notify.Icon = $(if ($script:flashOn) { $iconAlertA } else { $iconAlertB })
    })

$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = [Math]::Max(5000, $PollSec * 1000)
$poll.Add_Tick({
        try {
            Start-JobsWatcher
            $alerts = @(Get-BobStallAlerts -Seen $seen -StallSec $StallSec -HeartbeatStaleSec $HeartbeatStaleSec)
            if ($alerts.Count -gt 0) { Set-Attention $alerts }
            Update-Hover
        }
        catch {
            Write-TrayLog ("poll error: " + $_.Exception.Message)
        }
    })

$pulse = New-Object System.Windows.Forms.Timer
$pulse.Interval = 60000
$pulseOff = New-Object System.Windows.Forms.Timer
$pulseOff.Interval = 700
$pulseOff.Add_Tick({
        $pulseOff.Stop()
        if (-not $script:attention) { $notify.Icon = $iconIdle }
    })
$pulse.Add_Tick({
        if ($script:attention) { return }
        if ($null -eq $script:remainingPct) { return }
        if ([int]$script:remainingPct -ge 10) { return }
        $notify.Icon = $iconAlertA
        $pulseOff.Stop(); $pulseOff.Start()
    })

Start-JobsWatcher
Update-Hover
$flash.Start()
$poll.Start()
$pulse.Start()
Write-TrayLog 'tray up'
[System.Windows.Forms.Application]::Run($ctx)
$poll.Stop(); $flash.Stop(); $pulse.Stop(); $pulseOff.Stop(); $hideTip.Stop()
$tip.Hide(); $tip.Dispose()
$notify.Visible = $false
$notify.Dispose()
if ($script:jobsOwned -and $script:jobsPid) {
    try { Stop-Process -Id $script:jobsPid -Force -ErrorAction SilentlyContinue } catch { }
}
