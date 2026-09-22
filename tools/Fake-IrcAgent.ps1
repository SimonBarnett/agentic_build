# Test-pack IRC agent double: drains chair outbox PRIVMSG and outbox-wire via TCP/live wire (not forged JOIN).
param(
    [Parameter(Mandatory)][string]$IrcHome,
    [Parameter(Mandatory)][string]$Nick,
    [Parameter(Mandatory)][string]$Channel,
    [string]$SessionId
)

$ErrorActionPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $IrcHome | Out-Null
$posPath = Join-Path $IrcHome 'outbox.pos'
$outbox = Join-Path $IrcHome 'outbox.txt'
$wirePath = Join-Path $IrcHome 'outbox-wire.txt'

function Get-OutboxPos {
    if (-not (Test-Path $posPath)) { return 0 }
    try { return [int](Get-Content $posPath -Raw).Trim() } catch { return 0 }
}

function Set-OutboxPos {
    param([int]$Pos)
    Set-Content -LiteralPath $posPath -Value $Pos -Encoding utf8 -NoNewline
}

function Send-WireLine {
    param([string]$Line)
    $t = ([string]$Line).Trim()
    if (-not $t) { return $false }
    $client = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Bob-IrcWireClient.ps1'
    if (-not (Test-Path -LiteralPath $client)) { return $false }
    $exe = (Get-Command powershell.exe).Source
    & $exe -NoProfile -ExecutionPolicy Bypass -File $client -Line $t -IrcHome $IrcHome | Out-Null
    return ($LASTEXITCODE -eq 0)
}

while ($true) {
    if (Test-Path -LiteralPath $wirePath) {
        $wireLines = @(Get-Content -LiteralPath $wirePath -ErrorAction SilentlyContinue)
        if ($wireLines.Count -gt 0) {
            $keep = New-Object System.Collections.Generic.List[string]
            foreach ($wl in $wireLines) {
                if (Send-WireLine -Line $wl) { continue }
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
                if ($t.StartsWith('PRIVMSG ') -or $t.StartsWith('TOPIC ') -or $t.StartsWith('MODE ')) {
                    if (-not (Send-WireLine -Line $t)) { break }
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
