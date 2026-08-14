"""BLE discovery "nudge" for Quick Share, per grishka/NearDrop's PROTOCOL.md
and Google's own nearby source.

A Quick Share *sender* broadcasts a BLE advertisement while it is looking for
nearby targets: a 16-bit service UUID 0xFE2C carrying a fixed-prefix service
data blob. Receivers in "hidden" visibility hear it, wake up, and start
advertising their mDNS service -- which is what makes them appear instantly in
the sender's share sheet instead of only showing up on the next periodic mDNS
re-announce (our 60s timer on hosts with no BLE).

This module implements both roles of that nudge on top of BlueZ's D-Bus API:

* :class:`NudgeManager` with ``advertise=True`` -- broadcasts the FE2C
  advertisement continuously while Quick Share is enabled, so this machine
  behaves like a real "visible to everyone" Quick Share device.
* :class:`NudgeManager` with ``scan=True`` -- passively scans for *other*
  senders' FE2C nudges and fires ``on_nudge`` when one is heard, so the mDNS
  advertiser can re-announce immediately (hidden senders surface fast).

Either half degrades gracefully: if python-dbus, the BlueZ adapter, or the
D-Bus policy is unavailable, it logs once and continues with the existing
mDNS-only behavior. The BLE path is a discovery accelerant, never a
prerequisite.
"""

from __future__ import annotations

import random
import threading
import time
from typing import Callable, Optional

try:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop

    _DBUS_OK = True
except Exception:  # pragma: no cover - import guard, not exercised here
    _DBUS_OK = False

from quickshare import debug  # pylint: disable=import-error

# grishka/NearDrop PROTOCOL.md: Android broadcasts a BLE advertisement with
# Service UUID = fe 2c and Service data =
#   fc 12 8e 01 42 00 00 00 00 00 00 00 00 00 [10 random bytes]
# The 14 fixed prefix bytes identify this as a Nearby Share nudge; the 10
# trailing bytes are per-advertisement randomness. Reproduced verbatim.
BLE_SERVICE_UUID = "FE2C"
BLE_SERVICE_DATA_PREFIX = bytes([0xFC, 0x12, 0x8E, 0x01, 0x42]) + bytes(9)
BLE_SERVICE_DATA_RANDOM_BYTES = 10

ADAPTER_PATH = "/org/bluez/hci0"
ADAPTER_IFACE = "org.bluez.Adapter1"
LE_ADV_MGR_IFACE = "org.bluez.LEAdvertisingManager1"
LE_ADV_IFACE = "org.bluez.LEAdvertisement1"
DEVICE_IFACE = "org.bluez.Device1"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
OBJ_MGR_IFACE = "org.freedesktop.DBus.ObjectManager"

# Re-register our own BLE advertisement on this cadence, mirroring the mDNS
# re-announce loop: keeps the advertisement fresh on peer host caches and lets
# the 10 random trailing bytes rotate (Android matches on the prefix, but
# fresh bytes are harmless and match real devices' behavior).
_REANNOUNCE_INTERVAL_SECONDS = 15.0

# Throttle on_nudge callbacks so a noisy sender can't hammer the mDNS
# re-announce loop.
_SCAN_TRIGGER_MIN_INTERVAL_SECONDS = 2.0


def build_nudge_service_data() -> bytes:
    """The 24-byte FE2C service data a Nearby Share sender broadcasts."""
    return BLE_SERVICE_DATA_PREFIX + bytes(random.getrandbits(8) for _ in range(BLE_SERVICE_DATA_RANDOM_BYTES))


def is_nudge_service_data(service_data: bytes) -> bool:
    """True if *service_data* carries the Nearby Share nudge prefix."""
    return service_data[: len(BLE_SERVICE_DATA_PREFIX)] == BLE_SERVICE_DATA_PREFIX


def _service_data_from_props(props) -> Optional[bytes]:
    """Pull the first FE2C service-data blob out of a BlueZ properties dict."""
    if not isinstance(props, dict):
        return None
    sdata = props.get("ServiceData")
    if not isinstance(sdata, dict):
        return None
    for uuid, raw in sdata.items():
        if uuid.upper().endswith("FE2C"):
            try:
                return bytes(raw)
            except Exception:
                return None
    return None


class _Advertisement(dbus.service.Object):  # type: ignore[misc]
    """org.bluez.LEAdvertisement1 implementation carrying the nudge data."""

    def __init__(self, bus, path: str, data: bytes) -> None:
        super().__init__(bus, path)
        self._data = data

    def _properties(self) -> dict:
        return {
            "Type": dbus.String("broadcast"),
            "ServiceUUIDs": dbus.Array([dbus.String(BLE_SERVICE_UUID)], signature="s"),
            "ServiceData": dbus.Dictionary(
                {dbus.String(BLE_SERVICE_UUID): dbus.Array(list(self._data), signature="y")},
                signature="sv",
            ),
            "Discoverable": dbus.Boolean(False),
        }

    @dbus.service.method(LE_ADV_IFACE, in_signature="", out_signature="a{sv}")
    def GetProperties(self):  # noqa: N802 - D-Bus method name
        return self._properties()

    @dbus.service.method(LE_ADV_IFACE, in_signature="s", out_signature="v")
    def Get(self, prop):  # noqa: N802 - D-Bus method name
        props = self._properties()
        if prop not in props:
            raise dbus.exceptions.DBusException(
                "Invalid property", name="org.freedesktop.DBus.Error.InvalidArgs"
            )
        return props[prop]

    @dbus.service.method(LE_ADV_IFACE, in_signature="sv", out_signature="")
    def Set(self, prop, value):  # noqa: N802 - D-Bus method name
        raise dbus.exceptions.DBusException(
            "Read-only property", name="org.freedesktop.DBus.Error.PropertyReadOnly"
        )

    @dbus.service.method(LE_ADV_IFACE, in_signature="", out_signature="")
    def Release(self):  # noqa: N802 - D-Bus method name
        debug.log("ble", "BLE nudge advertisement released")


class NudgeManager:
    """Owns the BLE nudge broadcast (and optional scan) in one GLib thread.

    The BlueZ advertisement object must be served by a D-Bus main loop, so the
    whole manager runs inside a single background thread running a GLib main
    loop: a periodic timer re-registers the advertisement, and (when scan is
    enabled) an ObjectManager signal handler watches for peers' FE2C nudges.
    """

    def __init__(
        self,
        advertise: bool = True,
        scan: bool = False,
        on_nudge: Optional[Callable[[], None]] = None,
        adapter_path: str = ADAPTER_PATH,
    ) -> None:
        self._advertise = advertise
        self._scan = scan
        self._on_nudge = on_nudge
        self._adapter_path = adapter_path
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._adv: Optional[_Advertisement] = None
        self._adv_path = ""
        self._adv_counter = [0]
        self._bus: Optional[dbus.SystemBus] = None
        self._loop = None
        self._error_logged = False
        self._last_trigger = 0.0

    def start(self) -> None:
        if not _DBUS_OK or self._thread is not None:
            if not _DBUS_OK:
                debug.log("ble", "BLE nudge unavailable (python-dbus not importable)")
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, daemon=True, name="ble-nudge")
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        loop = self._loop
        if loop is not None:
            try:
                loop.quit()
            except Exception:
                pass
        thread, self._thread = self._thread, None
        if thread is not None:
            thread.join(timeout=2.0)

    def _log_once(self, message: str) -> None:
        if not self._error_logged:
            self._error_logged = True
            debug.log("ble", message)

    def _run(self) -> None:
        try:
            DBusGMainLoop(set_as_default=True)
            self._bus = dbus.SystemBus()
            from gi.repository import GLib  # type: ignore

            self._loop = GLib.MainLoop()
        except Exception as exc:
            self._log_once(f"BLE nudge unavailable: {exc}")
            return

        if self._advertise:
            GLib.timeout_add_seconds(1, self._advertise_once)
            GLib.timeout_add_seconds(_REANNOUNCE_INTERVAL_SECONDS, self._advertise_once)
        if self._scan:
            GLib.idle_add(self._setup_scan)
            self._bus.add_signal_receiver(
                self._on_interfaces_added,
                dbus_interface=OBJ_MGR_IFACE,
                signal_name="InterfacesAdded",
                path="/",
            )
        self._loop.run()
        self._teardown()

    def _teardown(self) -> None:
        self._unregister_advertisement()
        if self._bus is not None and self._scan:
            try:
                adapter = dbus.Interface(
                    self._bus.get_object("org.bluez", self._adapter_path), ADAPTER_IFACE
                )
                adapter.StopDiscovery()
            except Exception:
                pass

    def _advertise_once(self) -> bool:
        if self._stop.is_set():
            return False
        try:
            self._unregister_advertisement()
            self._adv_counter[0] += 1
            self._adv_path = f"/retro/quickshare/nudge{self._adv_counter[0]}"
            self._adv = _Advertisement(self._bus, self._adv_path, build_nudge_service_data())
            manager = dbus.Interface(
                self._bus.get_object("org.bluez", self._adapter_path), LE_ADV_MGR_IFACE
            )
            manager.RegisterAdvertisement(self._adv_path, {})
            self._error_logged = False
            debug.log("ble", "BLE nudge advertisement registered")
        except Exception as exc:
            self._log_once(f"BLE nudge advertisement failed: {exc}")
        return not self._stop.is_set()

    def _unregister_advertisement(self) -> None:
        if self._adv is None or self._bus is None:
            return
        try:
            manager = dbus.Interface(
                self._bus.get_object("org.bluez", self._adapter_path), LE_ADV_MGR_IFACE
            )
            manager.UnregisterAdvertisement(self._adv_path)
        except Exception:
            pass
        try:
            self._adv.remove_from_connection()
        except Exception:
            pass
        self._adv = None

    def _setup_scan(self) -> bool:
        if self._stop.is_set():
            return False
        try:
            adapter = dbus.Interface(
                self._bus.get_object("org.bluez", self._adapter_path), ADAPTER_IFACE
            )
            try:
                adapter.SetDiscoveryFilter(
                    dbus.Dictionary({"DuplicateData": dbus.Boolean(True), "Transport": dbus.String("le")}, signature="sv")
                )
            except Exception:
                pass
            adapter.StartDiscovery()
            debug.log("ble", "BLE nudge scan started")
        except Exception as exc:
            self._log_once(f"BLE nudge scan failed: {exc}")
        return False

    def _on_interfaces_added(self, path, interfaces) -> None:
        if self._stop.is_set():
            return
        if DEVICE_IFACE not in interfaces:
            return
        data = _service_data_from_props(interfaces[DEVICE_IFACE])
        if data is None or not is_nudge_service_data(data):
            return
        now = time.monotonic()
        if now - self._last_trigger < _SCAN_TRIGGER_MIN_INTERVAL_SECONDS:
            return
        self._last_trigger = now
        debug.log("ble", "sender BLE nudge detected, re-announcing mDNS")
        if self._on_nudge is not None:
            try:
                self._on_nudge()
            except Exception:
                pass
