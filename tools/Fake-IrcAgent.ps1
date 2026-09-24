# Test-pack shop/bobiverse IRC agent: drains outbox with wire semantics (TOPIC/MODE/SHOPDESC) and PRIVMSG.
param(
    [Parameter(Mandatory)][string]$IrcHome,
    [Parameter(Mandatory)][string]$Nick,
    [Parameter(Mandatory)][string]$Channel,
    [string]$SessionId,
    [string]$ManifestPath
)

$ErrorActionPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $IrcHome | Out-Null
$wireLog = Join-Path $IrcHome 'irc-wire.log'
$sentLog = Join-Path $IrcHome 'irc-sent.log'
$posPath = Join-Path $IrcHome 'outbox.pos'
$outbox = Join-Path $IrcHome 'outbox.txt'
$wirePath = Join-Path $IrcHome 'outbox-wire.txt'

function Write-Wire {
    param([string]$Line)
    if (-not $Line) { return }
    Add-Content -LiteralPath $wireLog -Value ([DateTime]::UtcNow.ToString('o') + ' ' + $Line) -Encoding utf8
    Add-Content -LiteralPath $sentLog -Value $Line -Encoding utf8
}

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
    if ($t -match '^SHOPDESC\s+(\S+)\s+(.+)$') {
        $chan = $Matches[1]
        $repo = $Matches[2].Trim()
        $descPath = Join-Path $IrcHome 'shop-channel-descriptions.json'
        $map = @{}
        if (Test-Path $descPath) {
            try {
                $existing = Get-Content $descPath -Raw | ConvertFrom-Json
                foreach ($p in $existing.PSObject.Properties) { $map[[string]$p.Name] = [string]$p.Value }
            }
            catch { }
        }
        $map[$chan] = $repo
        ($map | ConvertTo-Json -Compress) | Set-Content -LiteralPath $descPath -Encoding utf8
        Write-Wire ("TOPIC $chan :$repo")
        return $true
    }
    if ($t -match '^TOPIC\s+' -or $t -match '^MODE\s+') {
        Write-Wire $t
        return $true
    }
    return $false
}

if ($SessionId -and $ManifestPath) {
    $manifestPath = $ManifestPath
}
elseif ($SessionId) {
    $manifestPath = Join-Path $IrcHome ("shop-join-$SessionId.json")
}
if ($SessionId -and $manifestPath) {
    $manifest = @{
        channel      = $Channel
        nick         = $Nick
        sessionId    = $SessionId
        joinedAt     = [DateTime]::UtcNow.ToString('o')
        policy       = 'shop_only_no_bobiverse'
        joinKind     = 'irc_agent'
        shopNickLive = $true
        ircAgentPid  = $PID
        wireAgent    = $true
    }
    ($manifest | ConvertTo-Json -Compress) | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

while ($true) {
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
        $bytes = [IO.File]::ReadAllBytes($outbox)
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
                    Write-Wire $t
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
