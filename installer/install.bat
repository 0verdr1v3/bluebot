@echo off
:: Bluebot installer. Two ways to use it:
::   A) Download just this file and double-click it — it downloads the rest.
::   B) Download the repo ZIP, extract, and run this from the installer\ folder.
:: Either way it self-elevates to Administrator and does the full setup.
setlocal

:: --- self-elevate to Administrator, preserving this script's folder ---
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator privileges...
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)

set "BRANCH=claude/dreamy-thompson-2rkd15"
set "PS1URL=https://raw.githubusercontent.com/0verdr1v3/bluebot/%BRANCH%/installer/Install-Bluebot.ps1"

echo.
echo === Bluebot installer ===

if exist "%~dp0Install-Bluebot.ps1" (
  echo Running setup from local files: %~dp0
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Bluebot.ps1"
) else (
  echo Downloading setup script...
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; $f=Join-Path $env:TEMP 'Install-Bluebot.ps1'; Invoke-WebRequest -UseBasicParsing '%PS1URL%' -OutFile $f; & $f"
)

echo.
if %errorlevel% neq 0 (
  echo Installer exited with an error. See the messages above.
) else (
  echo Installer finished.
)
pause
