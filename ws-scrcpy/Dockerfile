# Web-based scrcpy: streams one or many ADB-connected Android devices to the
# browser. We build it from source because there's no stable official image.
FROM node:18-bullseye

# adb client (ws-scrcpy shells out to it), git for the checkout, and the
# python/compiler toolchain node-gyp needs to build native deps (e.g. node-pty).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      android-tools-adb git python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Pin to a known-good tag; bump deliberately when you want updates.
ARG WS_SCRCPY_REF=v0.8.1
RUN git clone --depth 1 --branch "${WS_SCRCPY_REF}" \
      https://github.com/NetrisTV/ws-scrcpy.git . \
 && npm ci \
 && npm run dist

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
