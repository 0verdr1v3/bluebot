<#
.SYNOPSIS
  One-shot installer for bluebot on Windows. Enables WSL2, installs Docker in
  WSL, builds & activates a binder-enabled kernel, deploys the Android panel
  stack, and creates a desktop launcher.

.NOTES
  Run from an *Administrator* PowerShell:
    powershell -ExecutionPolicy Bypass -File .\Install-Bluebot.ps1

  Idempotent: safe to re-run. If a reboot is required for WSL, it tells you and
  resumes on the next run.
#>
[CmdletBinding()]
param(
  [string]$Distro    = "Ubuntu",
  [int]$ViewerPort   = 8000,
  [switch]$SkipKernel  # for hosts that already have a binder kernel
)

$ErrorActionPreference = "Stop"
function Info($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Die ($m){ Write-Host "XX $m" -ForegroundColor Red; exit 1 }

# --- must be admin ---
$admin = ([Security.Principal.WindowsPrincipal] `
  [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $admin) { Die "Please run this in an Administrator PowerShell." }

# This installer runs from a LOCAL copy of the repo (works even though the repo
# is private). The repo root is the parent of this installer\ folder.
$RepoRootWin = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $RepoRootWin "deploy.sh"))) {
  Die "Can't find the repo. Run this from the extracted repo's installer\ folder (deploy.sh not found beside it)."
}

function ConvertTo-WslPath($winPath) {
  $full = (Resolve-Path $winPath).Path
  $drive = $full.Substring(0,1).ToLower()
  $rest  = $full.Substring(2) -replace '\\','/'
  return "/mnt/$drive$rest"
}

$winUser     = $env:USERNAME
$kernelWin   = "C:\Users\$winUser\bzImage-bluebot"
$kernelWsl   = "/mnt/c/Users/$winUser/bzImage-bluebot"
$wslConfig   = "C:\Users\$winUser\.wslconfig"

# --- 1. WSL present? ---
Info "Checking WSL..."
$wslOk = $false
try { wsl.exe --status *> $null; if ($LASTEXITCODE -eq 0) { $wslOk = $true } } catch {}
if (-not $wslOk) {
  Info "Installing WSL2 + $Distro (a reboot will be required)..."
  wsl.exe --install -d $Distro
  wsl.exe --update
  Warn "WSL was just installed. REBOOT Windows, finish the Ubuntu first-run user"
  Warn "setup, then run this installer again to continue."
  exit 0
}

# --- 2. distro installed? ---
$distros = (wsl.exe -l -q) -replace "`0","" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($distros -notcontains $Distro) {
  Info "Installing $Distro distro..."
  wsl.exe --install -d $Distro
  Warn "Finish the Ubuntu first-run user setup, then re-run this installer."
  exit 0
}
wsl.exe --set-version $Distro 2 *> $null

# Helper: run a bash command in the distro (fresh login shell so PATH + the
# docker group are loaded), streaming output, and stop on error.
function Wsl($cmd) {
  wsl.exe -d $Distro -- bash -lc $cmd
  if ($LASTEXITCODE -ne 0) { Die "WSL step failed (exit $LASTEXITCODE): $cmd" }
}

# --- 3. copy the local repo into WSL's filesystem (fast + avoids CRLF issues) ---
$RepoRootWsl = ConvertTo-WslPath $RepoRootWin
Info "Copying the repo into WSL (~/bluebot)..."
# Copy, strip any CRLF from shell scripts, and make them executable.
Wsl "rm -rf ~/bluebot && cp -r '$RepoRootWsl' ~/bluebot && rm -rf ~/bluebot/data && find ~/bluebot -type f -name '*.sh' -print0 | xargs -0 sed -i 's/\r`$//' && sed -i 's/\r`$//' ~/bluebot/deploy.sh && chmod +x ~/bluebot/deploy.sh ~/bluebot/scripts/*.sh ~/bluebot/installer/*.sh"

# --- 4. build phase: docker install + kernel build (repo already present) ---
if ($SkipKernel) {
  Info "Skipping kernel build (-SkipKernel); assuming binder is available."
  Wsl "bash ~/bluebot/installer/provision-wsl.sh --phase build --skip-clone --kernel-out 'skip'"
} else {
  Info "Build phase in WSL (Docker + binder kernel). The kernel build is slow..."
  Wsl "bash ~/bluebot/installer/provision-wsl.sh --phase build --skip-clone --kernel-out '$kernelWsl'"

  # --- 5. point .wslconfig at the new kernel ---
  if (-not (Test-Path $kernelWin)) { Die "Kernel build reported success but $kernelWin is missing." }
  Info "Pointing $wslConfig at the binder kernel..."
  $kernelEsc = $kernelWin -replace '\\','\\'
  $cfg = @()
  if (Test-Path $wslConfig) { $cfg = Get-Content $wslConfig | Where-Object { $_ -notmatch '^\s*kernel\s*=' } }
  if ($cfg -notcontains "[wsl2]") { $cfg = @("[wsl2]") + $cfg }
  $out = @(); $put = $false
  foreach ($line in $cfg) {
    $out += $line
    if ($line -match '^\[wsl2\]' -and -not $put) { $out += "kernel=$kernelEsc"; $put = $true }
  }
  Set-Content -Path $wslConfig -Value $out -Encoding ASCII
}

# --- 6. restart WSL (loads the new kernel AND activates the docker group) ---
Info "Restarting WSL..."
wsl.exe --shutdown
Start-Sleep -Seconds 6

# --- 7. deploy the stack ---
Info "Deploying the Android panel stack (redroid + viewer)..."
Wsl "bash ~/bluebot/installer/provision-wsl.sh --phase deploy"

# --- 8. desktop launcher (starts the stack, waits, opens the browser) ---
Info "Creating desktop launcher..."
$launcher = "$env:USERPROFILE\Desktop\Bluebot.cmd"
$launchBody = @"
@echo off
title Bluebot
echo Starting Bluebot Android panels...
wsl.exe -d $Distro -- bash -lc "cd ~/bluebot && docker compose up -d"
if %errorlevel% neq 0 (
  echo Failed to start. Open WSL and run: cd ~/bluebot ^&^& ./scripts/doctor.sh
  pause
  exit /b 1
)
echo Opening viewer...
timeout /t 3 >nul
start "" http://localhost:$ViewerPort
"@
Set-Content -Path $launcher -Value $launchBody -Encoding ASCII

Write-Host ""
Info "Done. Bluebot is running."
Write-Host "    Open:  http://localhost:$ViewerPort   (or the 'Bluebot' shortcut on your Desktop)"
Write-Host "    Manage in WSL:  cd ~/bluebot  &&  make ps | make logs | make down"
