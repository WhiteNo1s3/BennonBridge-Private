@echo off
REM ============================================================
REM  Bridge - launch script for Windows (LOVE2D)
REM  Double-click this file, or run from cmd: run.bat
REM
REM  Uses lovec.exe (the console variant of LOVE) so Lua errors
REM  print into the same window instead of dying silently.
REM ============================================================

setlocal enabledelayedexpansion

REM --- locate a LOVE runtime (prefer console build, fall back to GUI) ---
set "LOVE="
for %%P in (
    "C:\Dev\love-windows-build\lovec.exe"
    "C:\Program Files\LOVE\lovec.exe"
    "C:\Program Files (x86)\LOVE\lovec.exe"
    "C:\Dev\love-windows-build\love.exe"
    "C:\Program Files\LOVE\love.exe"
    "C:\Program Files (x86)\LOVE\love.exe"
) do (
    if "!LOVE!"=="" if exist %%P set "LOVE=%%~P"
)

if "%LOVE%"=="" (
    echo [run.bat] Could not find lovec.exe or love.exe.
    echo Edit run.bat and add the full path of love^(c^).exe to the search list.
    pause
    exit /b 1
)

REM --- kill any previous instance so we always see a fresh window ---
taskkill /IM love.exe  /F >nul 2>&1
taskkill /IM lovec.exe /F >nul 2>&1

set "GAMEDIR=%~dp0"
if "%GAMEDIR:~-1%"=="\" set "GAMEDIR=%GAMEDIR:~0,-1%"

echo [run.bat] Using   : %LOVE%
echo [run.bat] Game dir: %GAMEDIR%
echo.
echo (Close the game window to return to this prompt. Any Lua error
echo  message will appear above this line.)
echo.

"%LOVE%" "%GAMEDIR%"
set "EXITCODE=%ERRORLEVEL%"

echo.
echo [run.bat] LOVE exited with code %EXITCODE%.
if not "%EXITCODE%"=="0" pause

endlocal
exit /b %EXITCODE%
