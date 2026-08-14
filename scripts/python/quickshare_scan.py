#!/usr/bin/env python3
# pylint: disable=C0413

import argparse
import os
import sys

RETRO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, RETRO_DIR)
sys.path.insert(0, os.path.join(RETRO_DIR, "lib", "python"))

from quickshare import mdns  # pylint: disable=import-error
from quickshare import ble_nudge  # pylint: disable=import-error
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

    # Broadcast the BLE nudge while scanning so hidden-mode Quick Share
    # receivers wake up and advertise mDNS, making them visible to this scan.
    # Degrades silently to mDNS-only when no Bluetooth adapter is present.
    nudge = ble_nudge.NudgeManager(advertise=True, scan=False)
    nudge.start()

    local_endpoint = mdns.stable_endpoint_id()
    devices = browse(args.duration, address)

    nudge.stop()

    for d in devices:
        if d.endpoint_id == local_endpoint:
            continue
        if address and d.address == address:
            continue
        print(f"{d.device_name}|{d.address}|{d.port}|{d.device_type.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
