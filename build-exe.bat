@echo off
REM ============================================================
REM  Build the standalone Windows EXE from bridge/ source.
REM  Produces dist\Bridge\ (Bridge.exe + runtime DLLs).
REM ============================================================
setlocal
set "PROJ=%~dp0"
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"
set "LOVE=C:\Program Files\LOVE"
if not exist "%LOVE%\love.exe" set "LOVE=C:\Program Files (x86)\LOVE"

echo [1/3] Building game.love from source...
powershell -NoProfile -Command ^
  "New-Item -ItemType Directory -Force '%PROJ%\dist\Bridge' | Out-Null;" ^
  "if (Test-Path '%PROJ%\dist\game.love') { Remove-Item '%PROJ%\dist\game.love' -Force };" ^
  "Compress-Archive -Path '%PROJ%\main.lua','%PROJ%\conf.lua','%PROJ%\src','%PROJ%\assets' -DestinationPath '%PROJ%\dist\game.zip' -Force;" ^
  "Move-Item '%PROJ%\dist\game.zip' '%PROJ%\dist\game.love' -Force"
if errorlevel 1 ( echo FAILED to build game.love & exit /b 1 )

echo [2/3] Fusing love.exe + game.love -^> Bridge.exe...
powershell -NoProfile -Command ^
  "$b=[System.IO.File]::ReadAllBytes('%LOVE%\love.exe')+[System.IO.File]::ReadAllBytes('%PROJ%\dist\game.love');" ^
  "[System.IO.File]::WriteAllBytes('%PROJ%\dist\Bridge\Bridge.exe',$b)"
if errorlevel 1 ( echo FAILED to fuse exe & exit /b 1 )

echo [3/4] Copying runtime DLLs...
for %%F in (SDL2.dll OpenAL32.dll love.dll lua51.dll mpg123.dll msvcp120.dll msvcr120.dll license.txt) do copy /Y "%LOVE%\%%F" "%PROJ%\dist\Bridge\" >nul

echo [4/4] Branding the EXE (icon + version strings)...
if exist "C:\Dev\rcedit.exe" (
  "C:\Dev\rcedit.exe" "%PROJ%\dist\Bridge\Bridge.exe" --set-icon "%PROJ%\assets\icon\Bridge.ico" --set-version-string ProductName "Bridge" --set-version-string FileDescription "Bridge" --set-version-string CompanyName "Whiteno1se" --set-version-string OriginalFilename "Bridge.exe"
) else (
  echo   [skip] C:\Dev\rcedit.exe not found - EXE keeps the default LOVE icon.
  echo          Get it from https://github.com/electron/rcedit/releases and save as C:\Dev\rcedit.exe
)

echo.
echo DONE.  Run:  %PROJ%\dist\Bridge\Bridge.exe
endlocal
