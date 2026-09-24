# Shop JOIN via TCP wire (Ergo test double or BOB_IRC_WIRE_TCP_PORT). No local forged JOIN.
param(
    [Parameter(Mandatory)][string]$SeatIrcHome,
    [Parameter(Mandatory)][string]$Nick,
    [Parameter(Mandatory)][string]$Channel,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$SessionId,
    [string]$WireTcpPort
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $SeatIrcHome | Out-Null
if ($WireTcpPort -and $WireTcpPort.Trim()) {
    $env:BOB_IRC_WIRE_TCP_PORT = $WireTcpPort.Trim()
}
else {
    $portFile = $null
    if ($env:BOB_IRC_HOME) { $portFile = Join-Path $env:BOB_IRC_HOME 'wire-tcp-port.txt' }
    if ($portFile -and (Test-Path -LiteralPath $portFile)) {
        try { $env:BOB_IRC_WIRE_TCP_PORT = (Get-Content -LiteralPath $portFile -Raw).Trim() } catch { }
    }
}
$ircLog = Join-Path $SeatIrcHome 'irc.log'
$joinedOk = Join-Path $SeatIrcHome 'joined.ok'

function Send-TcpLines {
    param([string[]]$Lines)
    $port = 0
    if ($env:BOB_IRC_WIRE_TCP_PORT -and $env:BOB_IRC_WIRE_TCP_PORT.Trim()) {
        try { $port = [int]$env:BOB_IRC_WIRE_TCP_PORT.Trim() } catch { $port = 0 }
    }
    if ($port -le 0) { return $false }
    $hostName = '127.0.0.1'
    if ($env:BOB_IRC_WIRE_TCP_HOST -and $env:BOB_IRC_WIRE_TCP_HOST.Trim()) {
        $hostName = $env:BOB_IRC_WIRE_TCP_HOST.Trim()
    }
    $client = New-Object System.Net.Sockets.TcpClient
    $client.Connect($hostName, $port)
    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8)
    $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
    $writer.NewLine = "`r`n"
    $writer.AutoFlush = $true
    $echoJoin = $null
    foreach ($ln in $Lines) {
        $writer.WriteLine($ln)
        Start-Sleep -Milliseconds 80
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($stream.DataAvailable) {
            $resp = $reader.ReadLine()
            if ($resp) {
                Add-Content -LiteralPath $ircLog -Value $resp -Encoding utf8
                if ($resp -match [regex]::Escape($Nick) -and $resp -match '\bJOIN\b') { $echoJoin = $resp }
            }
        }
        else { Start-Sleep -Milliseconds 40 }
        if ($echoJoin) { break }
    }
    $client.Close()
    return ($null -ne $echoJoin)
}

$chan = $Channel
if ($chan -and -not $chan.StartsWith('#')) { $chan = '#' + $chan }
$ok = Send-TcpLines -Lines @(
    "NICK $Nick",
    "USER $Nick 0 * :repo-pair-shop",
    "JOIN $chan"
)
if (-not $ok) {
    if (Test-Path -LiteralPath $ircLog) {
        $raw = Get-Content -LiteralPath $ircLog -Raw -ErrorAction SilentlyContinue
        if ($raw -and $raw -match [regex]::Escape($Nick) -and $raw -match '\bJOIN\b') { $ok = $true }
    }
}
if (-not $ok) { exit 1 }

Set-Content -LiteralPath $joinedOk -Value ([DateTime]::UtcNow.ToString('o')) -Encoding utf8 -NoNewline
$manifest = @{
    channel      = $chan
    nick         = $Nick
    sessionId    = $SessionId
    joinedAt     = [DateTime]::UtcNow.ToString('o')
    policy       = 'shop_only_no_bobiverse'
    joinKind     = 'irc_agent_worker'
    shopNickLive = $true
    ircAgentPid  = $PID
    seatIrcHome  = $SeatIrcHome
    joinProof    = 'wire_tcp'
}
($manifest | ConvertTo-Json -Compress) | Set-Content -LiteralPath $ManifestPath -Encoding utf8
exit 0
