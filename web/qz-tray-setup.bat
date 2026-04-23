@echo off
setlocal EnableDelayedExpansion

title Tulasi Stores - Chrome Print Setup

echo.
echo ========================================================
echo   Tulasi Stores - Chrome Silent Print Setup
echo   One-time setup for receipt printing without popups
echo ========================================================
echo.

:: ============================================================
:: STEP 1 - Check / Auto-install QZ Tray
:: ============================================================
echo [1/3] Checking QZ Tray installation...

set "QZ_EXE="
if exist "%ProgramFiles%\QZ Tray\qz-tray.exe"             set "QZ_EXE=%ProgramFiles%\QZ Tray\qz-tray.exe"
if exist "%LOCALAPPDATA%\Programs\QZ Tray\qz-tray.exe"    set "QZ_EXE=%LOCALAPPDATA%\Programs\QZ Tray\qz-tray.exe"
if exist "%APPDATA%\QZ Tray\qz-tray.exe"                  set "QZ_EXE=%APPDATA%\QZ Tray\qz-tray.exe"

if "%QZ_EXE%"=="" (
    echo.
    echo   [!] QZ Tray not found. Downloading installer automatically...
    echo       (About 100 MB - please wait)
    echo.

    set "QZ_INSTALLER=%TEMP%\qz-tray-installer.exe"
    set "QZ_PS1=%TEMP%\qz_download.ps1"

    :: Write a small PowerShell script to download the latest Windows x64 installer
    (
        echo $api = Invoke-RestMethod 'https://api.github.com/repos/qzind/tray/releases/latest'
        echo $asset = $api.assets ^| Where-Object { $_.name -match 'x86_64\.exe' } ^| Select-Object -First 1
        echo if (-not $asset) { Write-Error 'Could not find Windows installer in latest release'; exit 1 }
        echo Write-Host ('  Downloading ' + $asset.name + ' ...')
        echo Invoke-WebRequest -Uri $asset.browser_download_url -OutFile '%QZ_INSTALLER%' -UseBasicParsing
        echo Write-Host '  Download complete.'
    ) > "%QZ_PS1%"

    powershell -NoProfile -ExecutionPolicy Bypass -File "%QZ_PS1%"
    del "%QZ_PS1%" >nul 2>&1

    if not exist "%QZ_INSTALLER%" (
        echo.
        echo   [!] Download failed. Please install QZ Tray manually:
        echo       https://qz.io/download/
        echo.
        pause
        exit /b 1
    )

    echo.
    echo   Installing QZ Tray - please follow the installer wizard...
    echo   (Click Next through the wizard; setup will continue after it finishes)
    echo.
    start /wait "" "%QZ_INSTALLER%"
    del "%QZ_INSTALLER%" >nul 2>&1

    :: Re-check all locations after install
    set "QZ_EXE="
    if exist "%ProgramFiles%\QZ Tray\qz-tray.exe"             set "QZ_EXE=%ProgramFiles%\QZ Tray\qz-tray.exe"
    if exist "%LOCALAPPDATA%\Programs\QZ Tray\qz-tray.exe"    set "QZ_EXE=%LOCALAPPDATA%\Programs\QZ Tray\qz-tray.exe"
    if exist "%APPDATA%\QZ Tray\qz-tray.exe"                  set "QZ_EXE=%APPDATA%\QZ Tray\qz-tray.exe"

    if "%QZ_EXE%"=="" (
        echo   [!] Install not detected. Run this file again after installing.
        pause
        exit /b 1
    )
    echo   [OK] Installed: %QZ_EXE%
) else (
    echo       Found: %QZ_EXE%
)

:: ============================================================
:: STEP 2 - Start QZ Tray if it is not already running
:: ============================================================
echo [2/3] Checking QZ Tray service...

tasklist /FI "IMAGENAME eq qz-tray.exe" 2>NUL | find /I "qz-tray.exe" >NUL
if %ERRORLEVEL% NEQ 0 (
    echo       Starting QZ Tray...
    start "" "%QZ_EXE%"
    echo       Waiting for QZ Tray to initialise (8 seconds)...
    timeout /t 8 /nobreak >nul
) else (
    echo       QZ Tray is already running.
)

:: ============================================================
:: STEP 3 - Find and trust the QZ Tray certificate
::          Chrome on Windows uses the Windows certificate store,
::          so importing here removes the "Proceed anyway" warning.
:: ============================================================
echo [3/3] Trusting QZ Tray certificate for Chrome...

:: QZ Tray generates its cert on first run, usually in ~/.qz/certs/
set "CERT_PATH="
if exist "%USERPROFILE%\.qz\certs\root-ca.crt"    set "CERT_PATH=%USERPROFILE%\.qz\certs\root-ca.crt"
if exist "%APPDATA%\qz\certs\root-ca.crt"          set "CERT_PATH=%APPDATA%\qz\certs\root-ca.crt"
if exist "%LOCALAPPDATA%\qz\certs\root-ca.crt"     set "CERT_PATH=%LOCALAPPDATA%\qz\certs\root-ca.crt"

:: If not found yet, wait a bit longer (slow first-start) and retry
if "%CERT_PATH%"=="" (
    echo       Certificate not ready yet, waiting 6 more seconds...
    timeout /t 6 /nobreak >nul
    if exist "%USERPROFILE%\.qz\certs\root-ca.crt"  set "CERT_PATH=%USERPROFILE%\.qz\certs\root-ca.crt"
    if exist "%APPDATA%\qz\certs\root-ca.crt"        set "CERT_PATH=%APPDATA%\qz\certs\root-ca.crt"
    if exist "%LOCALAPPDATA%\qz\certs\root-ca.crt"   set "CERT_PATH=%LOCALAPPDATA%\qz\certs\root-ca.crt"
)

if "%CERT_PATH%"=="" (
    echo.
    echo   [!] Certificate file not found.
    echo.
    echo   Please try this manually:
    echo     1. Look for the QZ Tray icon in the taskbar (bottom-right, near clock)
    echo     2. Right-click it and choose "Show status" or wait for "Ready"
    echo     3. Run this file again
    echo.
    pause
    exit /b 1
)

echo       Certificate: %CERT_PATH%
echo       Importing into Windows Trusted Root store (no admin required)...

:: Use PowerShell Import-Certificate (CurrentUser store - Chrome trusts this)
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
  "try { $null = Import-Certificate -FilePath '%CERT_PATH%' -CertStoreLocation Cert:\CurrentUser\Root -ErrorAction Stop; exit 0 } catch { exit 1 }"

if %ERRORLEVEL% NEQ 0 (
    :: Fallback to certutil (also works for user store)
    certutil -addstore -user ROOT "%CERT_PATH%" >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        echo.
        echo   [!] Could not import certificate automatically.
        echo   Please follow the manual steps below:
        echo     1. Open Chrome and go to: https://localhost:8182
        echo     2. Click "Advanced" then "Proceed to localhost (unsafe)"
        echo     3. Come back to the app and click Refresh
        echo.
        pause
        exit /b 1
    )
)

:: ============================================================
:: ALL DONE
:: ============================================================
echo.
echo ========================================================
echo   Setup Complete!
echo ========================================================
echo.
echo   Chrome will now connect to QZ Tray with no warnings.
echo.
echo   Next steps in Tulasi Stores:
echo     1. Open Chrome and go to login-radha.web.app
echo     2. Settings ^> Hardware Settings
echo     3. Turn ON "Use QZ Tray for receipt printing"
echo     4. Select your thermal printer from the dropdown
echo     5. Tap "Test print"
echo.
echo   Press any key to close.
pause >nul
