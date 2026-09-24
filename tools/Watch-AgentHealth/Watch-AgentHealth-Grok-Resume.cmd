@echo off
REM Legacy name "Resume" — CAST IRON always -New (skills + prompt). Use CLI "resume" only for rare recovery.
wscript.exe //nologo "%~dp0Run-Hidden.vbs" "%~dp0Watch-AgentHealth.ps1" -WatchWorker -Grok -New -Windows off
