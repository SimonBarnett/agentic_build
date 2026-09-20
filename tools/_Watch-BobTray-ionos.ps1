$ErrorActionPreference = "Continue"
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
  $_.CommandLine -and $_.CommandLine -match "Watch-BobTray" -and [int]$_.ProcessId -ne $PID
} | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
Start-Sleep -Milliseconds 600
$env:BOB_IRC_HOME = "C:\Users\Administrator\.agentic-irc-bobiverse"
$env:AGENTIC_IRC_HOME = "C:\Users\Administrator\.agentic-irc-bobiverse"
$env:BOB_MACHINE_ID = "ionos"
$env:BOB_BRIDGE_HOME = "C:\Users\Administrator\.grok\bob-bridge"
& "C:\ai\agentic_build\tools\Watch-BobTray.ps1"
