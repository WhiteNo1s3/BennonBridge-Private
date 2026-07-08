@echo off
REM ============================================================
REM  Build the Android APK from the current bridge/ source.
REM
REM  This is the "sync": editing files in this folder does NOT
REM  change the APK by itself. Run this script and it will:
REM    1. zip this folder into game.love
REM    2. copy that into the love-android embed assets
REM    3. build the APK with Gradle
REM    4. drop the finished APK at dist\Bridge.apk
REM
REM  Machine paths (edit these if you move things):
REM ============================================================
setlocal
set "PROJ=%~dp0"
if "%PROJ:~-1%"=="\" set "PROJ=%PROJ:~0,-1%"
set "LOVEANDROID=C:\Dev\love-android"
set "JAVA_HOME=C:\Dev\jdk17\jdk-17.0.19+10"
set "ANDROID_HOME=C:\Users\Ben\AppData\Local\Android\Sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"

echo [1/4] Building game.love from source...
powershell -NoProfile -Command ^
  "New-Item -ItemType Directory -Force '%PROJ%\dist' | Out-Null;" ^
  "if (Test-Path '%PROJ%\dist\game.love') { Remove-Item '%PROJ%\dist\game.love' -Force };" ^
  "Compress-Archive -Path '%PROJ%\main.lua','%PROJ%\conf.lua','%PROJ%\src','%PROJ%\assets' -DestinationPath '%PROJ%\dist\game.zip' -Force;" ^
  "Move-Item '%PROJ%\dist\game.zip' '%PROJ%\dist\game.love' -Force"
if errorlevel 1 ( echo FAILED to build game.love & exit /b 1 )

echo [2/4] Copying game.love into the Android project...
copy /Y "%PROJ%\dist\game.love" "%LOVEANDROID%\app\src\embed\assets\game.love" >nul

echo [3/4] Building SIGNED RELEASE APK with Gradle (this can take a minute)...
REM Release (not debug): a debuggable APK makes Android show a portrait
REM "App Compatibility" warning dialog on every launch — unshippable.
REM Signing config comes from love-android\keystore.properties (machine-only).
pushd "%LOVEANDROID%"
call "%LOVEANDROID%\gradlew.bat" assembleEmbedNoRecordRelease --console=plain
set "ERR=%ERRORLEVEL%"
popd
if not "%ERR%"=="0" ( echo BUILD FAILED ^(gradle exit %ERR%^) & exit /b %ERR% )

echo [4/4] Copying APK to dist\Bridge.apk...
copy /Y "%LOVEANDROID%\app\build\outputs\apk\embedNoRecord\release\app-embed-noRecord-release.apk" "%PROJ%\dist\Bridge.apk" >nul

echo.
echo DONE.  Install this on the phone:  %PROJ%\dist\Bridge.apk
endlocal
