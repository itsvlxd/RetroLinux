#!/usr/bin/env python3
# pylint: disable=C0413

import argparse
import os
import sys

RETRO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, RETRO_DIR)
sys.path.insert(0, os.path.join(RETRO_DIR, "lib", "python"))

from quickshare.discover import browse  # pylint: disable=import-error
from quickshare.server import pick_ipv4_address  # pylint: disable=import-error


def main():
    parser = argparse.ArgumentParser(prog="quickshare_scan", description="Scan for nearby Android Quick Share devices")
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--iface", default=None)
    args = parser.parse_args()

    try:
        address = pick_ipv4_address(args.iface)
    except Exception:
        address = None

    local_name = os.uname().nodename.lower()
    devices = browse(args.duration, address)
    for d in devices:
        if address and d.address == address:
            continue
        if d.device_name.lower() == local_name:
            continue
        print(f"{d.device_name}|{d.address}|{d.port}|{d.device_type.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
