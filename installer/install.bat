@echo off
:: Bluebot installer bootstrapper.
:: Double-click this file (or right-click > Run as administrator). It elevates,
:: downloads the installer, and runs it. That's the whole install.
setlocal

:: --- self-elevate to Administrator ---
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator privileges...
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)

set "BRANCH=claude/dreamy-thompson-2rkd15"
set "PS1=https://raw.githubusercontent.com/0verdr1v3/bluebot/%BRANCH%/installer/Install-Bluebot.ps1"

echo.
echo === Bluebot installer ===
echo Downloading and running the setup script...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $f=Join-Path $env:TEMP 'Install-Bluebot.ps1'; Invoke-WebRequest -UseBasicParsing '%PS1%' -OutFile $f; & $f"

echo.
if %errorlevel% neq 0 (
  echo Installer exited with an error. See the messages above.
) else (
  echo Installer finished.
)
pause
