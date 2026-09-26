# FR #347: Write-Utf8NoBomFile / Add-Utf8NoBomLine never write a BOM.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot 'tools\Utf8NoBom.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('bt0utf8-347-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $f = Join-Path $tmp 'out.txt'
    # Include a real Unicode em dash (U+2014) without introducing mojibake markers.
    $content = 'hello ' + [char]0x2014 + " world`n"
    Write-Utf8NoBomFile -Path $f -Content $content
    $bytes = [IO.File]::ReadAllBytes($f)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'Write-Utf8NoBomFile wrote a UTF-8 BOM'
    }
    $text = Read-Utf8NoBomFile -Path $f
    if ($text -notmatch 'hello') { throw ('read back failed: ' + $text) }
    if ($text.IndexOf([char]0x2014) -lt 0) { throw 'em dash missing after write/read' }

    Add-Utf8NoBomLine -Path $f -Line 'second line'
    $bytes2 = [IO.File]::ReadAllBytes($f)
    if ($bytes2.Length -ge 3 -and $bytes2[0] -eq 0xEF -and $bytes2[1] -eq 0xBB -and $bytes2[2] -eq 0xBF) {
        throw 'Add-Utf8NoBomLine introduced a UTF-8 BOM'
    }

    # Contrast: PS5 Set-Content -Encoding utf8 typically BOMs (document for workers).
    $bad = Join-Path $tmp 'bom.txt'
    Set-Content -LiteralPath $bad -Value 'x' -Encoding utf8
    $bb = [IO.File]::ReadAllBytes($bad)
    $hasBom = ($bb.Length -ge 3 -and $bb[0] -eq 0xEF -and $bb[1] -eq 0xBB -and $bb[2] -eq 0xBF)
    if (-not $hasBom) {
        Write-Host 'NOTE: Set-Content -Encoding utf8 did not BOM on this host (PS7?); helper still required for PS5'
    }

    Write-Host 'PASS BT0 FR #347 utf8 no bom'
    exit 0
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
