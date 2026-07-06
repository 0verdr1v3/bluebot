#!/usr/bin/env bash
# Prepare a Linux host (bare metal, cloud VM, or WSL2) to run redroid.
# redroid needs binder devices (/dev/binder, hwbinder, vndbinder). Depending on
# the kernel, binder is either a loadable module, built in with static devices,
# or exposed via binderfs. Handle all three.
set -euo pipefail

echo "==> Checking kernel: $(uname -r)"

have_binder() { ls /dev/binder /dev/hwbinder /dev/vndbinder >/dev/null 2>&1; }

if have_binder; then
  echo "==> binder devices already present."
elif sudo modprobe binder_linux devices="binder,hwbinder,vndbinder" 2>/dev/null && have_binder; then
  echo "==> Loaded binder_linux module."
  # Persist the module across reboots (bare metal / VMs).
  if [ ! -f /etc/modules-load.d/redroid.conf ]; then
    echo "binder_linux" | sudo tee /etc/modules-load.d/redroid.conf >/dev/null
    echo "options binder_linux devices=binder,hwbinder,vndbinder" | \
      sudo tee /etc/modprobe.d/redroid.conf >/dev/null
    echo "==> Made binder load on boot."
  fi
elif grep -qw binder /proc/filesystems 2>/dev/null; then
  # Kernel has binderfs built in (typical for a custom WSL2 kernel). Mount it and
  # create the three devices redroid expects.
  echo "==> Using binderfs..."
  sudo mkdir -p /dev/binderfs
  mountpoint -q /dev/binderfs || sudo mount -t binder binder /dev/binderfs
  for d in binder hwbinder vndbinder; do
    [ -e "/dev/$d" ] || sudo ln -sf "/dev/binderfs/$d" "/dev/$d" 2>/dev/null || true
  done
  have_binder || {
    echo "!! binderfs is mounted but /dev/binder* still missing."
    echo "   Your kernel may lack CONFIG_ANDROID_BINDER_DEVICES. See docs/WINDOWS.md."
    exit 1
  }
else
  echo "!! No binder support found — Android cannot boot."
  echo "   - Ubuntu/VM: sudo apt install linux-modules-extra-\$(uname -r)"
  echo "   - WSL2:      build a kernel with CONFIG_ANDROID_BINDERFS=y (see docs/WINDOWS.md)"
  echo "               or just run installer/install.bat which does this for you."
  exit 1
fi

# adb on the host (used by ./scripts/connect.sh and mirror.py — optional).
if ! command -v adb >/dev/null 2>&1; then
  echo "!! 'adb' not found (optional). Install for host-side control:"
  echo "   Ubuntu/Debian: sudo apt install -y android-tools-adb"
  echo "   Fedora:        sudo dnf install -y android-tools"
fi

echo "==> Host looks ready."
