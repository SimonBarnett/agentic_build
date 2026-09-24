# Minimal IRC wire test server for pack: accepts TCP lines, echoes server JOIN, logs all traffic.
param(
    [Parameter(Mandatory)][int]$Port,
    [string]$LogPath,
    [string]$WireCapture
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $LogPath) { $LogPath = Join-Path $env:TEMP 'bob-irc-tcp-test.log' }
if (-not $WireCapture) { $WireCapture = $env:BOB_IRC_WIRE_CAPTURE }

function Write-Log {
    param([string]$Line)
    $t = [DateTime]::UtcNow.ToString('o') + ' ' + $Line
    Add-Content -LiteralPath $LogPath -Value $t -Encoding utf8
    if ($WireCapture) {
        Add-Content -LiteralPath $WireCapture -Value ("LIVE $Line") -Encoding utf8
    }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$listener.Start()
Write-Log "LISTEN $Port"

while ($true) {
    if (-not $listener.Pending()) {
        Start-Sleep -Milliseconds 20
        continue
    }
    $client = $listener.AcceptTcpClient()
    try {
        $stream = $client.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
        $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true
        $nick = 'testnick'
        $deadline = [DateTime]::UtcNow.AddSeconds(1)
        while ($client.Connected -and [DateTime]::UtcNow -lt $deadline) {
            if (-not $stream.DataAvailable) {
                Start-Sleep -Milliseconds 15
                continue
            }
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            $t = $line.Trim()
            if (-not $t) { continue }
            Write-Log "RX $t"
            if ($t -match '^NICK\s+(\S+)') { $nick = $Matches[1] }
            if ($t -match '^JOIN\s+(\S+)') {
                $chan = $Matches[1]
                $echo = ":$nick!u@test JOIN $chan"
                $writer.WriteLine($echo)
                Write-Log "TX $echo"
            }
            elseif ($t -match '^TOPIC\s+' -or $t -match '^MODE\s+' -or $t -match '^PRIVMSG\s+') {
                Write-Log "TX $t"
            }
        }
    }
    catch { }
    finally {
        try { $client.Close() } catch { }
    }
}
