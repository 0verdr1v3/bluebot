#!/usr/bin/env bash
# Prepare a Linux host (bare metal, cloud VM, or WSL2) to run redroid.
# redroid needs the kernel `binder` module exposing 3 binder devices.
set -euo pipefail

echo "==> Checking kernel: $(uname -r)"

# 1) binder_linux — required by Android's IPC. On many distros it's a module.
if [ -d /dev/binderfs ] || ls /dev/*binder* >/dev/null 2>&1; then
  echo "==> binder devices already present."
else
  echo "==> Loading binder_linux with 3 devices (binder,hwbinder,vndbinder)..."
  sudo modprobe binder_linux devices="binder,hwbinder,vndbinder" || {
    echo "!! Could not modprobe binder_linux."
    echo "   - On Ubuntu: sudo apt install linux-modules-extra-\$(uname -r)"
    echo "   - On WSL2:  you need a custom kernel built with CONFIG_ANDROID_BINDERFS=y"
    echo "               (see docs/README in this repo)."
    exit 1
  }
fi

# 2) Persist across reboots.
if [ ! -f /etc/modules-load.d/redroid.conf ]; then
  echo "binder_linux" | sudo tee /etc/modules-load.d/redroid.conf >/dev/null
  echo "options binder_linux devices=binder,hwbinder,vndbinder" | \
    sudo tee /etc/modprobe.d/redroid.conf >/dev/null
  echo "==> Made binder load on boot."
fi

# 3) adb on the host (used by ./scripts/connect.sh).
if ! command -v adb >/dev/null 2>&1; then
  echo "!! 'adb' not found. Install it:"
  echo "   Ubuntu/Debian: sudo apt install -y android-tools-adb"
  echo "   Fedora:        sudo dnf install -y android-tools"
fi

echo "==> Host looks ready. Now: docker compose up -d"
