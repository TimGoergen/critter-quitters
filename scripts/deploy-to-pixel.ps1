# deploy-to-pixel.ps1
# Downloads the latest Critter Quitters APK from GitHub Releases and installs it
# on a connected Android device via ADB.
#
# Prerequisites:
#   - gh CLI authenticated (already configured at C:\Program Files\GitHub CLI\gh.exe)
#   - Android Platform Tools (adb.exe) - download from:
#     https://developer.android.com/tools/releases/platform-tools
#     Common install location: %LOCALAPPDATA%\Android\Sdk\platform-tools\
#   - USB debugging OR Wireless debugging enabled on the Pixel
#
# Usage:
#   .\deploy-to-pixel.ps1                     # installs the latest release
#   .\deploy-to-pixel.ps1 -Tag build-abc1234  # installs a specific build tag

param(
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"

$RepoSlug  = "TimGoergen/critter-quitters"
$GhCli     = "C:\Program Files\GitHub CLI\gh.exe"

# --- Locate adb.exe -------------------------------------------------------
# Check PATH first, then the standard Android Studio SDK location.
$AdbCmd  = Get-Command adb -ErrorAction SilentlyContinue
$AdbPath = if ($AdbCmd) { $AdbCmd.Source } else { $null }
if (-not $AdbPath) {
    $SdkAdb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
    if (Test-Path $SdkAdb) {
        $AdbPath = $SdkAdb
    }
}
if (-not $AdbPath) {
    Write-Error "adb.exe not found. Download Android Platform Tools from https://developer.android.com/tools/releases/platform-tools and place adb.exe in %LOCALAPPDATA%\Android\Sdk\platform-tools\"
    exit 1
}
Write-Host "Using adb: $AdbPath"

# --- Resolve the release tag -----------------------------------------------
if ($Tag -eq "") {
    Write-Host "Fetching latest release tag from $RepoSlug..."
    $Tag = & $GhCli release list --repo $RepoSlug --limit 1 --json tagName --jq ".[0].tagName"
    if (-not $Tag) {
        Write-Error "No releases found in $RepoSlug. Has CI run at least once?"
        exit 1
    }
}
Write-Host "Target release: $Tag"

# --- Download the APK -------------------------------------------------------
$TmpDir = Join-Path $env:TEMP "cq-deploy-$([System.IO.Path]::GetRandomFileName())"
New-Item -ItemType Directory -Path $TmpDir | Out-Null

Write-Host "Downloading APK..."
& $GhCli release download $Tag --repo $RepoSlug --pattern "*.apk" --dir $TmpDir
if ($LASTEXITCODE -ne 0) {
    Remove-Item $TmpDir -Recurse -Force
    Write-Error "gh release download failed"
    exit 1
}

$ApkFile = Get-ChildItem $TmpDir -Filter "*.apk" | Select-Object -First 1
if (-not $ApkFile) {
    Remove-Item $TmpDir -Recurse -Force
    Write-Error "No APK found in release assets for tag '$Tag'"
    exit 1
}
Write-Host "Downloaded: $($ApkFile.Name)"

# --- Check ADB device -------------------------------------------------------
$DeviceLines = & $AdbPath devices 2>&1 | Select-String "^\S+\s+device$"
if (-not $DeviceLines) {
    Remove-Item $TmpDir -Recurse -Force
    Write-Host ""
    Write-Host "No ADB device detected."
    Write-Host "  USB:  Connect Pixel via USB with USB debugging enabled (Settings > Developer options)."
    Write-Host "  WiFi: Settings > Developer options > Wireless debugging > Pair device with pairing code."
    Write-Host "        Run: adb pair <ip>:<port>  then  adb connect <ip>:<port>"
    exit 1
}

$Serial = @($DeviceLines | ForEach-Object { ($_ -split '\s+')[0] })[0]
Write-Host "ADB device: $Serial"
$DeviceFlag = @("-s", $Serial)

# --- Install APK -----------------------------------------------------------
Write-Host "Installing $($ApkFile.Name)..."
& $AdbPath @DeviceFlag install -r $ApkFile.FullName
if ($LASTEXITCODE -ne 0) {
    Remove-Item $TmpDir -Recurse -Force
    Write-Error "adb install failed (exit code $LASTEXITCODE)"
    exit 1
}

Remove-Item $TmpDir -Recurse -Force
Write-Host ""
Write-Host "Installed successfully. Launch Critter Quitters Pest Control on your Pixel."
