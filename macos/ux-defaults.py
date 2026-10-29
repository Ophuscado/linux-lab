#!/usr/bin/env python3
"""ux-defaults.py: the macOS settings that shape how input and the desktop feel, to mirror on KDE/libinput.

    python3 -I ux-defaults.py > ux-defaults.txt

Prints, per domain, every scalar setting (numbers, booleans, short strings); lists and dictionaries are summarized
by size, so app lists and recent items do not come along. From the global domain only the keys about pointer,
scroll, keyboard, appearance and animation. Read with 'defaults export', nothing is written.
"""
import plistlib
import re
import subprocess

DOMAINS = [
    "com.apple.AppleMultitouchTrackpad",
    "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    "com.apple.AppleMultitouchMouse",
    "com.apple.driver.AppleBluetoothMultitouch.mouse",
    "com.apple.driver.AppleHIDMouse",
    "com.apple.keyboard",
    "com.apple.HIToolbox",
    "com.apple.dock",
    "com.apple.WindowManager",
    "com.apple.spaces",
    "com.apple.universalaccess",
    "com.apple.symbolichotkeys",
    "com.apple.preference.trackpad",
]
GLOBAL_KEYS = re.compile(
    r"mouse|trackpad|scroll|swipe|gesture|keyrepeat|fnstate|keyboard|interfacestyle|accentcolor|highlightcolor|"
    r"animation|resizetime|windowtab|doubleclick|springing|forcetouch|smoothing|reducemotion|scrollbar|"
    r"textsize|sidebaricon|menubar|fullscreen|natural|momentum|inertia|tap|click|zoom|font|cursor",
    re.I,
)


def export(domain):
    r = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
    if r.returncode != 0 or not r.stdout:
        return None
    try:
        return plistlib.loads(r.stdout)
    except Exception:
        return None


def show(value):
    if isinstance(value, (bool, int, float)):
        return repr(value)
    if isinstance(value, str):
        return repr(value) if len(value) <= 120 else f"<text of {len(value)} chars>"
    if isinstance(value, bytes):
        return f"<{len(value)} bytes>"
    if isinstance(value, list):
        return f"<list of {len(value)}>"
    if isinstance(value, dict):
        return f"<dict of {len(value)}>"
    return f"<{type(value).__name__}>"


def main():
    for d in DOMAINS:
        p = export(d)
        print(f"== {d}" + ("" if p is not None else ": not set or not readable"))
        if not p:
            continue
        for k in sorted(p):
            v = p[k]
            if d == "com.apple.symbolichotkeys" and k == "AppleSymbolicHotKeys" and isinstance(v, dict):
                # Each system shortcut: its number, enabled, and the key/modifier triple.
                for n in sorted(v, key=lambda x: int(x) if str(x).isdigit() else 0):
                    e = v[n]
                    params = e.get("value", {}).get("parameters") if isinstance(e, dict) else None
                    print(f"  hotkey {n}: enabled={e.get('enabled') if isinstance(e, dict) else '?'} parameters={params}")
                continue
            print(f"  {k} = {show(v)}")
    g = export("NSGlobalDomain") or {}
    print("== global (pointer, scroll, keyboard, appearance and animation keys)")
    for k in sorted(g):
        if GLOBAL_KEYS.search(k):
            print(f"  {k} = {show(g[k])}")


if __name__ == "__main__":
    main()
