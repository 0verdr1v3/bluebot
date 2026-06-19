#!/usr/bin/env python3
"""Mirror one Android panel's touch input to all the others — a simple way to
load-test how many panels your host can drive at once.

You drive panel #1 by hand (or with a script) in the browser; every touch event
is broadcast to the rest in real time. Because all redroid instances are
identical clones, raw input events replay 1:1.

    ./scripts/connect.sh            # make the host's adb see every panel
    python3 scripts/mirror.py       # master = first device, mirror to the rest

Options:
    --master HOST:PORT   device to read from   (default: lowest-numbered)
    --device /dev/input/eventN   touch device  (default: auto-detect)
    --list               just list connected devices and exit
"""
import argparse
import re
import subprocess
import sys


def adb_devices():
    out = subprocess.run(["adb", "devices"], capture_output=True, text=True).stdout
    devs = []
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) == 2 and parts[1] == "device":
            devs.append(parts[0])
    # Stable order: by trailing port number when present.
    devs.sort(key=lambda d: int(d.rsplit(":", 1)[-1]) if ":" in d else d)
    return devs


def detect_touch_device(serial):
    """Find the touchscreen by scanning getevent capabilities for multitouch."""
    out = subprocess.run(
        ["adb", "-s", serial, "shell", "getevent", "-pl"],
        capture_output=True, text=True,
    ).stdout
    current = None
    for line in out.splitlines():
        m = re.search(r"add device \d+:\s*(\S+)", line)
        if m:
            current = m.group(1)
        if current and ("ABS_MT_POSITION_X" in line or "BTN_TOUCH" in line):
            return current
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--master", help="device to read input from (default: first)")
    p.add_argument("--device", help="touch input device path on the master")
    p.add_argument("--list", action="store_true")
    args = p.parse_args()

    devs = adb_devices()
    if args.list:
        print("Connected devices:")
        for d in devs:
            print("  ", d)
        return
    if len(devs) < 2:
        sys.exit("Need at least 2 connected devices. Run ./scripts/connect.sh first.")

    master = args.master or devs[0]
    if master not in devs:
        sys.exit(f"Master {master} is not in the connected list: {devs}")
    slaves = [d for d in devs if d != master]

    touch = args.device or detect_touch_device(master)
    if not touch:
        sys.exit("Could not auto-detect the touch device. Pass it with "
                 "--device (find it via: adb -s <master> shell getevent -pl).")

    print(f"Master : {master}")
    print(f"Mirror to ({len(slaves)}): {', '.join(slaves)}")
    print(f"Touch device: {touch}")
    print("Drive panel #1 in the browser; Ctrl-C to stop.\n")

    # One persistent shell per slave so we don't pay adb startup per event.
    shells = {}
    for s in slaves:
        shells[s] = subprocess.Popen(
            ["adb", "-s", s, "shell"],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, text=True, bufsize=1,
        )

    # exec-out gives a clean stream without pty newline translation.
    reader = subprocess.Popen(
        ["adb", "-s", master, "exec-out", "getevent", touch],
        stdout=subprocess.PIPE, text=True, bufsize=1,
    )

    sent = 0
    try:
        for line in reader.stdout:
            toks = line.split()
            if len(toks) < 3:
                continue
            try:  # getevent prints hex; sendevent wants decimal
                t, c, v = (int(x, 16) for x in toks[-3:])
            except ValueError:
                continue
            cmd = f"sendevent {touch} {t} {c} {v}\n"
            for sh in shells.values():
                if sh.stdin:
                    sh.stdin.write(cmd)
                    sh.stdin.flush()
            sent += 1
            if sent % 200 == 0:
                print(f"  …forwarded {sent} events", end="\r", flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        reader.terminate()
        for sh in shells.values():
            try:
                sh.stdin.close()
                sh.terminate()
            except Exception:
                pass
        print(f"\nStopped. Forwarded {sent} events to {len(slaves)} panel(s).")


if __name__ == "__main__":
    main()
