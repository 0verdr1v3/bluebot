#!/usr/bin/env bash
# Live CPU / memory per panel while you load-test. Ctrl-C to stop.
# Run this in a second terminal alongside scripts/mirror.py.
# Word-splitting of the container names is intentional (names have no spaces).
# shellcheck disable=SC2046
exec docker stats $(docker ps --filter "name=redroid-" --format '{{.Names}}') ws-scrcpy
