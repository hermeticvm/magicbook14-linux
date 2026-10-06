#!/usr/bin/env python3
"""Freeze configured apps while unfocused, thaw them on focus (Hyprland).

Freezing uses the systemd user scope freezer (`systemctl --user freeze`), so
every process of the app stops atomically: no CPU, no timers, no wakeups.
RAM stays allocated (frozen pages are just ice-cold for the reclaim/zram).

Config: ~/.config/omarchy/focus-freeze.json  {"classes": ["app.class", ...]}
"""
import glob
import json
import os
import signal
import socket
import subprocess
import sys
import time

CONFIG_PATH = os.path.expanduser("~/.config/omarchy/focus-freeze.json")
RUN = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")


def log(msg):
    print(f"focus-freeze: {msg}", flush=True)


def find_socket():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig:
        path = f"{RUN}/hypr/{sig}/.socket2.sock"
        if os.path.exists(path):
            return path
    # Derive the signature from the runtime dir (newest instance wins).
    cands = [d for d in glob.glob(f"{RUN}/hypr/*/") if os.path.exists(d + ".socket2.sock")]
    if not cands:
        return None
    return max(cands, key=os.path.getmtime) + ".socket2.sock"


def cfg_classes():
    try:
        with open(CONFIG_PATH) as f:
            return set(json.load(f).get("classes", []))
    except Exception as e:
        log(f"config unreadable ({e}); nothing will be frozen")
        return set()


def run(cmd, timeout=5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None


def units_for_class(cls):
    """Map a window class to the systemd user scope unit(s) of its windows."""
    out = run(["hyprctl", "clients", "-j"])
    if not out or not out.stdout:
        return set()
    try:
        clients = json.loads(out.stdout)
    except Exception:
        return set()
    units = set()
    for c in clients:
        if c.get("class") != cls or not c.get("pid"):
            continue
        try:
            with open(f"/proc/{c['pid']}/cgroup") as f:
                for line in f:
                    if ".scope" in line:
                        units.add(line.rsplit("/", 1)[-1].strip())
        except OSError:
            pass
    return units


class Freezer:
    def __init__(self):
        self.frozen = {}  # class -> set of unit names

    def freeze(self, cls):
        if cls in self.frozen:
            return
        units = units_for_class(cls)
        if not units:
            return
        for u in units:
            run(["systemctl", "--user", "freeze", u])
        self.frozen[cls] = units
        log(f"froze {cls}: {', '.join(sorted(units))}")

    def thaw(self, cls):
        units = self.frozen.pop(cls, set())
        for u in units:
            run(["systemctl", "--user", "thaw", u])
        if units:
            log(f"thawed {cls}")

    def thaw_all(self):
        for cls in list(self.frozen):
            self.thaw(cls)


def active_class():
    out = run(["hyprctl", "activewindow", "-j"])
    if not out or not out.stdout:
        return None
    try:
        return json.loads(out.stdout).get("class")
    except Exception:
        return None


def main():
    sock_path = find_socket()
    if not sock_path:
        log("Hyprland socket2 not found; exiting (will be restarted)")
        sys.exit(1)

    classes = cfg_classes()
    fz = Freezer()
    last_focus = active_class()
    log(f"watching {sorted(classes)}; current focus: {last_focus!r}")

    # Freeze anything configured that is not what the user is looking at.
    for cls in classes:
        if cls != last_focus:
            fz.freeze(cls)

    stop = {"flag": False}

    def on_signal(signum, frame):
        stop["flag"] = True

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
    s.settimeout(1.0)
    buf = ""

    while not stop["flag"]:
        try:
            chunk = s.recv(4096)
            if not chunk:
                raise ConnectionError("socket closed")
            buf += chunk.decode("utf-8", "replace")
        except socket.timeout:
            continue
        except ConnectionError:
            log("Hyprland closed the socket; exiting")
            break

        while "\n" in buf:
            line, buf = buf.split("\n", 1)
            if not line.startswith("activewindow>>"):
                continue
            cls = line[len("activewindow>>"):].split(",", 1)[0]

            # Thaw what the user just focused, freeze what they left.
            if cls in classes:
                fz.thaw(cls)
            if last_focus in classes and last_focus != cls:
                fz.freeze(last_focus)
            last_focus = cls if cls else None

    fz.thaw_all()
    log("stopped; everything thawed")


if __name__ == "__main__":
    main()
