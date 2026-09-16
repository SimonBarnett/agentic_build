# Off-DEV suite. Wrapper so tests/ holds BT0* as the freeze specifies.
& (Join-Path $PSScriptRoot '..\tools\Test-Pack.ps1') @args
exit $LASTEXITCODE
