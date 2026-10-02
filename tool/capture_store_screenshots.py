#!/usr/bin/env python3
"""Capture the Google Play screenshots from a running Android emulator.

Runs integration_test/store_screenshots_test.dart on the device and, each time
the test prints `STORE_SHOT <name>`, saves `adb exec-out screencap -p` as
<out>/<name>.png, then tells the test to carry on.

Use a 1080 x 1920 device so the captures need no cropping, e.g.:

    avdmanager create avd -n HiLoStore1080 -d pixel_2 \
        -k "system-images;android-35;google_apis;arm64-v8a"

Usage: tool/capture_store_screenshots.py [out_dir] [device_id]
"""
import os
import re
import subprocess
import sys

PACKAGE = "io.github.a15817348.hiloblackjacktrainer"
ACK_DIR = f"/data/user/0/{PACKAGE}/cache"


def adb(device, *args, **kw):
    return subprocess.run(["adb", "-s", device, *args], **kw)


def demo_status_bar(device):
    """A clean, fixed status bar: full battery and Wi-Fi, 9:41, no notifications."""
    adb(device, "shell", "settings", "put", "global", "sysui_demo_allowed", "1")
    for extra in (
        ["-e", "command", "enter"],
        ["-e", "command", "clock", "-e", "hhmm", "0941"],
        ["-e", "command", "battery", "-e", "level", "100", "-e", "plugged", "false"],
        ["-e", "command", "network", "-e", "wifi", "show", "-e", "level", "4", "-e", "fully", "true"],
        ["-e", "command", "network", "-e", "mobile", "hide"],
        ["-e", "command", "notifications", "-e", "visible", "false"],
    ):
        adb(device, "shell", "am", "broadcast", "-a", "com.android.systemui.demo", *extra,
            stdout=subprocess.DEVNULL)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "build/store_screenshots"
    device = sys.argv[2] if len(sys.argv) > 2 else "emulator-5554"
    os.makedirs(out, exist_ok=True)
    demo_status_bar(device)

    proc = subprocess.Popen(
        ["flutter", "test", "integration_test/store_screenshots_test.dart", "-d", device],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )
    shots = []
    for line in proc.stdout:
        sys.stdout.write(line)
        sys.stdout.flush()
        m = re.search(r"STORE_SHOT (\S+)", line)
        if not m:
            continue
        name = m.group(1)
        path = os.path.join(out, f"{name}.png")
        with open(path, "wb") as f:
            adb(device, "exec-out", "screencap", "-p", stdout=f)
        shots.append(path)
        print(f"  -> saved {path}", flush=True)
        adb(device, "shell", "run-as", PACKAGE, "touch", f"{ACK_DIR}/ack_{name}")
    code = proc.wait()
    print(f"\n{len(shots)} screenshots in {out}; test exit code {code}")
    sys.exit(code)


if __name__ == "__main__":
    main()
