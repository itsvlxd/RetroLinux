#!/usr/bin/env python3
"""Measure real storage usage for the Device Storage widget.

Usage: storage_buckets.py [mount]
Outputs a JSON object with the device's total/used (via statvfs) plus the
Linux bucket sizes measured with ``du`` (best-effort, timeout guarded):

  - System  : /usr, /opt, /snap, /nix
  - Home    : $HOME excluding cache/container/trash paths
  - Cache   : ~/.cache, ~/.var (flatpak), docker, libvirt images
  - Apps    : ~/.local/share (Steam, Kiwix, game launchers, etc.)
  - Root    : /var/log, /tmp, swap
  - Other   : gap between measured buckets and actual disk usage
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

    # Only measure individual buckets when viewing the root filesystem —
    # the hardcoded paths (/usr, $HOME, etc.) don't apply to other mounts.
    if mount == "/":
        sys_apps = sum(_du(p) for p in ("/usr", "/opt", "/snap", "/nix"))
        cache_cont = (
            _du(os.path.join(home, ".cache"))
            + _du(os.path.join(home, ".var"))
            + _du("/var/lib/docker")
            + _du("/var/lib/libvirt/images")
        )
        home_dir = _du_home(home)
        app_data = _du(os.path.join(home, ".local", "share"))
        sys_root = _du("/var/log") + _du("/tmp") + _swap_size()

        buckets = [
            {"label": "System", "sizeGB": _gb(sys_apps), "color": "#FF3B30", "striped": False},
            {"label": "Home", "sizeGB": _gb(home_dir), "color": "#34C759", "striped": False},
            {"label": "Apps", "sizeGB": _gb(app_data), "color": "#007AFF", "striped": False},
            {"label": "Cache", "sizeGB": _gb(cache_cont), "color": "#FF9500", "striped": False},
            {"label": "Root", "sizeGB": _gb(sys_root), "color": "#D1D1D6", "striped": True},
        ]

        # Add "Other" for the gap between measured buckets and actual disk usage
        # (filesystem metadata, journal, deleted-open files, unlisted dirs, etc.)
        bucket_sum = sum(b["sizeGB"] for b in buckets)
        other_gb = round(used_gb - bucket_sum, 1)
        if other_gb > 0.5:
            buckets.append({"label": "Other", "sizeGB": other_gb, "color": "#8E8E93", "striped": True})
    else:
        # Non-root mount: show a single "Used" bucket from statvfs.
        buckets = [
            {"label": "Used", "sizeGB": used_gb, "color": "#FF9500", "striped": False},
        ]

    print(json.dumps({
        "device": mount,
        "totalGB": total_gb,
        "usedGB": used_gb,
        "buckets": buckets,
    }))


if __name__ == "__main__":
    main()