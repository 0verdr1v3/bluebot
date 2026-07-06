@echo off
:: Bluebot installer.
:: 1) Download the repo as a ZIP from GitHub and extract it.
:: 2) Open the extracted folder's "installer" folder.
:: 3) Double-click THIS file (it self-elevates to Administrator).
:: It runs entirely from these local files — nothing is downloaded from the
:: (private) repo.
setlocal

:: --- self-elevate to Administrator, preserving this script's folder ---
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator privileges...
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)

echo.
echo === Bluebot installer ===
echo Running setup from: %~dp0
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Bluebot.ps1"

echo.
if %errorlevel% neq 0 (
  echo Installer exited with an error. See the messages above.
) else (
  echo Installer finished.
)
pause
