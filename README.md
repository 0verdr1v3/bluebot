# bluebot — a browser panel of Android instances

A self-hosted alternative to BlueStacks built from open-source parts: a grid of
independent **Android** instances you view and control as **panels in your web
browser**. Each panel is its own isolated Android device that can run regular
Android apps, including (with the GApps image) the Google Play Store.

```
┌─────────── your browser : http://localhost:8000 ───────────┐
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐            │
│  │Android1│  │Android2│  │Android3│  │Android4│   …panels   │
│  └────────┘  └────────┘  └────────┘  └────────┘            │
└────────────────────────────────────────────────────────────┘
        ▲ ws-scrcpy (web viewer)  ▲ redroid containers (Android)
```

## How it's built

| Piece | Role |
|-------|------|
| [**redroid**](https://github.com/remote-android/redroid-doc) | Real Android running in a Docker container. One container = one panel. |
| [**ws-scrcpy**](https://github.com/NetrisTV/ws-scrcpy) | Streams every device to the browser and renders the panel grid. |
| **Docker Compose** | Wires N Android instances + the viewer together. |
| `scripts/gen_compose.py` | Regenerates `docker-compose.yml` for any number of panels. |

## Requirements

- A **Linux host** — bare metal, a cloud VM, or **WSL2 on Windows**.
  redroid needs the Linux kernel `binder` module; it cannot run on the Windows
  kernel directly. (WSL2 works but needs a kernel built with binderfs — see below.)
- **Docker** + the Compose plugin.
- A few GB RAM per panel; more is better.

## Quick start

```bash
# 1. Prepare the host (loads the binder kernel module, persists it).
./scripts/setup_host.sh

# 2. (Optional) choose how many panels and which Android version.
python3 scripts/gen_compose.py --count 4 --android 11.0.0      # vanilla
# python3 scripts/gen_compose.py --count 6 --android 11.0.0 --gapps  # with Play Store

# 3. Bring it up (first run builds the viewer image; takes a few minutes).
docker compose up -d

# 4. Open the panel grid.
#    http://localhost:8000   (or http://<server-ip>:8000 for a cloud VM)
```

The viewer connects to each instance automatically. Click a panel to interact;
multiple panels stream at once.

## Installing apps

**With the Google Play Store** (`--gapps` image): open the Play Store inside a
panel, sign in, install apps normally. Note Play may require you to register the
device — see "Google Play & Play Integrity" below.

**Sideloading an APK** from your own machine:

```bash
./scripts/connect.sh                          # connect host adb to the panels
adb -s 127.0.0.1:5555 install path/to/app.apk # 5555 = android-1, 5556 = android-2 ...
```

## Changing the number of panels

```bash
docker compose down
python3 scripts/gen_compose.py --count 8
docker compose up -d
```

## Load testing: mirror one panel to all the others

To check how many panels your host can actually drive at once, mirror panel #1's
touch input to every other panel in real time and watch resource use:

```bash
./scripts/connect.sh          # host adb sees every panel
python3 scripts/mirror.py     # panel #1 = master, broadcast to the rest
# in a second terminal:
./scripts/stats.sh            # live CPU/mem per panel
```

Drive panel #1 in the browser (scroll, tap, open an app); the same input replays
on all the others. Add `--count` panels with `gen_compose.py` and repeat to find
where your machine tops out. This works because every redroid instance is an
identical clone, so raw input events replay 1:1.

## Google Play & Play Integrity — read this

- The Play Store / Play Services are **Google's proprietary software**. This repo
  does not bundle them; the `--gapps` redroid image includes the open
  integration, and you sign in with your own Google account.
- Many apps now run **Play Integrity** checks. On an emulator you may need to
  register the device's Google Services Framework (GSF) ID at
  <https://www.google.com/android/uncertified> for Play to work, and some apps
  (banking, DRM-heavy streaming) will still refuse to run on a virtual device.
  That's a limitation of emulators in general, not a bug here.
- **`redroid` gapps image tags change over time.** If `--gapps` fails to pull,
  check the current tag at <https://hub.docker.com/r/redroid/redroid/tags>.

## WSL2-on-Windows notes

The stock WSL2 kernel does not ship binderfs. You'll need to build a WSL2 kernel
with `CONFIG_ANDROID_BINDER_IPC=y` and `CONFIG_ANDROID_BINDERFS=y`, then point
`.wslconfig` at it. A plain Linux cloud VM avoids this and is the easier path if
you just want it working.

## Scope / use

This is intended for running and testing apps on Android instances you control.
It deliberately does **not** include device-fingerprint spoofing or anything
designed to make instances impersonate distinct real handsets — that's outside
what this project is for.
