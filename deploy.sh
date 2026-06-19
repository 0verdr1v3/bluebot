#!/usr/bin/env bash
# One-command deploy: prepare host -> preflight -> generate -> build -> launch.
#
#   ./deploy.sh                # uses .env (or defaults)
#   PANELS=8 ./deploy.sh       # override inline
#
# Re-running is safe — it regenerates the compose file and rolls the stack.
set -euo pipefail
cd "$(dirname "$0")"

# --- config: .env overrides defaults, env vars override .env ---
[ -f .env ] && set -a && . ./.env && set +a
PANELS="${PANELS:-4}"
ANDROID_VERSION="${ANDROID_VERSION:-11.0.0}"
VIEWER_PORT="${VIEWER_PORT:-8000}"
export PANELS VIEWER_PORT

echo "==> bluebot deploy: ${PANELS} panel(s), Android ${ANDROID_VERSION}, viewer :${VIEWER_PORT}"

# 1. Host prep (loads the binder kernel module; needs sudo). Skippable.
if [ "${SKIP_HOST_SETUP:-0}" != "1" ]; then
  echo "==> Preparing host..."
  ./scripts/setup_host.sh || {
    echo "!! Host setup failed. Fix the above (or set SKIP_HOST_SETUP=1 if already prepared)."; exit 1; }
fi

# 2. Preflight.
./scripts/doctor.sh

# 3. Generate the compose file for the requested size.
python3 scripts/gen_compose.py --count "$PANELS" --android "$ANDROID_VERSION" --port "$VIEWER_PORT"

# 4. Build the viewer + launch everything.
echo "==> Building and starting the stack (first build pulls images + compiles the viewer)..."
docker compose up -d --build

# 5. Wait for the viewer to report healthy.
echo -n "==> Waiting for the viewer to come up"
for _ in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' ws-scrcpy 2>/dev/null || echo "starting")
  [ "$status" = "healthy" ] && break
  echo -n "."; sleep 3
done
echo

if [ "${status:-}" = "healthy" ]; then
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "==> Up. Open the viewer:"
  echo "      http://localhost:${VIEWER_PORT}"
  [ -n "${ip:-}" ] && echo "      http://${ip}:${VIEWER_PORT}   (from another machine / cloud VM)"
  echo
  echo "    Android instances may take another minute to finish booting."
  echo "    Load test:  ./scripts/connect.sh && python3 scripts/mirror.py"
else
  echo "!! Viewer didn't report healthy in time. Inspect logs:"
  echo "      docker compose logs viewer"
  echo "      docker compose ps"
  exit 1
fi
