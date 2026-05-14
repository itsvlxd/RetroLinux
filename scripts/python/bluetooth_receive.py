#!/usr/bin/env python3
# pylint: disable=C0413

import os
import sys
import time
import signal
import threading
import subprocess

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib  # type: ignore

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from lib.python.log import rx_log  # pylint: disable=import-error
from lib.python.obex import (  # pylint: disable=import-error
    BUS_NAME, AGENT_IFACE, PROPS_IFACE, TRANSFER_IFACE, SESSION_IFACE,
    clean_cancel_flag, get_cancel_flag_path,
)
from lib.python.env import ensure_dbus, get_shell_env  # pylint: disable=import-error

ensure_dbus()


class ObexAgent(dbus.service.Object):
    def __init__(self, bus, path, shell_script, dry_run=False):
        super().__init__(bus, path)
        self.shell_script = shell_script
        self.dry_run = dry_run
        self.bus = bus
        self._receivers = {}
        self._start_times = {}
        self._needs_move = False

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s")
    def AuthorizePush(self, transfer_path):
        transfer_path = str(transfer_path)
        try:
            obj = self.bus.get_object(BUS_NAME, transfer_path)
            iface = dbus.Interface(obj, PROPS_IFACE)
            props = iface.GetAll(TRANSFER_IFACE)
        except dbus.DBusException as exc:
            rx_log("error", f"Cannot read transfer properties: {exc}")
            err = "org.bluez.obex.Error.Rejected"
            raise dbus.exceptions.DBusException(err)

        filename = str(props.get("Name", "unknown_file"))
        size = int(props.get("Size", 0))
        source = "Unknown"

        session_path = str(props.get("Session", ""))
        if session_path:
            try:
                session_obj = self.bus.get_object(BUS_NAME, session_path)
                session_props = dbus.Interface(session_obj, PROPS_IFACE)
                source = str(session_props.Get(SESSION_IFACE, "Destination"))
            except Exception as e:
                rx_log("warn", f"Could not resolve session address: {e}")

        rx_log("info", f"Incoming: {filename} ({size} bytes) from {source}")

        if source != "Unknown":
            clean_cancel_flag(source)

        self._start_times[transfer_path] = time.time()
        self._subscribe_progress(transfer_path, size, filename, source)

        result_event = threading.Event()
        result_box = [False]

        def _ask():
            if self.dry_run:
                result_box[0] = True
            else:
                rc = subprocess.call(
                    [self.shell_script, "--obex-ask", filename, str(size), source],
                    env=get_shell_env()
                )
                if rc == 0:
                    result_box[0] = True
                    result = subprocess.run(
                        [self.shell_script, "--obex-ensure-download-dir"],
                        capture_output=True, text=True,
                        env=get_shell_env()
                    )
                    dl_dir = result.stdout.strip()
                    if dl_dir:
                        rx_log("info", f"Download directory set to: {dl_dir}")
                    self._needs_move = True
                else:
                    result_box[0] = False
            result_event.set()

        threading.Thread(target=_ask, daemon=True).start()

        main_ctx = GLib.MainContext.default()
        while not result_event.is_set():
            main_ctx.iteration(may_block=False)
            time.sleep(0.05)

        if result_box[0]:
            return filename
        else:
            self._remove_receiver(transfer_path)
            self._start_times.pop(transfer_path, None)
            err = "org.bluez.obex.Error.Rejected"
            raise dbus.exceptions.DBusException("Rejected", name=err)

    def _subscribe_progress(self, transfer_path, total_size, filename, source):
        last_pct = [-1]
        self._cancelled = {}

        def _check_cancel():
            flag = get_cancel_flag_path(source)
            if os.path.exists(flag) and transfer_path not in self._cancelled:
                self._cancelled[transfer_path] = True
                rx_log(
                    "info",
                    f"Transfer cancelled by user, restarting agent: {filename}"
                )
                subprocess.Popen(
                    [self.shell_script, "--receive-restart"],
                    env=get_shell_env(),
                    start_new_session=True
                )
                try:
                    transfer_obj = self.bus.get_object(
                        BUS_NAME, transfer_path
                    )
                    transfer = dbus.Interface(
                        transfer_obj, "org.bluez.obex.Transfer1"
                    )
                    transfer.Cancel()
                except Exception:
                    pass
                os._exit(0)
            return False

        def on_prop_changed(iface, changed, invalidated, path=None):
            if iface != TRANSFER_IFACE:
                return
            if "Status" in changed:
                status = str(changed["Status"])
                if status == "active":
                    if _check_cancel():
                        return
                if status in ["complete", "error"]:
                    start_time = self._start_times.pop(
                        transfer_path, time.time()
                    )
                    elapsed = int(time.time() - start_time)
                    was_cancelled = self._cancelled.get(transfer_path)
                    final = "cancelled" if was_cancelled else status
                    subprocess.run([
                        self.shell_script, "--obex-notify-done",
                        source, filename, final, str(elapsed)
                    ])
                    self._remove_receiver(transfer_path)
                    if status == "complete" and self._needs_move:
                        rx_log(
                            "info",
                            "First transfer complete, "
                            "moving file and restarting with new root"
                        )
                        subprocess.Popen([
                            self.shell_script, "--obex-move-and-restart",
                            filename, source
                        ], env=get_shell_env(), start_new_session=True)
            if "Transferred" in changed:
                t = int(changed["Transferred"])
                pct = int((t / total_size * 100) if total_size > 0 else 0)
                if pct > last_pct[0]:
                    last_pct[0] = pct
                    subprocess.run([
                        self.shell_script, "--obex-notify-progress",
                        source, filename, str(pct), str(t), str(total_size)
                    ])
                    if _check_cancel():
                        return

        match = self.bus.add_signal_receiver(
            on_prop_changed,
            dbus_interface=PROPS_IFACE,
            signal_name="PropertiesChanged",
            path=transfer_path,
            path_keyword="path"
        )
        self._receivers[transfer_path] = match

    def _remove_receiver(self, transfer_path):
        match = self._receivers.pop(transfer_path, None)
        if match:
            self.bus.remove_signal_receiver(
                match,
                dbus_interface=PROPS_IFACE,
                signal_name="PropertiesChanged",
                path=transfer_path
            )

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        rx_log("info", "Agent released.")


def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    unique_path = f"/retro/agent_{int(time.time())}"
    agent = ObexAgent(
        bus, unique_path,
        os.path.abspath(sys.argv[1]),
        dry_run="--dry-run" in sys.argv
    )
    manager = dbus.Interface(
        bus.get_object(BUS_NAME, "/org/bluez/obex"),
        "org.bluez.obex.AgentManager1"
    )
    manager.RegisterAgent(unique_path)
    loop = GLib.MainLoop()

    def _shutdown(sig, frame):
        try:
            manager.UnregisterAgent(unique_path)
        except Exception:
            pass
        loop.quit()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)
    loop.run()


if __name__ == "__main__":
    main()
