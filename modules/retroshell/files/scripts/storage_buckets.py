#!/usr/bin/env python3
"""Measure real storage usage for the Device Storage widget.

Usage: storage_buckets.py [mount]
Outputs a JSON object with the device's total/used (via statvfs) plus the four
Linux bucket sizes measured with ``du`` (best-effort, timeout guarded):

  - System & Apps        : /usr, /opt, /snap, /nix
  - Home Directory       : $HOME excluding cache/container/trash paths
  - Cache & Containers   : ~/.cache, ~/.var (flatpak), docker, libvirt images
  - System Root & Logs   : /var/log, /tmp, swap
"""

import json
import os
import subprocess
import sys

DU_TIMEOUT = 12


def _du(path):
    """Directory size in bytes (best-effort, single filesystem)."""
    if not path or not os.path.exists(path):
        return 0
    try:
        out = subprocess.run(
            ["du", "-s", "-x", "--", path],
            capture_output=True,
            text=True,
            timeout=DU_TIMEOUT,
        )
        if out.returncode == 0 and out.stdout:
            return int(out.stdout.split("\t")[0].strip()) * 1024
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return 0


def _du_home(home):
    """Home directory size excluding cache/container/trash buckets."""
    if not home or not os.path.exists(home):
        return 0
    try:
        out = subprocess.run(
            [
                "du", "-s", "-x",
                "--exclude=.cache", "--exclude=.var", "--exclude=Trash",
                "--", home,
            ],
            capture_output=True,
            text=True,
            timeout=DU_TIMEOUT + 8,
        )
        if out.returncode == 0 and out.stdout:
            return int(out.stdout.split("\t")[0].strip()) * 1024
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return _du(home)


def _swap_size():
    total = 0
    try:
        with open("/proc/swaps", "r") as f:
            next(f, None)
            for line in f:
                parts = line.split()
                if len(parts) >= 3 and parts[0] != "Filename":
                    try:
                        total += int(parts[2])  # KB
                    except ValueError:
                        pass
    except OSError:
        pass
    return total * 1024


def _gb(b):
    return round(b / (1024 ** 3), 1)


def main():
    mount = sys.argv[1] if len(sys.argv) > 1 else "/"
    home = os.path.expanduser("~")

    total_gb = used_gb = 0.0
    try:
        st = os.statvfs(mount)
        total = st.f_blocks * st.f_frsize
        used = total - (st.f_bavail * st.f_frsize)
        total_gb = _gb(total)
        used_gb = _gb(used)
    except OSError:
        pass

    sys_apps = sum(_du(p) for p in ("/usr", "/opt", "/snap", "/nix"))
    cache_cont = (
        _du(os.path.join(home, ".cache"))
        + _du(os.path.join(home, ".var"))
        + _du("/var/lib/docker")
        + _du("/var/lib/libvirt/images")
    )
    home_dir = _du_home(home)
    sys_root = _du("/var/log") + _du("/tmp") + _swap_size()

    buckets = [
        {"label": "System & Apps", "sizeGB": _gb(sys_apps), "color": "#FF3B30", "striped": False},
        {"label": "Home Directory", "sizeGB": _gb(home_dir), "color": "#34C759", "striped": False},
        {"label": "Cache & Containers", "sizeGB": _gb(cache_cont), "color": "#FF9500", "striped": False},
        {"label": "System Root", "sizeGB": _gb(sys_root), "color": "#D1D1D6", "striped": True},
    ]

    print(json.dumps({
        "device": mount,
        "totalGB": total_gb,
        "usedGB": used_gb,
        "buckets": buckets,
    }))


if __name__ == "__main__":
    main()