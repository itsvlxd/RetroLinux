#!/usr/bin/env python3
"""Stream real-time network bandwidth + IP info for the Network widget.

Emits one JSON line per second:
  {"interface", "download", "upload", "localIp", "publicIp", "publicIpValid"}

download/upload are Mbps computed from /proc/net/dev byte deltas. The public
IP is fetched once in a background thread (and retried on failure / refreshed
periodically); until it resolves ``publicIp`` is empty and ``publicIpValid``
is false.
"""

import json
import re
import subprocess
import threading
import time
import urllib.request

INTERVAL = 1.0
PUBLIC_RETRY_SEC = 300


def _read_dev():
    data = {}
    try:
        with open("/proc/net/dev", "r") as f:
            lines = f.read().splitlines()[2:]
    except OSError:
        return data
    for line in lines:
        if ":" not in line:
            continue
        iface, rest = line.split(":", 1)
        vals = rest.split()
        if len(vals) >= 9:
            try:
                data[iface.strip()] = (int(vals[0]), int(vals[8]))  # rx, tx bytes
            except ValueError:
                pass
    return data


def _active_interface():
    try:
        out = subprocess.run(
            ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE", "d", "status"],
            capture_output=True,
            text=True,
            timeout=3,
        ).stdout
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) >= 3 and parts[2] == "connected" and parts[1] in ("wifi", "ethernet"):
                return parts[0]
    except Exception:
        pass
    return "wlan0"


def _local_ip(iface):
    try:
        out = subprocess.run(
            ["ip", "-4", "-o", "addr", "show", iface],
            capture_output=True,
            text=True,
            timeout=3,
        ).stdout
        m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        if m:
            return m.group(1)
    except Exception:
        pass
    return ""


_public_ip = ""
_public_valid = False


def _fetch_public():
    global _public_ip, _public_valid
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=5) as r:
            v = r.read().decode().strip()
            if re.match(r"^\d+\.\d+\.\d+\.\d+$", v):
                _public_ip = v
                _public_valid = True
    except Exception:
        pass


def _schedule_public():
    threading.Thread(target=_fetch_public, daemon=True).start()


def main():
    iface = _active_interface()
    local = _local_ip(iface)
    prev = _read_dev()
    last = time.time()
    last_public = 0
    last_recheck = time.time()
    _schedule_public()

    while True:
        time.sleep(INTERVAL)
        cur = _read_dev()
        now = time.time()
        dt = max(0.001, now - last)
        last = now

        now2 = time.time()
        if now2 - last_recheck >= 30:
            new_iface = _active_interface()
            if new_iface != iface:
                iface = new_iface
                prev = cur
                local = _local_ip(iface)
            last_recheck = now2

        prev_rx, prev_tx = prev.get(iface, (0, 0))
        cur_rx, cur_tx = cur.get(iface, (0, 0))
        down = max(0.0, (cur_rx - prev_rx) * 8 / dt / 1e6)
        up = max(0.0, (cur_tx - prev_tx) * 8 / dt / 1e6)

        if not local:
            local = _local_ip(iface)

        if not _public_valid and now - last_public >= 60:
            _schedule_public()
            last_public = now
        elif _public_valid and now - last_public >= PUBLIC_RETRY_SEC:
            _schedule_public()
            last_public = now

        print(json.dumps({
            "interface": iface,
            "download": round(down, 2),
            "upload": round(up, 2),
            "localIp": local,
            "publicIp": _public_ip,
            "publicIpValid": _public_valid,
        }), flush=True)
        prev = cur


if __name__ == "__main__":
    main()