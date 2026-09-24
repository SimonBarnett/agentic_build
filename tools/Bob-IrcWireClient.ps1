# Send raw IRC wire lines (TOPIC, MODE). Test: BOB_IRC_WIRE_CAPTURE and/or BOB_IRC_WIRE_TCP_PORT.
param(
    [Parameter(Mandatory)][string]$Line,
    [string]$IrcHome,
    [string]$WireCapture
)

$ErrorActionPreference = 'Stop'
$t = ([string]$Line).Trim()
if (-not $t) { exit 0 }

function Write-BobIrcWireCapture {
    param([string]$Sent)
    $cap = $WireCapture
    if (-not $cap) { $cap = $env:BOB_IRC_WIRE_CAPTURE }
    if (-not $cap) { return }
    $dir = Split-Path $cap -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Add-Content -LiteralPath $cap -Value $Sent -Encoding utf8
}

function Send-BobIrcWireTcp {
    param([string]$HostName, [int]$Port, [string]$WireLine)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect($HostName, $Port)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true
        $writer.WriteLine($WireLine)
        Start-Sleep -Milliseconds 50
    }
    finally {
        try { $client.Close() } catch { }
    }
}

Write-BobIrcWireCapture -Sent $t

$tcpPort = 0
if ($env:BOB_IRC_WIRE_TCP_PORT -and $env:BOB_IRC_WIRE_TCP_PORT.Trim()) {
    try { $tcpPort = [int]$env:BOB_IRC_WIRE_TCP_PORT.Trim() } catch { $tcpPort = 0 }
}
if ($tcpPort -gt 0) {
    $tcpHost = '127.0.0.1'
    if ($env:BOB_IRC_WIRE_TCP_HOST -and $env:BOB_IRC_WIRE_TCP_HOST.Trim()) {
        $tcpHost = $env:BOB_IRC_WIRE_TCP_HOST.Trim()
    }
    Send-BobIrcWireTcp -HostName $tcpHost -Port $tcpPort -WireLine $t
    exit 0
}

if ($env:BOB_IRC_WIRE_SKIP_LIVE -eq '1') { exit 0 }

$ircHomeLocal = $IrcHome
if (-not $ircHomeLocal -and $env:BOB_IRC_HOME) { $ircHomeLocal = $env:BOB_IRC_HOME.Trim() }
if (-not $ircHomeLocal) { exit 0 }

$pwFile = Join-Path $env:USERPROFILE '.grok\ergo\connect.password'
if (-not (Test-Path $pwFile)) { exit 0 }
$pw = (Get-Content $pwFile -Raw).Trim()

$ircHost = '127.0.0.1'
$ircPort = 6697
$nick = 'bob-wire'
try {
    $cfgPath = $env:BOB_IRC_CONFIG
    if ($cfgPath -and (Test-Path $cfgPath)) {
        $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($cfg.host -and [string]$cfg.host -ne 'irc.libera.chat') { $ircHost = [string]$cfg.host }
        if ($cfg.port) { $ircPort = [int]$cfg.port }
        $mid = $env:BOB_MACHINE_ID
        if (-not $mid) { $mid = $env:COMPUTERNAME.ToLowerInvariant() }
        if ($cfg.nicks -and $mid -and $cfg.nicks.$mid) { $nick = [string]$cfg.nicks.$mid }
    }
}
catch { }
if ($env:BOB_IRC_HOST -and $env:BOB_IRC_HOST.Trim()) { $ircHost = $env:BOB_IRC_HOST.Trim() }

try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($ircHost, $ircPort)
    $net = $tcp.GetStream()
    $ssl = New-Object System.Net.Security.SslStream($net, $false, { $true })
    $ssl.AuthenticateAsClient($ircHost)
    $w = New-Object System.IO.StreamWriter($ssl, [Text.Encoding]::UTF8)
    $w.NewLine = "`r`n"
    $w.AutoFlush = $true
    $r = New-Object System.IO.StreamReader($ssl, [Text.Encoding]::UTF8)
    $w.WriteLine("PASS $pw")
    $w.WriteLine("NICK $nick")
    $w.WriteLine("USER $nick 0 * :bob-wire")
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    $ready = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not $ssl.CanRead) { break }
        if ($r.Peek() -ge 0) {
            $ln = $r.ReadLine()
            if ($ln -match '^:\S+\s+001\s') { $ready = $true; break }
        }
        Start-Sleep -Milliseconds 40
    }
    if ($ready) {
        $w.WriteLine($t)
        Write-BobIrcWireCapture -Sent ("LIVE $t")
    }
    $ssl.Close()
    $tcp.Close()
}
catch {
    # live Ergo may be down in CI; capture path still records intent
}
