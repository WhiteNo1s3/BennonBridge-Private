# Android build configuration

Everything needed to reproduce `dist/Bridge.apk` from a clean machine.
The APK is built with the official [love-android](https://github.com/love2d/love-android)
project (11.x branch); the files in this folder are the only local
modifications applied on top of it.

## Toolchain

| Component | Version |
|---|---|
| love-android | branch `11.x` (tested at commit `07088ee`) |
| JDK | Temurin **17** (Gradle 8.1 rejects 21) |
| Android SDK | platform 34, build-tools (any recent) |
| NDK | **27.1.12297006** |
| Gradle | wrapper included in love-android (8.1) |

## Setup

```bat
git clone -b 11.x https://github.com/love2d/love-android C:\Dev\love-android
```

Then apply this folder's files onto the clone:

| This repo | Goes to |
|---|---|
| `android/gradle.properties` | `love-android/gradle.properties` — app name ("Bridge"), application id `com.shaltiel.bridge`, version, **sensorLandscape** orientation |
| `android/app-build.gradle` | `love-android/app/build.gradle` — pins `ndkVersion 27.1.12297006` |
| `android/res/drawable-*/love.png` | `love-android/app/src/main/res/drawable-*/love.png` — launcher icon at 5 densities (from `assets/Icon/Icon.png`) |

## Building

From the repo root, run **`build-apk.bat`** (paths at the top of the script:
`LOVEANDROID`, `JAVA_HOME`, `ANDROID_HOME`). It zips the game into
`game.love`, copies it to `love-android/app/src/embed/assets/`, runs the
`assembleEmbedNoRecordDebug` Gradle task, and drops the finished APK at
`dist/Bridge.apk`.

The Windows build is `build-exe.bat` (brands the LÖVE runtime with
`assets/Icon/Bridge.ico` **before** fusing `game.love` — rcedit strips
appended data, so the order matters).
