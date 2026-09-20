# Hidden Bob Fleet tray watcher + system tray icon. Flashes on ACTION_REQUIRED.
# Title is Bob Fleet. Primary bar is weekly remaining (CLI billing log).
# Job list: every registered fleet machine (bundled registry + local store +
# read-only filesystem peer peek). Fail closed: unreachable / lastSeen stale.
# No WinRM. See docs/bob-fleet-peer-peek.md.
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

if (-not ('BobTrayUi.TipForm' -as [type])) {
    $refs = @(
        [System.Windows.Forms.Form].Assembly.Location,
        [System.Drawing.Point].Assembly.Location
    )
    Add-Type -ReferencedAssemblies $refs -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace BobTrayUi {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct NOTIFYICONIDENTIFIER {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public Guid guidItem;
    }
    public class IconRect {
        public int X;
        public int Y;
        public int Width;
        public int Height;
        public string Source;
        public bool Ok;
    }
    public static class Shell {
        [DllImport("shell32.dll")]
        public static extern int Shell_NotifyIconGetRect(ref NOTIFYICONIDENTIFIER identifier, out RECT iconLocation);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string lpszClass, string lpszWindow);
        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public const int SW_SHOWNOACTIVATE = 4;
        public const int SW_SHOWNA = 8;
        public const uint NIM_MODIFY = 1;
        public const uint NIF_TIP = 0x00000004;
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern bool Shell_NotifyIcon(uint dwMessage, ref NOTIFYICONDATA lpdata);
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct NOTIFYICONDATA {
            public int cbSize;
            public IntPtr hWnd;
            public uint uID;
            public uint uFlags;
            public uint uCallbackMessage;
            public IntPtr hIcon;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string szTip;
        }
        public static void ClearNotifyTip(IntPtr hWnd, uint uID) {
            NOTIFYICONDATA d = new NOTIFYICONDATA();
            d.cbSize = Marshal.SizeOf(typeof(NOTIFYICONDATA));
            d.hWnd = hWnd;
            d.uID = uID;
            d.uFlags = NIF_TIP;
            d.szTip = "";
            Shell_NotifyIcon(NIM_MODIFY, ref d);
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        public const int TTM_POP = 0x041C;
        public const int SW_HIDE = 0;
        public static void HideTooltipWindows() {
            IntPtr h = IntPtr.Zero;
            for (int i = 0; i < 16; i++) {
                h = FindWindowEx(IntPtr.Zero, h, "tooltips_class32", null);
                if (h == IntPtr.Zero) break;
                SendMessage(h, TTM_POP, IntPtr.Zero, IntPtr.Zero);
                ShowWindow(h, SW_HIDE);
            }
        }
        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;

        public static bool TryGetNotifyIconRect(IntPtr hWnd, uint uID, out RECT rect) {
            rect = new RECT();
            if (hWnd == IntPtr.Zero) return false;
            NOTIFYICONIDENTIFIER nid = new NOTIFYICONIDENTIFIER();
            nid.cbSize = (uint)Marshal.SizeOf(typeof(NOTIFYICONIDENTIFIER));
            nid.hWnd = hWnd;
            nid.uID = uID;
            nid.guidItem = Guid.Empty;
            int hr = Shell_NotifyIconGetRect(ref nid, out rect);
            return hr == 0 && (rect.Right - rect.Left) > 0 && (rect.Bottom - rect.Top) > 0;
        }

        public static bool TryGetTrayNotifyRect(out RECT rect) {
            rect = new RECT();
            IntPtr tray = FindWindow("Shell_TrayWnd", null);
            if (tray == IntPtr.Zero) return false;
            IntPtr area = FindWindowEx(tray, IntPtr.Zero, "TrayNotifyWnd", null);
            IntPtr target = area != IntPtr.Zero ? area : tray;
            return GetWindowRect(target, out rect) && (rect.Right - rect.Left) > 0;
        }

        public static IconRect QueryNotifyIconRect(IntPtr hWnd, uint uID) {
            IconRect r = new IconRect();
            RECT rect;
            if (TryGetNotifyIconRect(hWnd, uID, out rect)) {
                r.Ok = true;
                r.Source = "icon";
                r.X = rect.Left;
                r.Y = rect.Top;
                r.Width = rect.Right - rect.Left;
                r.Height = rect.Bottom - rect.Top;
                return r;
            }
            if (TryGetTrayNotifyRect(out rect)) {
                r.Ok = true;
                r.Source = "tray";
                r.X = rect.Left;
                r.Y = rect.Top;
                r.Width = rect.Right - rect.Left;
                r.Height = rect.Bottom - rect.Top;
                return r;
            }
            r.Ok = false;
            r.Source = "";
            return r;
        }
    }
    public class TipForm : Form {
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
                cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
                cp.ExStyle |= 0x00000008; // WS_EX_TOPMOST
                return cp;
            }
        }
        public bool ShowParkedAt(int x, int y) {
            this.Left = x;
            this.Top = y;
            if (!this.IsHandleCreated) this.CreateHandle();
            bool pos = Shell.SetWindowPos(
                this.Handle,
                Shell.HWND_TOPMOST,
                x,
                y,
                this.Width,
                this.Height,
                Shell.SWP_NOACTIVATE | Shell.SWP_SHOWWINDOW);
            this.Visible = true;
            if (!this.Visible) {
                Shell.ShowWindow(this.Handle, Shell.SW_SHOWNA);
                this.Visible = true;
            }
            if (!this.Visible) {
                Shell.ShowWindow(this.Handle, Shell.SW_SHOWNOACTIVATE);
                this.Visible = true;
            }
            return this.Visible && pos;
        }
    }
}
'@
}

Remove-Module BobBridge -ErrorAction SilentlyContinue
Import-Module $psd1 -Force

$watchJobs = Join-Path $RepoRoot 'tools\Watch-BobJobs.ps1'
$watchBobiverse = Join-Path $RepoRoot 'tools\Watch-Bobiverse.ps1'
$logDir = Join-Path $env:USERPROFILE '.grok\long-running-background-tasks'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir 'watch_bob_tray.log'

function Write-TrayLog([string]$m) {
    Add-Content -Path $logPath -Value ('{0:o} {1}' -f [datetime]::UtcNow, $m) -ErrorAction SilentlyContinue
}

function Get-BobNotifyIconRect {
    param([System.Windows.Forms.NotifyIcon]$NotifyIcon)
    try {
        $hWnd = [IntPtr]::Zero
        $id = [uint32]0
        $t = $NotifyIcon.GetType()
        $flags = [Reflection.BindingFlags]'Instance,NonPublic'
        $windowField = $t.GetField('window', $flags)
        $idField = $t.GetField('id', $flags)
        if ($windowField -and $idField) {
            $window = $windowField.GetValue($NotifyIcon)
            if ($window) {
                $hWnd = $window.Handle
                $id = [uint32]$idField.GetValue($NotifyIcon)
            }
        }
        $r = [BobTrayUi.Shell]::QueryNotifyIconRect($hWnd, $id)
        if ($r -and $r.Ok) {
            return [pscustomobject]@{
                X      = [int]$r.X
                Y      = [int]$r.Y
                Width  = [int]$r.Width
                Height = [int]$r.Height
                Source = [string]$r.Source
            }
        }
    }
    catch {
        Write-TrayLog ('icon rect error: ' + $_.Exception.Message)
    }
    return $null
}

function Test-BobTrayPointInRect {
    param($Point, $Rect, [int]$Pad = 0)
    if ($null -eq $Point -or $null -eq $Rect) { return $false }
    try {
        $x = [int]$Point.X
        $y = [int]$Point.Y
        $w = [int]$Rect.Width
        $h = [int]$Rect.Height
        if ($w -le 0 -or $h -le 0) { return $false }
        $left = [int]$Rect.X - $Pad
        $top = [int]$Rect.Y - $Pad
        $right = [int]$Rect.X + $w + $Pad
        $bottom = [int]$Rect.Y + $h + $Pad
        return ($x -ge $left -and $x -le $right -and $y -ge $top -and $y -le $bottom)
    }
    catch { return $false }
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
$iconContext = New-FaRobotIcon -Badge ([System.Drawing.Color]::FromArgb(210, 153, 34))
Write-TrayLog 'tray icon Font Awesome robot'

$script:attention = $false
$script:flashOn = $false
$script:lastAlerts = @()
$script:jobsPid = $null
$script:jobsOwned = $false
$script:hoverTitle = Get-BobTrayTitle
$script:hoverBody = $script:hoverTitle
$script:remainingPct = $null
$script:alertKind = 'none'
$script:iconRectCache = $null
$script:cardClosed = $false
$script:tileHost = $null
$script:cursorBmp = $null
$script:notifyTipText = ' '
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

function Test-IrcAgentUp {
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'irc_agent\.py' -and
            $_.CommandLine -match 'bobiverse'
        })
    return $hits
}

function Test-BobiverseWatcherUp {
    $hits = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'Watch-Bobiverse\.ps1'
        })
    return $hits
}

function Start-IrcWatcher {
    $hits = Test-BobiverseWatcherUp
    if ($hits.Count -gt 0) { return }
    if (-not (Test-Path $watchBobiverse)) { return }
    Write-TrayLog 'starting Watch-Bobiverse (automation, not a Grok session)'
    Start-Process -FilePath (Get-Command powershell.exe).Source `
        -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $watchBobiverse) `
        -WorkingDirectory $RepoRoot -WindowStyle Hidden | Out-Null
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
    Clear-BobNativeTip
    Write-TrayLog ($alerts -join ' | ')
}

function Update-Hover {
    try {
        $h = Get-BobTrayHover
        $script:hoverBody = [string]$h.body
        $script:hoverTitle = [string]$h.title
        if (-not $script:hoverTitle) { $script:hoverTitle = Get-BobTrayTitle }
        if ($null -eq $h.remaining_pct -or $h.remaining_pct -eq '') { $script:remainingPct = $null }
        else { $script:remainingPct = [int]$h.remaining_pct }
        $paint = Get-BobTrayBarPaint -RemainingPct $script:remainingPct -BarWidth 392
        $script:alertKind = Get-BobTrayAlertKind -Alerts $script:lastAlerts -RemainingPct $script:remainingPct
        $short = [string]$h.short
        if ($script:attention) { $short = '! ' + $short }
        if ($short.Length -gt 63) { $short = $short.Substring(0, 63) }
        $script:notifyTipText = $short
        Clear-BobNativeTip
        if ($titleLabel) {
            $titleLabel.Text = $script:hoverTitle
            if ($jobsLabel) { $jobsLabel.Text = $(if ($h.jobs_text) { [string]$h.jobs_text } else { '' }) }
            Rebuild-BobTrayTiles -Machines @($h.machines) -AccountName $h.account_name -AccountPct $h.account_remaining_pct
            if ($alertLabel) {
                $alertLabel.Text = ('alert: {0}' -f $script:alertKind)
                $yAlert = 40
                if ($script:tileHost) { $yAlert = $script:tileHost.Bottom + 8 }
                $alertLabel.Location = New-Object System.Drawing.Point 14, $yAlert
            }
            if ($tip.Visible -and $alertLabel) {
                $tip.Height = [Math]::Max(110, $alertLabel.Bottom + 16)
            }
            if (-not $script:attention -and -not $paint.pulse -and $notify.Icon -ne $iconIdle) {
                $notify.Icon = $iconIdle
            }
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

function Clear-BobNativeTip {
    try {
        $flags = [Reflection.BindingFlags]'NonPublic,Instance'
        $w = $notify.GetType().GetField('window', $flags)
        $id = $notify.GetType().GetField('id', $flags)
        if (-not $w -or -not $id) { $notify.Text = ' '; return }
        $nw = $w.GetValue($notify)
        if (-not $nw) { $notify.Text = ' '; return }
        $hwnd = $nw.Handle
        $uid = [uint32]$id.GetValue($notify)
        [BobTrayUi.Shell]::ClearNotifyTip($hwnd, $uid)
        [BobTrayUi.Shell]::HideTooltipWindows()
        $notify.Text = ''
    }
    catch {
        try { $notify.Text = '' } catch { try { $notify.Text = ' ' } catch { } }
        try { [BobTrayUi.Shell]::HideTooltipWindows() } catch { }
    }
}

function Hide-BobTrayCard {
    $script:cardClosed = $true
    try { $hideTip.Stop() } catch { }
    try { if ($tip.Visible) { $tip.Hide() } } catch { Write-TrayLog ('tip hide error: ' + $_.Exception.Message) }
    Clear-BobNativeTip
}

function New-BobTrayCursorBitmap {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $bmp.MakeTransparent()
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $pts = @(
        (New-Object System.Drawing.Point 2, 1),
        (New-Object System.Drawing.Point 2, 13),
        (New-Object System.Drawing.Point 5, 10),
        (New-Object System.Drawing.Point 8, 15),
        (New-Object System.Drawing.Point 10, 14),
        (New-Object System.Drawing.Point 7, 9),
        (New-Object System.Drawing.Point 12, 9)
    )
    $fill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(20, 20, 20), 1)
    $g.FillPolygon($fill, $pts)
    $g.DrawPolygon($pen, $pts)
    $pen.Dispose(); $fill.Dispose(); $g.Dispose()
    return $bmp
}

function Add-BobTrayUsageRow {
    param(
        [int]$X,
        [int]$Y,
        [string]$Heading,
        $RemainingPct,
        [int]$BarWidth,
        [System.Drawing.Image]$Icon
    )
    $nameFont = New-Object System.Drawing.Font 'Segoe UI Semibold', 9
    $iconW = 0
    if ($Icon) {
        $pic = New-Object System.Windows.Forms.PictureBox
        $pic.Image = $Icon
        $pic.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::CenterImage
        $pic.Size = New-Object System.Drawing.Size 16, 16
        $pic.BackColor = [System.Drawing.Color]::Transparent
        $pic.Location = New-Object System.Drawing.Point $X, ($Y + 2)
        $script:tileHost.Controls.Add($pic)
        $iconW = 20
    }
    $nm = New-Object System.Windows.Forms.Label
    $nm.AutoSize = $true
    $nm.Font = $nameFont
    $nm.ForeColor = $fg
    $nm.BackColor = [System.Drawing.Color]::Transparent
    $nm.Text = $Heading
    $nm.Location = New-Object System.Drawing.Point ($X + $iconW), $Y
    $script:tileHost.Controls.Add($nm)
    $barY = $Y + 20
    $barX = $X + $iconW
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Location = New-Object System.Drawing.Point $barX, $barY
    $bar.Size = New-Object System.Drawing.Size $BarWidth, 10
    $bar.BackColor = $bg
    $bar.Tag = $RemainingPct
    $bar.Visible = $true
    $bar.Add_Paint({
            param($s, $e)
            $p = Get-BobTrayBarPaint -RemainingPct $s.Tag -BarWidth $s.Width
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $track = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(48, 54, 61))
            $pathT = New-Object System.Drawing.Drawing2D.GraphicsPath
            Add-RoundRect $pathT 0 0 $s.Width 10 5
            $g.FillPath($track, $pathT)
            if ($p.known -and $p.show_fill -and $null -ne $p.fill_width -and $p.fill_width -gt 0) {
                $col = [System.Drawing.Color]::FromArgb([int]$p.fill_r, [int]$p.fill_g, [int]$p.fill_b)
                $fill = New-Object System.Drawing.SolidBrush $col
                $pathF = New-Object System.Drawing.Drawing2D.GraphicsPath
                Add-RoundRect $pathF 1 1 $p.fill_width 8 4
                $g.FillPath($fill, $pathF)
                $pathF.Dispose(); $fill.Dispose()
            }
            $pathT.Dispose(); $track.Dispose()
        })
    $script:tileHost.Controls.Add($bar)
    return ($barY + 14)
}

function Rebuild-BobTrayTiles {
    param($Machines, $AccountName, $AccountPct)
    if (-not $script:tileHost) { return }
    $script:tileHost.Controls.Clear()
    $y = 0
    $jobFont = New-Object System.Drawing.Font 'Segoe UI', 9
    if (-not $script:cursorBmp) { $script:cursorBmp = New-BobTrayCursorBitmap }
    $acctLabel = 'n/a'
    if ($null -ne $AccountPct -and [string]$AccountPct -ne '') { $acctLabel = ('{0}%' -f [int]$AccountPct) }
    $acctName = 'cursor'
    if ($AccountName) { $acctName = [string]$AccountName }
    $y = Add-BobTrayUsageRow -X 0 -Y $y -Heading ('{0} ({1})' -f $acctName, $acctLabel) `
        -RemainingPct $AccountPct -BarWidth 372 -Icon $script:cursorBmp
    $y += 6
    $indent = 18
    foreach ($m in @($Machines)) {
        if (-not $m) { continue }
        $id = [string]$m.id
        $pct = $m.remaining_pct
        $pctLabel = 'n/a'
        if ($null -ne $pct -and [string]$pct -ne '') { $pctLabel = ('{0}%' -f [int]$pct) }
        $y = Add-BobTrayUsageRow -X $indent -Y $y -Heading ('{0} ({1})' -f $id, $pctLabel) `
            -RemainingPct $pct -BarWidth 354 -Icon $null
        $reach = [string]$m.reach
        $jobTxt = ''
        if ($reach -eq 'not-in-moot' -or $reach -eq 'unreachable') { $jobTxt = 'not in moot' }
        elseif (@($m.jobs).Count -eq 0) {
            if ($reach -eq 'stale') { $jobTxt = 'lastSeen stale' }
            else { $jobTxt = 'no jobs' }
        }
        else {
            $bits = @()
            if ($reach -eq 'stale') { $bits += 'lastSeen stale' }
            foreach ($j in @($m.jobs)) {
                $bits += ('{0}  {1}  {2}' -f $j.repo, $j.duration, $j.state)
            }
            $jobTxt = ($bits -join "`n")
        }
        $jl = New-Object System.Windows.Forms.Label
        $jl.AutoSize = $true
        $jl.MaximumSize = New-Object System.Drawing.Size 392, 0
        $jl.Font = $jobFont
        $jl.ForeColor = $fg
        $jl.BackColor = [System.Drawing.Color]::Transparent
        $jl.Text = $jobTxt
        $jl.Location = New-Object System.Drawing.Point ($indent + 14), $y
        $script:tileHost.Controls.Add($jl)
        $nLines = @($jobTxt -split "`n").Count
        $y += [Math]::Max(18, (16 * $nLines) + 8)
    }
    $script:tileHost.Height = [Math]::Max(10, $y)
}

$bg = [System.Drawing.Color]::FromArgb(22, 27, 34)
$fg = [System.Drawing.Color]::FromArgb(230, 237, 243)
$muted = [System.Drawing.Color]::FromArgb(139, 148, 158)
$tip = New-Object BobTrayUi.TipForm
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
$titleLabel.Text = $script:hoverTitle
$titleLabel.Location = New-Object System.Drawing.Point 14, 12
$closeBtn = New-Object System.Windows.Forms.Label
$closeBtn.AutoSize = $true
$closeBtn.Text = 'X'
$closeBtn.Font = New-Object System.Drawing.Font 'Segoe UI Semibold', 10
$closeBtn.ForeColor = $muted
$closeBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
$closeBtn.Location = New-Object System.Drawing.Point 392, 10
$closeBtn.Add_Click({ Hide-BobTrayCard })
$barCaption = New-Object System.Windows.Forms.Label
$barCaption.AutoSize = $true
$barCaption.Font = New-Object System.Drawing.Font 'Segoe UI', 8.5
$barCaption.ForeColor = $muted
$barCaption.Text = 'Weekly remaining  n/a'
$barCaption.Location = New-Object System.Drawing.Point 14, 40
$barCaption.Visible = $false
$barPanel = New-Object System.Windows.Forms.Panel
$barPanel.Location = New-Object System.Drawing.Point 14, 62
$barPanel.Size = New-Object System.Drawing.Size 392, 10
$barPanel.BackColor = $bg
$barPanel.Visible = $false
$jobsLabel = New-Object System.Windows.Forms.Label
$jobsLabel.AutoSize = $true
$jobsLabel.MaximumSize = New-Object System.Drawing.Size 392, 0
$jobsLabel.Font = New-Object System.Drawing.Font 'Segoe UI', 9
$jobsLabel.ForeColor = $fg
$jobsLabel.Location = New-Object System.Drawing.Point 14, 62
$jobsLabel.Text = ''
$jobsLabel.Visible = $false
$script:tileHost = New-Object System.Windows.Forms.Panel
$script:tileHost.Location = New-Object System.Drawing.Point 14, 38
$script:tileHost.Size = New-Object System.Drawing.Size 392, 10
$script:tileHost.BackColor = $bg
$alertLabel = New-Object System.Windows.Forms.Label
$alertLabel.AutoSize = $true
$alertLabel.Font = New-Object System.Drawing.Font 'Segoe UI', 8
$alertLabel.ForeColor = $muted
$alertLabel.Location = New-Object System.Drawing.Point 14, 86
$alertLabel.Text = 'alert: none'
$tip.Controls.Add($titleLabel)
$tip.Controls.Add($closeBtn)
$tip.Controls.Add($barCaption)
$tip.Controls.Add($barPanel)
$tip.Controls.Add($jobsLabel)
$tip.Controls.Add($script:tileHost)
$tip.Controls.Add($alertLabel)
$tip.Add_Shown({
        $tip.Height = $alertLabel.Bottom + 16
    })
$hideTip = New-Object System.Windows.Forms.Timer
$hideTip.Interval = 3200
$hideTip.Add_Tick({
        try {
            if ($tip.Visible) { $tip.Hide() }
        }
        catch {
            Write-TrayLog ('tip hide error: ' + $_.Exception.Message)
        }
        $hideTip.Stop()
    })

function Show-BobTrayCard {
    param([string]$Reason = 'hover')
    try {
        if ($script:cardClosed -and $Reason -ne 'click') { return }
        if ($Reason -eq 'click') { $script:cardClosed = $false }
        if ($tip.Visible) { return }
        Clear-BobNativeTip
        # Paint from the last poll. Do not Get-BobTrayHover here: peer DNS/UNC
        # would freeze the UI and the native "P+ idle" tip would win.
        $bottom = $jobsLabel.Bottom
        if ($script:tileHost) { $bottom = $script:tileHost.Bottom }
        if ($alertLabel) { $bottom = $alertLabel.Bottom }
        $tip.Height = [Math]::Max(110, $bottom + 16)
        # NC-T01 / NC-D02: park once on first show. Do not update Location on later MouseMove.
        if (-not $tip.Visible) {
            $iconRect = $script:iconRectCache
            $pt = [System.Windows.Forms.Cursor]::Position
            $work = [System.Windows.Forms.Screen]::FromPoint($pt).WorkingArea
            $place = Get-BobTrayTipPlacement -TipWidth $tip.Width -TipHeight $tip.Height `
                -IconRect $iconRect -Cursor $pt -WorkArea $work -AlreadyVisible $false
            $tip.Location = New-Object System.Drawing.Point ([int]$place.x), ([int]$place.y)
            $shown = $false
            try {
                $shown = [bool]$tip.ShowParkedAt([int]$place.x, [int]$place.y)
            }
            catch {
                Write-TrayLog ("tip ShowParkedAt error reason=${Reason}: " + $_.Exception.Message)
            }
            # Do not call Form.Show() after ShowParkedAt — that is a second dialog.
            if (-not $tip.Visible) {
                Write-TrayLog ("tip show fail reason=$Reason visible=false handle=$($tip.IsHandleCreated) loc=$($tip.Left),$($tip.Top) src=$($place.source) parked=$shown")
            }
            else {
                Write-TrayLog ("tip show ok reason=$Reason src=$($place.source) loc=$($tip.Left),$($tip.Top) size=$($tip.Width)x$($tip.Height)")
            }
        }
    }
    catch {
        Write-TrayLog ("tip show error reason=${Reason}: " + $_.Exception.Message)
    }
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = $iconIdle
$notify.Visible = $false
$notify.Text = ''
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miStatus = $menu.Items.Add('Status')
$miAck = $menu.Items.Add('Acknowledge')
$miLog = $menu.Items.Add('Open log')
[void]$menu.Items.Add('-')
$miExit = $menu.Items.Add('Exit watcher')
$notify.ContextMenuStrip = $menu

$miStatus.Add_Click({
        Update-Hover
        Show-BobTrayCard -Reason 'click'
    })
$miAck.Add_Click({ Clear-Attention })
$miLog.Add_Click({ if (Test-Path $logPath) { Start-Process notepad.exe $logPath } })
$ctx = New-Object System.Windows.Forms.ApplicationContext
$miExit.Add_Click({ $ctx.ExitThread() })
$notify.Add_MouseClick({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            if ($script:attention) { Clear-Attention }
            Show-BobTrayCard -Reason 'click'
        }
    })
$notify.Add_MouseMove({
        Show-BobTrayCard -Reason 'hover'
    })

$flash = New-Object System.Windows.Forms.Timer
$flash.Interval = 450
$flash.Add_Tick({
        if (-not $script:attention) { return }
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
        $paint = Get-BobTrayBarPaint -RemainingPct $script:remainingPct
        if (-not $paint.pulse) { return }
        $notify.Icon = $iconContext
        $pulseOff.Stop(); $pulseOff.Start()
    })

$iconProbe = New-Object System.Windows.Forms.Timer
$iconProbe.Interval = 400
$iconProbe.Add_Tick({
        try {
            $script:iconRectCache = Get-BobNotifyIconRect $notify
            $pt = [System.Windows.Forms.Cursor]::Position
            if ($script:iconRectCache -and [string]$script:iconRectCache.Source -eq 'icon') {
                if (Test-BobTrayPointInRect $pt $script:iconRectCache -Pad 2) {
                    Show-BobTrayCard -Reason 'probe'
                }
                elseif ($script:cardClosed) {
                    $overTip = $false
                    if ($tip.Visible) {
                        $tipRect = @{ X = $tip.Left; Y = $tip.Top; Width = $tip.Width; Height = $tip.Height }
                        $overTip = Test-BobTrayPointInRect $pt $tipRect -Pad 4
                    }
                    if (-not $overTip) { $script:cardClosed = $false }
                }
            }
            if ($tip.Visible) {
                Clear-BobNativeTip
                $tipRect = @{ X = $tip.Left; Y = $tip.Top; Width = $tip.Width; Height = $tip.Height }
                if (Test-BobTrayPointInRect $pt $tipRect -Pad 4) {
                    $hideTip.Stop(); $hideTip.Start()
                }
            }
        }
        catch {
            Write-TrayLog ('icon probe error: ' + $_.Exception.Message)
        }
    })

Start-JobsWatcher
try { Start-IrcWatcher } catch { Write-TrayLog ('irc watcher: ' + $_.Exception.Message) }
Update-Hover
try { [void]$tip.Handle } catch { Write-TrayLog ('tip handle create fail: ' + $_.Exception.Message) }
$notify.Visible = $true
$flash.Start()
$poll.Start()
$pulse.Start()
$iconProbe.Start()
Write-TrayLog 'tray up'
[System.Windows.Forms.Application]::Run($ctx)
$poll.Stop(); $flash.Stop(); $pulse.Stop(); $pulseOff.Stop(); $hideTip.Stop(); $iconProbe.Stop()
$tip.Hide(); $tip.Dispose()
$notify.Visible = $false
$notify.Dispose()
if ($script:jobsOwned -and $script:jobsPid) {
    try { Stop-Process -Id $script:jobsPid -Force -ErrorAction SilentlyContinue } catch { }
}

