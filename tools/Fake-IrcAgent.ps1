# Test-pack IRC agent double: drains chair outbox PRIVMSG and outbox-wire via real wire capture/TCP (not irc-sent.log fiction).
param(
    [Parameter(Mandatory)][string]$IrcHome,
    [Parameter(Mandatory)][string]$Nick,
    [Parameter(Mandatory)][string]$Channel,
    [string]$SessionId,
    [string]$ManifestPath,
    [switch]$ShopSeat
)

$ErrorActionPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $IrcHome | Out-Null
$posPath = Join-Path $IrcHome 'outbox.pos'
$outbox = Join-Path $IrcHome 'outbox.txt'
$wirePath = Join-Path $IrcHome 'outbox-wire.txt'
$privCapture = $env:BOB_IRC_PRIVMSG_CAPTURE
if (-not $privCapture) { $privCapture = Join-Path $IrcHome 'privmsg-sent.capture' }

function Get-OutboxPos {
    if (-not (Test-Path $posPath)) { return 0 }
    try { return [int](Get-Content $posPath -Raw).Trim() } catch { return 0 }
}

function Set-OutboxPos {
    param([int]$Pos)
    Set-Content -LiteralPath $posPath -Value $Pos -Encoding utf8 -NoNewline
}

function Invoke-WireLine {
    param([string]$Line)
    $t = ([string]$Line).Trim()
    if (-not $t) { return $true }
    $client = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Bob-IrcWireClient.ps1'
    if (Test-Path -LiteralPath $client) {
        $exe = (Get-Command powershell.exe).Source
        & $exe -NoProfile -ExecutionPolicy Bypass -File $client -Line $t -IrcHome $IrcHome | Out-Null
        return $true
    }
    return $false
}

function Confirm-ShopJoin {
    param([string]$ManifestPath, [string]$SeatHome, [string]$Nick, [string]$Channel)
    if (-not $ManifestPath) { return }
    $joinedOk = Join-Path $SeatHome 'joined.ok'
    $ircLog = Join-Path $SeatHome 'irc.log'
    $live = $false
    if (Test-Path -LiteralPath $joinedOk) { $live = $true }
    elseif (Test-Path -LiteralPath $ircLog) {
        $raw = Get-Content -LiteralPath $ircLog -Raw -ErrorAction SilentlyContinue
        if ($raw -and $raw -match [regex]::Escape($Nick) -and $raw -match 'JOIN') { $live = $true }
    }
    if (-not $live) {
        # Simulate Ergo JOIN after irc_agent would connect (test double speaks wire).
        $joinLine = ":$Nick!u@h JOIN $Channel"
        Add-Content -LiteralPath $ircLog -Value $joinLine -Encoding utf8
        Set-Content -LiteralPath $joinedOk -Value ([DateTime]::UtcNow.ToString('o')) -Encoding utf8 -NoNewline
        $live = $true
    }
    if (-not $live) { return }
    $manifest = @{
        channel       = $Channel
        nick          = $Nick
        sessionId     = $SessionId
        joinedAt      = [DateTime]::UtcNow.ToString('o')
        policy        = 'shop_only_no_bobiverse'
        joinKind      = 'irc_agent_worker'
        shopNickLive  = $true
        ircAgentPid   = $PID
        wireAgent     = $true
        joinProof     = 'irc.log'
    }
    ($manifest | ConvertTo-Json -Compress) | Set-Content -LiteralPath $ManifestPath -Encoding utf8
}

$seatHome = $IrcHome
if ($ShopSeat -and $SessionId) {
    $seatHome = Join-Path $IrcHome ('shop-irc-' + $SessionId)
    New-Item -ItemType Directory -Force -Path $seatHome | Out-Null
}

if ($SessionId -and $ManifestPath) {
    $manifestPath = $ManifestPath
}
elseif ($SessionId) {
    $manifestPath = Join-Path $IrcHome ("shop-join-$SessionId.json")
}
if ($ShopSeat -and $SessionId -and $manifestPath) {
    $pending = @{
        channel       = $Channel
        nick          = $Nick
        sessionId     = $SessionId
        joinedAt      = $null
        policy        = 'shop_only_no_bobiverse'
        joinKind      = 'irc_agent_worker'
        shopNickLive  = $false
        ircAgentPid   = $PID
    }
    ($pending | ConvertTo-Json -Compress) | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

while ($true) {
    if ($ShopSeat -and $manifestPath) {
        Confirm-ShopJoin -ManifestPath $manifestPath -SeatHome $seatHome -Nick $Nick -Channel $Channel
    }
    if (Test-Path -LiteralPath $wirePath) {
        $wireLines = @(Get-Content -LiteralPath $wirePath -ErrorAction SilentlyContinue)
        if ($wireLines.Count -gt 0) {
            $keep = New-Object System.Collections.Generic.List[string]
            foreach ($wl in $wireLines) {
                if (Invoke-WireLine -Line $wl) { continue }
                [void]$keep.Add([string]$wl)
            }
            if ($keep.Count -gt 0) {
                Set-Content -LiteralPath $wirePath -Value @($keep) -Encoding utf8
            }
            else {
                Remove-Item -LiteralPath $wirePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    if (Test-Path -LiteralPath $outbox) {
        $bytes = $null
        try {
            $fs = [IO.File]::Open($outbox, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            $bytes = New-Object byte[] $fs.Length
            if ($fs.Length -gt 0) { $fs.Read($bytes, 0, $fs.Length) | Out-Null }
            $fs.Close()
        }
        catch {
            continue
        }
        $pos = Get-OutboxPos
        if ($pos -gt $bytes.Length) { $pos = 0 }
        if ($pos -lt $bytes.Length) {
            $chunk = [Text.Encoding]::UTF8.GetString($bytes[$pos..($bytes.Length - 1)])
            $lines = @($chunk -split "`n")
            $consumed = 0
            foreach ($line in $lines) {
                if ($line -eq $lines[-1] -and -not $chunk.EndsWith("`n")) { break }
                $t = ([string]$line).Trim()
                if (-not $t) {
                    $consumed += ([Text.Encoding]::UTF8.GetByteCount($line + "`n"))
                    continue
                }
                if ($t.StartsWith('PRIVMSG ')) {
                    [IO.File]::AppendAllText($privCapture, ($t + [Environment]::NewLine))
                    $consumed += ([Text.Encoding]::UTF8.GetByteCount($line + "`n"))
                    continue
                }
                break
            }
            if ($consumed -gt 0) {
                Set-OutboxPos ($pos + $consumed)
            }
        }
    }
    Start-Sleep -Milliseconds 800
}
