#!/usr/bin/env python3
# pylint: disable=C0413

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time

_RETRO_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, _RETRO_DIR)
sys.path.insert(0, os.path.join(_RETRO_DIR, "lib", "python"))

from scripts.python.log_core import rx_log_file, register  # pylint: disable=import-error
from lib.python.env import ensure_dbus, get_shell_env  # pylint: disable=import-error

ensure_dbus()

from quickshare.server import run_receiver  # pylint: disable=import-error
from quickshare.receive import TransferCancelled  # pylint: disable=import-error

_ICON = "network-transmit-receive-symbolic"
_MILESTONES = (25, 50, 75)
_NOTIF_ID = 48210
_LAST_PCT: dict[int, int] = {}

_STATE_FILE = "/tmp/retro_logs/quickshare_transfers.json"
_STATE_LOCK = threading.Lock()
_TRANSFERS: dict[int, dict] = {}
_PAYLOAD_TO_UID: dict[int, int] = {}
_UID = 0
_PENDING_OFFERS: dict[int, dict] = {}
_CANCEL_DIR = "/tmp/retro_logs/quickshare_cancel"
_CLEAR_DIR = "/tmp/retro_logs/quickshare_clear"
_DECISION_DIR = "/tmp/retro_logs/quickshare_decision"

_QS_CORE = os.path.join(_RETRO_DIR, "scripts", "quickshare_core.sh")
_DIR_LOCK = threading.Lock()
_PENDING_MOVE_DIR: str | None = None

_NOTIFY_MIN_INTERVAL = 3.0
_LAST_NOTIFY_AT = 0.0


def _pick_download_dir():
    """Prompt for the save folder with zenity. Returns the chosen dir or None
    if the user cancels. The choice is also saved as the new default."""
    try:
        r = subprocess.run(
            ["bash", _QS_CORE, "--set-dir-interactive"],
            capture_output=True, text=True, timeout=600,
        )
        out = r.stdout.strip()
        if out.startswith("OK|"):
            return out.split("|", 1)[1]
    except Exception:
        pass
    return None


def _dir_configured() -> bool:
    """True once the user has explicitly picked a download folder. Only ask
    for the folder until that happens, then always reuse it."""
    try:
        r = subprocess.run(
            ["bash", _QS_CORE, "--dir-configured"],
            capture_output=True, text=True, timeout=10,
        )
        return r.stdout.strip() == "true"
    except Exception:
        return False


def _move_completed(paths, dest_dir):
    """Move received files into dest_dir (if chosen). Returns the final paths.
    Updates the state's dest so the page's Open button points at the real file."""
    final = []
    if not dest_dir:
        return [str(p) for p in paths]
    os.makedirs(dest_dir, exist_ok=True)
    for src in paths:
        src = str(src)
        if not os.path.isfile(src):
            continue
        base = os.path.basename(src)
        target = os.path.join(dest_dir, base)
        n = 1
        while os.path.exists(target):
            root, ext = os.path.splitext(base)
            target = os.path.join(dest_dir, f"{root} ({n}){ext}")
            n += 1
        try:
            shutil.move(src, target)
            with _STATE_LOCK:
                for x in _TRANSFERS.values():
                    if x.get("dest") == src:
                        x["dest"] = target
            _write_state()
            rx_log_file("success", f"Saved to {target}")
            final.append(target)
        except Exception as exc:
            rx_log_file("error", f"Failed to move {src} to {dest_dir}: {exc}")
            final.append(src)
    return final


def _notify_open(path):
    """Completion notification with an Open action, run off-thread so it can
    block on --wait until the user clicks or it times out."""
    base = os.path.basename(path)

    def run():
        try:
            r = _notify(
                "Transfer complete",
                f"<b>{base}</b> saved to {path}",
                actions={"open": "Open"},
                timeout=20000,
                wait=True,
            )
            if r.stdout.strip() == "open":
                subprocess.Popen(
                    ["xdg-open", path],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
        except Exception:
            pass

    threading.Thread(target=run, daemon=True).start()


def _notify_throttled(title, body, **kw):
    """Progress notifications: never stack — wait for the previous one to
    clear before posting another."""
    global _LAST_NOTIFY_AT
    now = time.time()
    if now - _LAST_NOTIFY_AT < _NOTIFY_MIN_INTERVAL:
        return
    _LAST_NOTIFY_AT = now
    _notify(title, body, **kw)


def _cancel_requested(payload_id: int) -> bool:
    try:
        return os.path.isfile(os.path.join(_CANCEL_DIR, str(payload_id)))
    except Exception:
        return False


def _clear_cancel(payload_id: int) -> None:
    try:
        os.remove(os.path.join(_CANCEL_DIR, str(payload_id)))
    except Exception:
        pass


def _read_decision(offer_id):
    """Read an accept/decline decision written by the GUI for a pending offer."""
    try:
        p = os.path.join(_DECISION_DIR, str(offer_id))
        if os.path.isfile(p):
            with open(p) as f:
                return f.read().strip()
    except Exception:
        pass
    return None


def _clear_decision(offer_id) -> None:
    try:
        os.remove(os.path.join(_DECISION_DIR, str(offer_id)))
    except Exception:
        pass


def _next_uid() -> int:
    global _UID
    _UID += 1
    return _UID


def _write_state():
    now = time.time()
    with _STATE_LOCK:
        try:
            if os.path.isdir(_CLEAR_DIR):
                for name in os.listdir(_CLEAR_DIR):
                    try:
                        pid = int(name)
                        uid = _PAYLOAD_TO_UID.pop(pid, None)
                        _TRANSFERS.pop(uid if uid is not None else pid, None)
                        os.remove(os.path.join(_CLEAR_DIR, name))
                    except Exception:
                        pass
        except Exception:
            pass
        payload = {
            "transfers": [
                {
                    "id": tid,
                    "payload_id": x.get("payload_id", tid),
                    "file": x["file"],
                    "size": x["size"],
                    "bytes": x["bytes"],
                    "direction": "receive",
                    "done": x.get("done", False),
                    "finished_at": x.get("finished_at"),
                    "dest": x.get("dest"),
                }
                for tid, x in _TRANSFERS.items()
            ],
            "offers": [
                {"id": oid, "files": o["files"], "pin": o["pin"]}
                for oid, o in _PENDING_OFFERS.items()
            ],
        }
    try:
        os.makedirs(os.path.dirname(_STATE_FILE), exist_ok=True)
        tmp = _STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(payload, f)
        os.replace(tmp, _STATE_FILE)
    except Exception:
        pass


def _track_offer(file_metadata, accepted):
    if not accepted:
        return
    with _STATE_LOCK:
        for meta in file_metadata:
            pid = meta.payload_id
            uid = _next_uid()
            _PAYLOAD_TO_UID[pid] = uid
            _TRANSFERS[uid] = {
                "payload_id": pid,
                "file": meta.name,
                "size": meta.size,
                "bytes": 0,
                "done": False,
                "dest": None,
            }
    _write_state()


def _track_progress(incoming):
    with _STATE_LOCK:
        uid = _PAYLOAD_TO_UID.get(incoming.payload_id)
        if uid is None:
            uid = _next_uid()
            _PAYLOAD_TO_UID[incoming.payload_id] = uid
        cur = _TRANSFERS.get(uid)
        if cur is None:
            cur = {
                "payload_id": incoming.payload_id,
                "file": incoming.name,
                "size": incoming.size,
                "bytes": 0,
                "done": False,
                "dest": None,
            }
            _TRANSFERS[uid] = cur
        cur["bytes"] = incoming.bytes_written
        cur["dest"] = str(incoming.dest_path)
        if incoming.complete:
            cur["done"] = True
            cur["finished_at"] = time.time()
    _write_state()


def _human(n):
    size = float(n)
    for unit in ("B", "K", "M", "G", "T"):
        if size < 1024 or unit == "T":
            return f"{size:.0f}{unit}" if unit == "B" else f"{size:.1f}{unit}"
        size /= 1024
    return f"{n}B"


def _notify(title, body, *, actions=None, timeout=None, progress=None, replace=None, wait=False):
    cmd = ["notify-send", "-a", "RetroLinux", "-i", _ICON]
    if wait:
        cmd.append("--wait")
    if replace:
        cmd += ["-r", str(replace)]
    if timeout:
        cmd += ["-t", str(timeout)]
    if progress is not None:
        cmd += ["-h", f"int:value:{progress}", "-h", "string:x-canonical-private-synchronous:qs-receive"]
    for key, label in (actions or {}).items():
        cmd += ["-A", f"{key}={label}"]
    cmd += [title, body]
    return subprocess.run(cmd, env=get_shell_env(), capture_output=True, text=True)


def _auto_accept_enabled() -> bool:
    """Read the live auto-accept setting (variables.sh), so toggling it in the
    settings page takes effect without restarting the receiver."""
    try:
        r = subprocess.run(
            ["bash", _QS_CORE, "--auto-accept-status"],
            capture_output=True, text=True, timeout=10,
        )
        return r.stdout.strip() == "true"
    except Exception:
        return False


def _on_offer(file_metadata, pin, auto_accept):
    global _PENDING_MOVE_DIR
    lines = [f"• <b>{m.name}</b> ({_human(m.size)})" for m in file_metadata]
    if auto_accept or _auto_accept_enabled():
        rx_log_file("info", f"Auto-accepting offer (PIN {pin}): {', '.join(m.name for m in file_metadata)}")
        _track_offer(file_metadata, True)
        return True

    rx_log_file("info", f"Incoming offer (PIN {pin}): {', '.join(m.name for m in file_metadata)}")
    offer_id = file_metadata[0].payload_id if file_metadata else 0
    offer_files = [{"name": m.name, "size": m.size} for m in file_metadata]

    with _STATE_LOCK:
        _PENDING_OFFERS[offer_id] = {"id": offer_id, "files": offer_files, "pin": pin}
    _write_state()

    notif_result: dict = {}

    def notif_run():
        try:
            r = _notify(
                "Incoming Quick Share transfer",
                f"Confirmation code: <b>{pin}</b>\n" + "\n".join(lines),
                actions={"accept": "Accept", "deny": "Deny"},
                timeout=120000,
                wait=True,
            )
            notif_result["action"] = r.stdout.strip()
        except Exception:
            notif_result["action"] = ""

    threading.Thread(target=notif_run, daemon=True).start()

    accepted = False
    deadline = time.time() + 120
    while time.time() < deadline:
        if "action" in notif_result:
            accepted = notif_result["action"] == "accept"
            break
        decision = _read_decision(offer_id)
        if decision == "accept":
            accepted = True
            break
        if decision == "deny":
            accepted = False
            break
        time.sleep(0.2)

    _clear_decision(offer_id)
    with _STATE_LOCK:
        _PENDING_OFFERS.pop(offer_id, None)
    _write_state()
    _track_offer(file_metadata, accepted)

    if accepted:
        if not _dir_configured():
            with _DIR_LOCK:
                _PENDING_MOVE_DIR = _pick_download_dir()
        else:
            _PENDING_MOVE_DIR = None
        rx_log_file("success", f"Offer accepted (PIN {pin})")
        return True
    rx_log_file("warn", f"Offer declined (PIN {pin})")
    return False


def _on_progress(incoming):
    _track_progress(incoming)
    if _cancel_requested(incoming.payload_id):
        _clear_cancel(incoming.payload_id)
        rx_log_file("warn", f"Cancel requested for {incoming.name} (payload {incoming.payload_id})")
        raise TransferCancelled(incoming.payload_id)
    pct = int(incoming.bytes_written * 100 / incoming.size) if incoming.size else 0
    if incoming.complete:
        _LAST_PCT.pop(incoming.payload_id, None)
        rx_log_file("success", f"Received {incoming.name} ({_human(incoming.size)}) → {incoming.dest_path}")
        return
    prev = _LAST_PCT.get(incoming.payload_id, -1)
    for milestone in _MILESTONES:
        if prev < milestone <= pct:
            rx_log_file(
                "info",
                f"Receiving {incoming.name}: {milestone}% ({_human(incoming.bytes_written)} / {_human(incoming.size)})",
            )
            _notify_throttled(
                f"Receiving: {incoming.name}",
                f"{pct}% ({_human(incoming.bytes_written)} / {_human(incoming.size)})",
                progress=pct,
                replace=_NOTIF_ID,
            )
            break
    _LAST_PCT[incoming.payload_id] = pct


def _on_connection_end(outcome, completed):
    """Connection finished. Move completed files to the folder the user
    picked at accept time, notify with an Open action, and drop any
    still-active transfers so the page doesn't show ghost rows for
    aborted/disconnected transfers."""
    global _PENDING_MOVE_DIR
    if outcome == "completed":
        with _DIR_LOCK:
            dest = _PENDING_MOVE_DIR
            _PENDING_MOVE_DIR = None
        for path in _move_completed(completed, dest):
            _notify_open(path)
        return
    with _DIR_LOCK:
        _PENDING_MOVE_DIR = None
    with _STATE_LOCK:
        for tid in [t for t, x in _TRANSFERS.items() if not x.get("done")]:
            _TRANSFERS.pop(tid, None)
    _write_state()


def _signal_handler(_signum, _frame):
    raise KeyboardInterrupt


def _state_worker():
    """Periodically rewrite the state file so pending clear/cancel flags are
    applied even while no transfer is in progress (clear flags would otherwise
    sit untouched until the next progress event)."""
    while True:
        time.sleep(2)
        try:
            _write_state()
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser(prog="quickshare_receive", description="Retro Android Quick Share receiver daemon")
    parser.add_argument("--dir", default=os.path.expanduser("~/Downloads"))
    parser.add_argument("--name", default=None)
    parser.add_argument("--iface", default=None)
    parser.add_argument("--yes", action="store_true", help="Auto-accept incoming transfers")
    args = parser.parse_args()

    register("quickshare")

    with _STATE_LOCK:
        _TRANSFERS.clear()
        _PAYLOAD_TO_UID.clear()
        _PENDING_OFFERS.clear()
    try:
        if os.path.isfile(_STATE_FILE):
            os.remove(_STATE_FILE)
        for d in (_CANCEL_DIR, _CLEAR_DIR, _DECISION_DIR):
            if os.path.isdir(d):
                for name in os.listdir(d):
                    os.remove(os.path.join(d, name))
    except Exception:
        pass

    device_name = args.name or os.uname().nodename
    rx_log_file("info", f"Quick Share receiver starting (device '{device_name}', dir {args.dir}, auto-accept {'on' if args.yes else 'off'})")

    signal.signal(signal.SIGTERM, _signal_handler)

    threading.Thread(target=_state_worker, daemon=True).start()

    try:
        run_receiver(
            output_dir=args.dir,
            device_name=device_name,
            iface=args.iface,
            auto_accept=args.yes,
            on_offer=lambda metadata, pin: _on_offer(metadata, pin, args.yes),
            on_progress=_on_progress,
            on_connection_end=_on_connection_end,
        )
    except KeyboardInterrupt:
        pass
    finally:
        rx_log_file("info", "Quick Share receiver stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
