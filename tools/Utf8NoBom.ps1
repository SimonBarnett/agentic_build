# FR #347: UTF-8 without BOM for repo files and outbox lines (PS5-safe).
# Dot-source or call from scripts. Prefer this over Set-Content/Out-File -Encoding UTF8
# (those write a BOM on Windows PowerShell 5).

function Get-Utf8NoBomEncoding {
    return New-Object System.Text.UTF8Encoding $false
}

function Read-Utf8NoBomFile {
    param(
        [Parameter(Mandatory)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Read-Utf8NoBomFile: missing $Path"
    }
    return [IO.File]::ReadAllText($Path, (Get-Utf8NoBomEncoding))
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Content, (Get-Utf8NoBomEncoding))
}

function Add-Utf8NoBomLine {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Line
    )
    $enc = Get-Utf8NoBomEncoding
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $payload = if ($Line.EndsWith("`n")) { $Line } else { $Line + "`n" }
    $bytes = $enc.GetBytes($payload)
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try {
        $fs.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $fs.Dispose()
    }
}
