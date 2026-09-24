@echo off
setlocal
if "%~1"=="" (
    echo Usage: %~nx0 grok ^| cursor [new^|resume] [off]
    echo   default / new: fresh session + skills + prompt
    echo   resume:        rare recovery only - reuse stored session id
    echo   extra:         run again while one is live - next free slot, does not restart
    echo   hidden:        %~nx0 cursor off
    echo   Visible by default. off hides the watch console and agent TUI.
    exit /b 1
)
set "KIND=%~1"
set "HIDDEN=0"
set "WANT_NEW=1"
set "PSARGS=-WatchWorker"
if /i "%KIND%"=="cursor" set "PSARGS=%PSARGS% -Cursor"
if /i "%KIND%"=="grok" set "PSARGS=%PSARGS% -Grok"
if /i not "%KIND%"=="cursor" if /i not "%KIND%"=="grok" (
    echo Unknown kind "%KIND%" - use grok or cursor
    exit /b 1
)
if /i "%~2"=="resume" set "WANT_NEW=0"
if /i "%~2"=="new" set "WANT_NEW=1"
if /i "%~2"=="off" set "HIDDEN=1"
if /i "%~3"=="resume" set "WANT_NEW=0"
if /i "%~3"=="new" set "WANT_NEW=1"
if /i "%~3"=="off" set "HIDDEN=1"
if "%WANT_NEW%"=="1" set "PSARGS=%PSARGS% -New"
if "%HIDDEN%"=="1" (
    set "PSARGS=%PSARGS% -Windows off"
    wscript.exe //nologo "%~dp0Run-Hidden.vbs" "%~dp0Watch-AgentHealth.ps1" %PSARGS%
    echo Watch monitor started hidden. Log: %USERPROFILE%\Desktop\Watch-AgentHealth\Watch-AgentHealth.log
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Watch-AgentHealth.ps1" %PSARGS%
exit /b 0
