#!/usr/bin/env bash
# OPTIONAL host-side helper. The web viewer connects to the instances on its
# own — you only need this if you want to drive the devices from YOUR machine's
# adb (e.g. install an APK, take a screenshot, open a shell).
#
#   ./scripts/connect.sh            # connect host adb to all panels
#   adb -s 127.0.0.1:5555 install yourapp.apk
set -euo pipefail

mapfile -t PORTS < <(docker ps --filter "name=redroid-" --format '{{.Ports}}' \
  | grep -oE '0.0.0.0:[0-9]+->5555' | grep -oE ':[0-9]+' | tr -d ':')

if [ "${#PORTS[@]}" -eq 0 ]; then
  echo "No redroid containers found. Run 'docker compose up -d' first."
  exit 1
fi

adb start-server >/dev/null 2>&1 || true
for port in "${PORTS[@]}"; do
  echo "==> adb connect 127.0.0.1:${port}"
  adb connect "127.0.0.1:${port}" || true
done

echo
adb devices
