#!/usr/bin/env python3

import os
import sys
import time
import signal
import logging
import threading
import subprocess

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

logging.basicConfig(
    level=logging.INFO,
    format="[OBEX] %(levelname)s: %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger(__name__)

if "DBUS_SESSION_BUS_ADDRESS" not in os.environ:
    os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{os.getuid()}/bus"

BUS_NAME       = "org.bluez.obex"
AGENT_IFACE    = "org.bluez.obex.Agent1"
PROPS_IFACE    = "org.freedesktop.DBus.Properties"
TRANSFER_IFACE = "org.bluez.obex.Transfer1"
SESSION_IFACE  = "org.bluez.obex.Session1"

class ObexAgent(dbus.service.Object):
    def __init__(self, bus, path, shell_script, dry_run=False):
        super().__init__(bus, path)
        self.shell_script = shell_script
        self.dry_run      = dry_run
        self.bus          = bus
        self._receivers   = {}
        self._start_times = {}

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s")
    def AuthorizePush(self, transfer_path):
        transfer_path = str(transfer_path)
        try:
            obj   = self.bus.get_object(BUS_NAME, transfer_path)
            iface = dbus.Interface(obj, PROPS_IFACE)
            props = iface.GetAll(TRANSFER_IFACE)
        except dbus.DBusException as exc:
            log.error("Cannot read transfer properties: %s", exc)
            raise dbus.exceptions.DBusException("org.bluez.obex.Error.Rejected")

        filename = str(props.get("Name", "unknown_file"))
        size     = int(props.get("Size", 0))
        source   = "Unknown"

        session_path = str(props.get("Session", ""))
        if session_path:
            try:
                session_obj = self.bus.get_object(BUS_NAME, session_path)
                session_props = dbus.Interface(session_obj, PROPS_IFACE)
                source = str(session_props.Get(SESSION_IFACE, "Destination"))
            except Exception as e:
                log.warning("Could not resolve session address: %s", e)

        log.info("Incoming: %s (%d bytes) from %s", filename, size, source)

        mac_clean = source.replace(":", "")
        if len(mac_clean) == 12:
            notif_id = int(mac_clean, 16) % 1000000
            if notif_id < 10000:
                notif_id += 10000
            cancel_flag = f"/tmp/.bt_receive_{notif_id}_cancel"
            if os.path.exists(cancel_flag):
                os.remove(cancel_flag)
                log.info("Cleaned stale cancel flag for %s", source)

        self._start_times[transfer_path] = time.time()
        self._subscribe_progress(transfer_path, size, filename, source)

        result_event = threading.Event()
        result_box   = [False]

        def _ask():
            if self.dry_run:
                result_box[0] = True
            else:
                rc = subprocess.call(
                    [self.shell_script, "--obex-ask", filename, str(size), source],
                    env={**os.environ, "DISPLAY": os.environ.get("DISPLAY", ""), "DBUS_SESSION_BUS_ADDRESS": os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")}
                )
                result_box[0] = (rc == 0)
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
            raise dbus.exceptions.DBusException("Rejected", name="org.bluez.obex.Error.Rejected")

    def _subscribe_progress(self, transfer_path, total_size, filename, source):
        last_pct = [-1]
        self._cancelled = {}

        def _check_cancel():
            mac_clean = source.replace(":", "")
            if len(mac_clean) == 12:
                notif_id = int(mac_clean, 16) % 1000000
                if notif_id < 10000:
                    notif_id += 10000
                cancel_flag = f"/tmp/.bt_receive_{notif_id}_cancel"
                if os.path.exists(cancel_flag) and transfer_path not in self._cancelled:
                    self._cancelled[transfer_path] = True
                    log.info("Transfer cancelled by user, restarting agent: %s", filename)
                    subprocess.Popen([self.shell_script, "--receive-restart"],
                                     env={**os.environ, "DISPLAY": os.environ.get("DISPLAY", ""),
                                          "DBUS_SESSION_BUS_ADDRESS": os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")},
                                     start_new_session=True)
                    try:
                        transfer_obj = self.bus.get_object(BUS_NAME, transfer_path)
                        transfer = dbus.Interface(transfer_obj, "org.bluez.obex.Transfer1")
                        transfer.Cancel()
                    except Exception:
                        pass
                    os._exit(0)
            return False

        def on_prop_changed(iface, changed, invalidated, path=None):
            if iface != TRANSFER_IFACE: return
            if "Status" in changed:
                status = str(changed["Status"])
                if status == "active":
                    if _check_cancel():
                        return
                if status in ["complete", "error"]:
                    start_time = self._start_times.pop(transfer_path, time.time())
                    elapsed = int(time.time() - start_time)
                    final_status = "cancelled" if self._cancelled.get(transfer_path) else status
                    subprocess.run([self.shell_script, "--obex-notify-done", source, filename, final_status, str(elapsed)])
                    self._remove_receiver(transfer_path)
            if "Transferred" in changed:
                t = int(changed["Transferred"])
                pct = int((t / total_size * 100) if total_size > 0 else 0)
                if pct > last_pct[0]:
                    last_pct[0] = pct
                    subprocess.run([self.shell_script, "--obex-notify-progress", source, filename, str(pct), str(t), str(total_size)])
                    if _check_cancel():
                        return

        match = self.bus.add_signal_receiver(on_prop_changed, dbus_interface=PROPS_IFACE, signal_name="PropertiesChanged", path=transfer_path, path_keyword="path")
        self._receivers[transfer_path] = match

    def _remove_receiver(self, transfer_path):
        match = self._receivers.pop(transfer_path, None)
        if match: self.bus.remove_signal_receiver(match, dbus_interface=PROPS_IFACE, signal_name="PropertiesChanged", path=transfer_path)

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self): log.info("Agent released.")

def main():
    if len(sys.argv) < 2: sys.exit(1)
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    unique_path = f"/retro/agent_{int(time.time())}"
    agent = ObexAgent(bus, unique_path, os.path.abspath(sys.argv[1]), dry_run="--dry-run" in sys.argv)
    manager = dbus.Interface(bus.get_object(BUS_NAME, "/org/bluez/obex"), "org.bluez.obex.AgentManager1")
    manager.RegisterAgent(unique_path)
    loop = GLib.MainLoop()
    def _shutdown(sig, frame):
        try: manager.UnregisterAgent(unique_path)
        except: pass
        loop.quit(); sys.exit(0)
    signal.signal(signal.SIGTERM, _shutdown); signal.signal(signal.SIGINT, _shutdown)
    loop.run()

if __name__ == "__main__":
    main()
