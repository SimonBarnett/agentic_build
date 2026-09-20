# Shared gh.exe discovery and MRB posting preflight (dot-sourced by Start-BobMrb*.ps1).
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'src\Private\Get-BobGh.ps1')
