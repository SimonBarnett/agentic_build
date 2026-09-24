@echo off
wscript.exe //nologo "%~dp0Run-Hidden.vbs" "%~dp0Watch-AgentHealth.ps1" -WatchWorker -Cursor -New -Windows off
