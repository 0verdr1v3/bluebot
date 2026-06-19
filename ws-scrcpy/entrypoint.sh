#!/usr/bin/env bash
# Connect ws-scrcpy's adb to every redroid instance over the docker network,
# then start the web server. DEVICES is a space-separated list of host:port
# (e.g. "android-1:5555 android-2:5555"), injected by docker-compose.
set -euo pipefail

adb start-server >/dev/null 2>&1 || true

for dev in ${DEVICES:-}; do
  echo "==> adb connect ${dev}"
  # redroid can take a moment to boot; retry a few times.
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if adb connect "${dev}" | grep -qE "connected|already"; then
      break
    fi
    sleep 3
  done
done

echo "==> Devices visible to the viewer:"
adb devices

echo "==> Starting ws-scrcpy on :8000"
# Run the built server via the project's own start script (resolves native
# deps from /app/node_modules); avoids hardcoding the entry filename.
cd /app/dist
exec npm start
