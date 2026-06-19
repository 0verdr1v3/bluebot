#!/usr/bin/env bash
# Preflight checks. Fails fast with a clear reason before we try to deploy,
# so the first run doesn't hang silently. Exit non-zero on a hard blocker.
set -uo pipefail

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m %s\n" "$1"; }
bad()  { printf "  \033[31m✗\033[0m %s\n" "$1"; }

HARD_FAIL=0
PANELS="${PANELS:-4}"
VIEWER_PORT="${VIEWER_PORT:-8000}"

echo "== bluebot doctor =="

# --- Docker ---
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "docker daemon reachable ($(docker version --format '{{.Server.Version}}' 2>/dev/null))"
  else
    bad "docker is installed but the daemon isn't reachable (start it / check permissions)"; HARD_FAIL=1
  fi
else
  bad "docker not found — install Docker Engine"; HARD_FAIL=1
fi

# --- Compose plugin ---
if docker compose version >/dev/null 2>&1; then
  ok "docker compose plugin present"
else
  bad "'docker compose' not available — install the Compose v2 plugin"; HARD_FAIL=1
fi

# --- binder (required for redroid to boot Android) ---
if ls /dev/binder* >/dev/null 2>&1 || [ -d /dev/binderfs ] || grep -q binder /proc/filesystems 2>/dev/null; then
  ok "binder kernel support present"
else
  bad "binder kernel module not loaded — Android will NOT boot. Run: ./scripts/setup_host.sh"; HARD_FAIL=1
fi

# --- viewer port free ---
if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":${VIEWER_PORT} "; then
  warn "port ${VIEWER_PORT} already in use — change VIEWER_PORT in .env or free it"
else
  ok "viewer port ${VIEWER_PORT} appears free"
fi

# --- adb (only needed for connect.sh / mirror.py from the host) ---
if command -v adb >/dev/null 2>&1; then
  ok "adb present (host-side device control available)"
else
  warn "adb not found — the viewer still works; needed only for ./scripts/connect.sh and mirror.py"
fi

# --- rough memory sanity ---
if [ -r /proc/meminfo ]; then
  mem_gb=$(awk '/MemTotal/{printf "%.1f", $2/1024/1024}' /proc/meminfo)
  need=$(awk "BEGIN{printf \"%.1f\", ${PANELS}*1.5}")
  if awk "BEGIN{exit !($mem_gb < $need)}"; then
    warn "host has ${mem_gb}GB RAM; ~${need}GB recommended for ${PANELS} panels (≈1.5GB each)"
  else
    ok "memory looks ok for ${PANELS} panels (${mem_gb}GB)"
  fi
fi

echo
if [ "$HARD_FAIL" -ne 0 ]; then
  bad "preflight failed — fix the ✗ items above, then re-run."
  exit 1
fi
ok "preflight passed."
