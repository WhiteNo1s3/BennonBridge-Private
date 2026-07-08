@echo off
REM ============================================================
REM  Build the standalone Windows EXE from bridge/ source.
REM  Produces dist\Bridge\ (Bridge.exe + runtime DLLs).
REM
REM  IMPORTANT: the icon/version branding is applied to the bare
REM  love.exe BEFORE the game.love is appended. rcedit rewrites PE
REM  resources and would strip the appended .love if run on the
REM  already-fused exe, so order matters.
REM ============================================================
setlocal
set "PROJ=%~dp0"
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"
set "LOVE=C:\Program Files\LOVE"
if not exist "%LOVE%\love.exe" set "LOVE=C:\Program Files (x86)\LOVE"
set "OUT=%PROJ%\dist\Bridge"
set "ICO=%PROJ%\assets\Icon\Bridge.ico"
set "RCEDIT=C:\Dev\rcedit.exe"

echo [1/4] Building game.love from source...
powershell -NoProfile -Command ^
  "New-Item -ItemType Directory -Force '%OUT%' | Out-Null;" ^
  "if (Test-Path '%PROJ%\dist\game.love') { Remove-Item '%PROJ%\dist\game.love' -Force };" ^
  "Compress-Archive -Path '%PROJ%\main.lua','%PROJ%\conf.lua','%PROJ%\src','%PROJ%\assets' -DestinationPath '%PROJ%\dist\game.zip' -Force;" ^
  "Move-Item '%PROJ%\dist\game.zip' '%PROJ%\dist\game.love' -Force"
if errorlevel 1 ( echo FAILED to build game.love & exit /b 1 )

echo [2/4] Branding the LOVE runtime (icon set BEFORE fusing)...
copy /Y "%LOVE%\love.exe" "%OUT%\_base.exe" >nul
if exist "%RCEDIT%" (
  "%RCEDIT%" "%OUT%\_base.exe" --set-icon "%ICO%" --set-version-string ProductName "Bridge" --set-version-string FileDescription "Bridge" --set-version-string CompanyName "Shaltiel Enterprises" --set-version-string LegalCopyright "Copyright 2026 Shaltiel Enterprises - developed by WhiteNo1se" --set-version-string OriginalFilename "Bridge.exe"
) else (
  echo   [skip] %RCEDIT% not found - EXE keeps the default LOVE icon.
  echo          Get it from https://github.com/electron/rcedit/releases and save as %RCEDIT%
)

echo [3/4] Fusing runtime + game.love -^> Bridge.exe...
powershell -NoProfile -Command ^
  "$b=[System.IO.File]::ReadAllBytes('%OUT%\_base.exe')+[System.IO.File]::ReadAllBytes('%PROJ%\dist\game.love');" ^
  "[System.IO.File]::WriteAllBytes('%OUT%\Bridge.exe',$b)"
del "%OUT%\_base.exe" >nul 2>&1
if not exist "%OUT%\Bridge.exe" ( echo FAILED to fuse exe & exit /b 1 )

echo [4/4] Copying runtime DLLs...
for %%F in (SDL2.dll OpenAL32.dll love.dll lua51.dll mpg123.dll msvcp120.dll msvcr120.dll license.txt) do copy /Y "%LOVE%\%%F" "%OUT%\" >nul

echo.
echo DONE.  Run:  %OUT%\Bridge.exe
endlocal
