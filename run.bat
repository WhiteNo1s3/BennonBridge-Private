@echo off
REM ============================================================
REM  Bridge - launch script for Windows (LOVE2D)
REM  Double-click this file, or run from cmd: run.bat
REM ============================================================

setlocal

REM --- locate love.exe (try common install paths) ---
set "LOVE="
if exist "C:\Program Files\LOVE\love.exe"        set "LOVE=C:\Program Files\LOVE\love.exe"
if exist "C:\Program Files (x86)\LOVE\love.exe"  set "LOVE=C:\Program Files (x86)\LOVE\love.exe"
if exist "C:\Dev\love-windows-build\love.exe"    set "LOVE=C:\Dev\love-windows-build\love.exe"

if "%LOVE%"=="" (
    echo [run.bat] Could not find love.exe in the usual places.
    echo Edit run.bat and set LOVE= to the full path of love.exe.
    pause
    exit /b 1
)

REM --- kill any previous instance so we always see a fresh window ---
taskkill /IM love.exe /F >nul 2>&1

REM --- launch the game pointing at this folder, capture stderr ---
set "GAMEDIR=%~dp0"
if "%GAMEDIR:~-1%"=="\" set "GAMEDIR=%GAMEDIR:~0,-1%"

echo [run.bat] Launching: "%LOVE%" "%GAMEDIR%"
start "" "%LOVE%" "%GAMEDIR%" 2>"%GAMEDIR%\_err.txt"

endlocal
exit /b 0
