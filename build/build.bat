@echo off
setlocal EnableDelayedExpansion

:: Local build script for Critter Quitters Pest Control.
:: Mirrors the GitHub Actions CI process so you can produce builds on your machine.
::
:: Prerequisites:
::   - Godot 4.5.1 Mono available as "godot" on your PATH
::   - Inno Setup 6 installed at the default location
::   - For Android builds: keystore at build\android_release.keystore
::     and keystore/release_password set in game\export_presets.cfg
::     (then run: git update-index --skip-worktree game\export_presets.cfg
::      so git ignores your local password change)
::
:: Run from the repository root: build\build.bat

set GODOT=godot
set ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe

:: ── Compute version stamp ────────────────────────────────────────────────────
for /f %%i in ('git rev-parse --short HEAD') do set SHA=%%i
if "!SHA!"=="" (
    echo ERROR: Could not read git SHA. Make sure you run this script from the repository root.
    exit /b 1
)
set VERSION=0.0.!SHA!

echo.
echo ================================================
echo  Critter Quitters Local Build   [!VERSION!]
echo ================================================
echo.

:: Ensure output directory exists
if not exist dist mkdir dist

:: ── Step 1: Windows export ───────────────────────────────────────────────────
echo [1/3] Exporting Windows build...
pushd game
!GODOT! --headless --export-release "Windows Desktop" "..\dist\critter_quitters_win.exe"
if !errorlevel! neq 0 (
    echo ERROR: Windows export failed.
    popd
    exit /b 1
)
popd
rename dist\critter_quitters_win.exe "critter_quitters_!SHA!_win.exe"
echo       Done: dist\critter_quitters_!SHA!_win.exe

:: ── Step 2: Windows installer ────────────────────────────────────────────────
echo [2/3] Building Inno Setup installer...
"!ISCC!" ^
    "/DAppVersion=!VERSION!" ^
    "/DSourceExe=%CD%\dist\critter_quitters_!SHA!_win.exe" ^
    "/DOutputDir=%CD%\dist" ^
    "/DOutputFilename=critter_quitters_setup_!SHA!" ^
    "%CD%\build\setup.iss"
if !errorlevel! neq 0 (
    echo ERROR: Installer build failed.
    exit /b 1
)
echo       Done: dist\critter_quitters_setup_!SHA!.exe

:: ── Step 3: Android export ───────────────────────────────────────────────────
echo [3/3] Exporting Android APK...

if not exist build\android_release.keystore (
    echo WARNING: build\android_release.keystore not found.
    echo          Skipping Android build.
    echo          See README or the Phase 4 setup instructions for keystore generation.
    goto :summary
)

pushd game
!GODOT! --headless --export-release "Android" "..\dist\critter_quitters.apk"
if !errorlevel! neq 0 (
    echo ERROR: Android export failed.
    popd
    exit /b 1
)
popd
rename dist\critter_quitters.apk "critter_quitters_!SHA!.apk"
echo       Done: dist\critter_quitters_!SHA!.apk

:summary
echo.
echo ── Build complete ──────────────────────────────────
dir /b dist\
echo ────────────────────────────────────────────────────
echo.
