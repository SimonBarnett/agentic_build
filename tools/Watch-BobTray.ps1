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

function Add-RoundRect([System.Drawing.Drawing2D.GraphicsPath]$path, $x, $y, $w, $h, $r) {
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
}

# Font Awesome Free solid robot (CC BY 4.0), drawn at tray size.
function New-FaRobotIcon {
    param([System.Drawing.Color]$Badge)
    $sz = 16
    $bmp = New-Object System.Drawing.Bitmap $sz, $sz
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $fg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(232, 236, 241))
    $eye = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(28, 33, 40))
    $ant = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(232, 236, 241)), 1.2
    $g.DrawLine($ant, 8.0, 1.2, 8.0, 4.0)
    $g.FillEllipse($fg, 7.0, 0.4, 2.0, 2.0)
    $body = New-Object System.Drawing.Drawing2D.GraphicsPath
    Add-RoundRect $body 3.2 4.2 9.6 10.4 1.6
    $g.FillPath($fg, $body)
    $g.FillRectangle($fg, 1.6, 7.2, 1.8, 4.4)
    $g.FillRectangle($fg, 12.6, 7.2, 1.8, 4.4)
    $g.FillEllipse($eye, 5.1, 7.0, 2.2, 2.2)
    $g.FillEllipse($eye, 8.7, 7.0, 2.2, 2.2)
    if ($Badge.A -gt 0) {
        $br = New-Object System.Drawing.SolidBrush $Badge
        $g.FillEllipse($br, 10.2, 10.2, 5.2, 5.2)
        $br.Dispose()
    }
    $body.Dispose(); $fg.Dispose(); $eye.Dispose(); $ant.Dispose()
    $h = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($h)
    $clone = $icon.Clone()
    $g.Dispose(); $bmp.Dispose()
    return $clone
}

$iconIdle = New-FaRobotIcon -Badge ([System.Drawing.Color]::Transparent)
$iconAlertA = New-FaRobotIcon -Badge ([System.Drawing.Color]::FromArgb(220, 50, 47))
$iconAlertB = New-FaRobotIcon -Badge ([System.Drawing.Color]::FromArgb(255, 180, 0))
Write-TrayLog 'tray icon Font Awesome robot'

$script:attention = $false
$script:flashOn = $false
$script:lastAlerts = @()
$script:jobsPid = $null
$script:jobsOwned = $false
$script:hoverBody = 'Bob fleet'
$script:remainingPct = $null
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
        if ($null -eq $h.remaining_pct -or $h.remaining_pct -eq '') { $script:remainingPct = $null }
        else { $script:remainingPct = [int]$h.remaining_pct }
        $short = [string]$h.short
        if ($script:attention) { $short = '! ' + $short }
        if ($short.Length -gt 63) { $short = $short.Substring(0, 63) }
        $notify.Text = $short
        if ($titleLabel) {
            $titleLabel.Text = 'Bob fleet'
            if ($null -eq $script:remainingPct) { $barCaption.Text = 'Context remaining' }
            else { $barCaption.Text = ('Context remaining    {0}%' -f $script:remainingPct) }
            $jobsLabel.Text = $(if ($h.jobs -and $h.jobs.Count) {
                    ($h.jobs | ForEach-Object { '{0}   {1}   {2}   {3}' -f $_.machine, $_.repo, $_.duration, $_.state }) -join [Environment]::NewLine
                } else { 'No fleet jobs running' })
            $barPanel.Invalidate()
        }
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

$bg = [System.Drawing.Color]::FromArgb(22, 27, 34)
$fg = [System.Drawing.Color]::FromArgb(230, 237, 243)
$muted = [System.Drawing.Color]::FromArgb(139, 148, 158)
$tip = New-Object System.Windows.Forms.Form
$tip.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$tip.ControlBox = $false
$tip.ShowInTaskbar = $false
$tip.TopMost = $true
$tip.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$tip.BackColor = $bg
$tip.Padding = New-Object System.Windows.Forms.Padding 14
$tip.Width = 420
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.AutoSize = $true
$titleLabel.Font = New-Object System.Drawing.Font 'Segoe UI Semibold', 11
$titleLabel.ForeColor = $fg
$titleLabel.Text = 'Bob fleet'
$titleLabel.Location = New-Object System.Drawing.Point 14, 12
$barCaption = New-Object System.Windows.Forms.Label
$barCaption.AutoSize = $true
$barCaption.Font = New-Object System.Drawing.Font 'Segoe UI', 8.5
$barCaption.ForeColor = $muted
$barCaption.Text = 'Context remaining'
$barCaption.Location = New-Object System.Drawing.Point 14, 40
$barPanel = New-Object System.Windows.Forms.Panel
$barPanel.Location = New-Object System.Drawing.Point 14, 62
$barPanel.Size = New-Object System.Drawing.Size 392, 10
$barPanel.BackColor = $bg
$barPanel.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $track = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(48, 54, 61))
        $pathT = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RoundRect $pathT 0 0 $barPanel.Width 10 5
        $g.FillPath($track, $pathT)
        $pct = $script:remainingPct
        if ($null -ne $pct) {
            $w = [int](($barPanel.Width - 2) * [math]::Max(0, [math]::Min(100, $pct)) / 100)
            if ($w -lt 8 -and $pct -gt 0) { $w = 8 }
            $col = [System.Drawing.Color]::FromArgb(63, 185, 80)
            if ($pct -lt 40) { $col = [System.Drawing.Color]::FromArgb(210, 153, 34) }
            if ($pct -lt 10) { $col = [System.Drawing.Color]::FromArgb(248, 81, 73) }
            $fill = New-Object System.Drawing.SolidBrush $col
            $pathF = New-Object System.Drawing.Drawing2D.GraphicsPath
            Add-RoundRect $pathF 1 1 $w 8 4
            $g.FillPath($fill, $pathF)
            $pathF.Dispose(); $fill.Dispose()
        }
        $pathT.Dispose(); $track.Dispose()
    })
$jobsLabel = New-Object System.Windows.Forms.Label
$jobsLabel.AutoSize = $true
$jobsLabel.MaximumSize = New-Object System.Drawing.Size 392, 0
$jobsLabel.Font = New-Object System.Drawing.Font 'Segoe UI', 9
$jobsLabel.ForeColor = $fg
$jobsLabel.Location = New-Object System.Drawing.Point 14, 82
$jobsLabel.Text = 'No fleet jobs running'
$tip.Controls.Add($titleLabel)
$tip.Controls.Add($barCaption)
$tip.Controls.Add($barPanel)
$tip.Controls.Add($jobsLabel)
$tip.Add_Shown({
        $tip.Height = $jobsLabel.Bottom + 16
    })
$hideTip = New-Object System.Windows.Forms.Timer
$hideTip.Interval = 3200
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
        $tip.Height = [Math]::Max(110, $jobsLabel.Bottom + 16)
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
