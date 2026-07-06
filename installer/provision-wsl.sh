#!/usr/bin/env bash
# Runs INSIDE WSL2 (Ubuntu). Driven by installer/Install-Bluebot.ps1, but safe
# to run by hand too. Idempotent: re-running skips work already done.
#
#   bash provision-wsl.sh --phase build  --kernel-out /mnt/c/Users/<you>/bzImage-bluebot
#   bash provision-wsl.sh --phase deploy
set -euo pipefail

PHASE=""
KERNEL_OUT=""
REPO_URL="https://github.com/0verdr1v3/bluebot.git"
REPO_BRANCH="claude/dreamy-thompson-2rkd15"
SKIP_CLONE=0   # set when the repo was already copied into ~/bluebot (private repo)

while [ $# -gt 0 ]; do
  case "$1" in
    --phase)      PHASE="${2:-}"; shift 2;;
    --kernel-out) KERNEL_OUT="${2:-}"; shift 2;;
    --branch)     REPO_BRANCH="${2:-}"; shift 2;;
    --repo)       REPO_URL="${2:-}"; shift 2;;
    --skip-clone) SKIP_CLONE=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

log()  { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m!! %s\033[0m\n' "$1" >&2; exit 1; }

ensure_docker_installed() {
  if command -v docker >/dev/null 2>&1; then log "Docker already installed."; return; fi
  log "Installing Docker Engine..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER" || true
}

ensure_docker_running() {
  if docker info >/dev/null 2>&1; then return; fi
  log "Starting Docker daemon..."
  sudo service docker start 2>/dev/null || sudo systemctl start docker 2>/dev/null || true
  for _ in $(seq 1 15); do docker info >/dev/null 2>&1 && return; sleep 2; done
  # Fall back to running as the docker group in case membership isn't active yet.
  sg docker -c 'docker info' >/dev/null 2>&1 && return
  fail "Docker daemon did not come up. Try: sudo service docker start"
}

clone_repo() {
  if [ -d "$HOME/bluebot/.git" ]; then
    log "Updating existing repo..."
    git -C "$HOME/bluebot" fetch --depth 1 origin "$REPO_BRANCH"
    git -C "$HOME/bluebot" checkout -B "$REPO_BRANCH" "origin/$REPO_BRANCH"
  else
    log "Cloning repo into ~/bluebot..."
    git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$HOME/bluebot"
  fi
}

build_kernel() {
  [ -n "$KERNEL_OUT" ] || fail "build phase needs --kernel-out"
  if [ -f "$HOME/.bluebot-kernel-built" ] && [ -f "$KERNEL_OUT" ]; then
    log "binder kernel already built ($KERNEL_OUT); skipping."; return
  fi

  # Need ~25GB free for the kernel build + Docker images that follow.
  local free_gb
  free_gb=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9')
  if [ -n "$free_gb" ] && [ "$free_gb" -lt 25 ]; then
    fail "Only ${free_gb}GB free in WSL, but the kernel build + Docker need ~25GB.
   Free up space on your Windows C: drive (WSL shares it), then re-run the installer.
   Tip: 'docker system prune -af' in WSL, and empty your Windows Recycle Bin."
  fi

  log "Installing kernel build dependencies..."
  sudo apt-get update -y
  sudo apt-get install -y build-essential flex bison libssl-dev libelf-dev bc dwarves git cpio

  local ver branch src="$HOME/WSL2-Linux-Kernel"
  ver="$(uname -r | grep -oE '^[0-9]+\.[0-9]+' || echo '6.6')"
  branch="linux-msft-wsl-${ver}.y"
  log "Fetching WSL2 kernel source ($branch)..."
  if [ ! -d "$src/.git" ]; then
    git clone --depth 1 -b "$branch" https://github.com/microsoft/WSL2-Linux-Kernel.git "$src" \
      || { log "Branch $branch not found; using default branch."; \
           git clone --depth 1 https://github.com/microsoft/WSL2-Linux-Kernel.git "$src"; }
  fi
  cd "$src"

  log "Enabling Android binder in the kernel config..."
  cp Microsoft/config-wsl .config
  # Static devices (/dev/binder,hwbinder,vndbinder) appear at boot; binderfs on
  # as a fallback. ashmem is intentionally omitted (redroid 11+ uses memfd).
  {
    echo 'CONFIG_ANDROID=y'
    echo 'CONFIG_ANDROID_BINDER_IPC=y'
    echo 'CONFIG_ANDROID_BINDERFS=y'
    echo 'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"'
  } >> .config
  make olddefconfig

  log "Building kernel (this is the slow part — grab a coffee)..."
  make -j"$(nproc)"
  [ -f arch/x86/boot/bzImage ] || fail "kernel build produced no bzImage"

  mkdir -p "$(dirname "$KERNEL_OUT")"
  cp arch/x86/boot/bzImage "$KERNEL_OUT"
  touch "$HOME/.bluebot-kernel-built"
  log "binder kernel installed at $KERNEL_OUT"

  # Reclaim the ~15GB of build objects now that we have the kernel — important
  # on storage-constrained machines (the rest of setup still needs disk).
  log "Cleaning up kernel build tree to free space..."
  cd "$HOME"
  rm -rf "$src"
}

case "$PHASE" in
  build)
    ensure_docker_installed
    if [ "$SKIP_CLONE" -eq 1 ]; then
      [ -d "$HOME/bluebot" ] || fail "--skip-clone set but ~/bluebot not found (installer should have copied it)."
      log "Using repo already present at ~/bluebot (skipping clone)."
    else
      clone_repo
    fi
    if [ -n "$KERNEL_OUT" ] && [ "$KERNEL_OUT" != "skip" ]; then
      build_kernel
    else
      log "Skipping kernel build (host already provides binder)."
    fi
    log "Build phase done. The installer will now restart WSL and deploy."
    ;;
  deploy)
    [ -d "$HOME/bluebot" ] || fail "repo missing at \$HOME/bluebot — run the build phase first."
    ensure_docker_running
    cd "$HOME/bluebot"
    [ -f .env ] || cp .env.example .env
    log "Running deploy.sh..."
    ./deploy.sh
    ;;
  *)
    fail "usage: --phase build|deploy"
    ;;
esac
