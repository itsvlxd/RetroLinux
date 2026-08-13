#!/usr/bin/env python3
# pylint: disable=C0413

import argparse
import os
import signal
import sys
import time
from pathlib import Path

RETRO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, RETRO_DIR)
sys.path.insert(0, os.path.join(RETRO_DIR, "lib", "python"))

from scripts.python.log_core import rx_log_file, register  # pylint: disable=import-error
from lib.python.env import ensure_dbus  # pylint: disable=import-error

ensure_dbus()

from quickshare import mdns, ukey2  # pylint: disable=import-error
from quickshare.proto import wire_format_pb2 as wf_pb2  # pylint: disable=import-error
from quickshare.send import (  # pylint: disable=import-error
    RECEIVER_CANCELED,
    USER_CANCELED,
    SendError,
    run_sender,
    send_files,
)


def _signal_handler(_signum, _frame):
    raise KeyboardInterrupt


def _send_direct(target: str, paths: list[str], device_name: str) -> int:
    """Send straight to HOST:PORT with parseable progress on stdout.

    Line protocol (consumed by the settings page):
      WAITING                 handshake in progress
      PIN|<code>              confirmation code available
      PROGRESS|<pct>|<file>   payload progress
      OK|<elapsed>            finished
      ERR|<reason>            failed / canceled
    """
    host, _, port_str = target.partition(":")
    try:
        port = int(port_str)
    except ValueError:
        print("ERR|bad_target")
        return 1
    if not host:
        print("ERR|bad_target")
        return 1

    files = [Path(p) for p in paths]
    endpoint_id = mdns.stable_endpoint_id()
    endpoint_info = mdns.build_endpoint_info(device_name, mdns.ShareTargetType.LAPTOP)

    print("WAITING", flush=True)
    started = time.monotonic()

    def on_pin(pin: str) -> None:
        print(f"PIN|{pin}", flush=True)

    def on_progress(sp) -> None:
        pct = int(sp.bytes_sent * 100 / sp.total_bytes) if sp.total_bytes else 0
        print(f"PROGRESS|{pct}|{sp.file_name}", flush=True)

    try:
        status = send_files(
            host, port, endpoint_id, endpoint_info,
            files, on_pin=on_pin, on_progress=on_progress,
        )
    except KeyboardInterrupt:
        print("ERR|canceled", flush=True)
        return 1
    except (OSError, SendError, ukey2.Ukey2Error) as exc:
        print(f"ERR|{exc}", flush=True)
        return 1

    elapsed = int(time.monotonic() - started)
    if status == wf_pb2.ConnectionResponseFrame.Status.ACCEPT:
        print(f"OK|{elapsed}", flush=True)
        return 0
    if status in (USER_CANCELED, RECEIVER_CANCELED):
        print("ERR|receiver_canceled", flush=True)
        return 1
    print(f"ERR|{wf_pb2.ConnectionResponseFrame.Status.Name(status)}", flush=True)
    return 1


def main():
    parser = argparse.ArgumentParser(prog="quickshare_send", description="Retro Android Quick Share sender")
    parser.add_argument("paths", nargs="+", help="File path(s) to send")
    parser.add_argument("--name", default=None, help="Device name to advertise as sender")
    parser.add_argument("--iface", default=None, help="Network interface to use for discovery")
    parser.add_argument("-t", "--target", default=None, metavar="HOST:PORT", help="Connect directly instead of discovering")
    args = parser.parse_args()

    register("quickshare")

    for p in args.paths:
        if not os.path.isfile(p):
            rx_log_file("error", f"Not a file: {p}")
            print(f"ERR|not_a_file|{p}")
            return 1

    device_name = args.name or os.uname().nodename

    signal.signal(signal.SIGTERM, _signal_handler)

    if args.target:
        rx_log_file("info", f"Sending {len(args.paths)} file(s) to {args.target} as '{device_name}'")
        rc = _send_direct(args.target, args.paths, device_name)
    else:
        rx_log_file("info", f"Sending {len(args.paths)} file(s) as '{device_name}'")
        rc = run_sender(args.paths, device_name, args.iface, None)

    if rc == 0:
        rx_log_file("success", f"Sent: {', '.join(os.path.basename(p) for p in args.paths)}")
    else:
        rx_log_file("warn", "Send canceled or failed")
    return rc


if __name__ == "__main__":
    sys.exit(main())
