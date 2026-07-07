"""Bluetooth management page — radio, devices, receive agent."""

import os
import subprocess
import threading
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk, Pango

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_BT_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "bluetooth_core.sh")
_BT_ICON = "bluetooth-active-symbolic"

_CATEGORY_ICONS = {
    "phone": "phone-symbolic",
    "computer": "computer-symbolic",
    "audio": "audio-headphones-symbolic",
    "audio+input": "audio-input-microphone-symbolic",
    "controller": "input-gaming-symbolic",
    "input": "input-keyboard-symbolic",
    "other": "bluetooth-active-symbolic",
}



def _run(args: list[str], timeout: int = 5) -> str:
    try:
        r = subprocess.run(
            ["bash", _BT_CORE, *args],
            capture_output=True, text=True, timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _category_icon(cat: str) -> str:
    return _CATEGORY_ICONS.get(cat, _CATEGORY_ICONS["other"])


def _format_mac(mac: str) -> str:
    m = mac.upper().replace("-", ":").replace(" ", "")
    if len(m) == 12:
        return ":".join(m[i:i+2] for i in range(0, 12, 2))
    return m


class _DeviceRow(Gtk.ListBoxRow):
    def __init__(self, mac: str, name: str, cat: str, connected: bool,
                 trusted: bool, audio_capable: bool, is_nearby: bool = False,
                 can_send: bool = False,
                 on_connect=None, on_disconnect=None, on_forget=None,
                 on_send=None, on_trust=None, on_pair=None,
                 radio_on: bool = True):
        super().__init__()
        self.mac = mac
        self.name = name
        self.cat = cat
        self.connected = connected
        self.audio_capable = audio_capable
        self._on_trust = on_trust

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(8)
        box.set_margin_end(8)

        icon_img = Gtk.Image.new_from_icon_name(_category_icon(cat))
        icon_img.set_valign(Gtk.Align.START)
        icon_img.set_margin_top(4)
        icon_img.set_pixel_size(24)
        box.append(icon_img)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        text_box.set_hexpand(True)

        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        name_lbl = Gtk.Label(label=name)
        name_lbl.set_halign(Gtk.Align.START)
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        name_box.append(name_lbl)

        if trusted:
            trust_lbl = Gtk.Label(label="TRUSTED")
            trust_lbl.add_css_class("badge")
            trust_lbl.set_opacity(0.8)
            name_box.append(trust_lbl)

        text_box.append(name_box)

        mac_lbl = Gtk.Label(label=mac)
        mac_lbl.set_halign(Gtk.Align.START)
        mac_lbl.add_css_class("dim-label")
        mac_lbl.add_css_class("caption")
        text_box.append(mac_lbl)

        box.append(text_box)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        btn_box.set_valign(Gtk.Align.CENTER)

        if is_nearby:
            if on_pair:
                pair_btn = Gtk.Button(label="Pair")
                pair_btn.add_css_class("suggested-action")
                pair_btn.connect("clicked", lambda _b: on_pair(mac, name))
                btn_box.append(pair_btn)
        else:
            if connected:
                self.add_css_class("option-managed")
            else:
                self.add_css_class("option-default")

            if connected and on_disconnect:
                d_btn = Gtk.Button(icon_name="media-playback-stop-symbolic")
                d_btn.set_tooltip_text("Disconnect")
                d_btn.connect("clicked", lambda _b: on_disconnect(mac))
                btn_box.append(d_btn)
            elif not connected:
                if on_connect:
                    c_btn = Gtk.Button(icon_name="media-playback-start-symbolic")
                    c_btn.set_tooltip_text("Connect")
                    c_btn.set_sensitive(radio_on)
                    c_btn.add_css_class("suggested-action")
                    c_btn.connect("clicked", lambda _b: on_connect(mac))
                    btn_box.append(c_btn)

            if on_send and can_send:
                s_btn = Gtk.Button(icon_name="document-send-symbolic")
                s_btn.set_tooltip_text("Send file")
                s_btn.set_sensitive(radio_on)
                s_btn.connect("clicked", lambda _b: on_send(mac, name))
                btn_box.append(s_btn)

            if on_trust and not is_nearby:
                t_btn = Gtk.Button(icon_name="channel-secure-symbolic" if trusted else "channel-insecure-symbolic")
                t_btn.set_tooltip_text("Trusted" if trusted else "Not trusted — click to trust")
                t_btn.connect("clicked", lambda _b: on_trust(mac))
                btn_box.append(t_btn)

            if on_forget and not connected:
                f_btn = Gtk.Button(icon_name="user-trash-symbolic")
                f_btn.set_tooltip_text("Forget device")
                f_btn.connect("clicked", lambda _b: on_forget(mac))
                btn_box.append(f_btn)

        box.append(btn_box)
        self.set_child(box)

    def set_connected(self, connected: bool) -> None:
        self.connected = connected
        self.remove_css_class("option-managed")
        self.remove_css_class("option-default")
        if connected:
            self.add_css_class("option-managed")
        else:
            self.add_css_class("option-default")


class BluetoothPage:
    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._dirty = False
        self._on_dirty_changed = None
        self._orig: dict[str, str] = {}
        self._pending: dict[str, str] = {}
        self._setting_value = False
        self._status: dict[str, str] = {}
        self._tick_source = None

        self._paired_devices: list[dict] = []
        self._nearby_devices: list[dict] = []
        self._paired_listbox: Gtk.ListBox | None = None
        self._device_rows: dict[str, _DeviceRow] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        scan_btn = Gtk.Button(icon_name="list-add-symbolic")
        scan_btn.set_tooltip_text("Scan for nearby devices")
        scan_btn.connect("clicked", lambda _b: self._show_scan_dialog())
        header.pack_start(scan_btn)

        self._load_data()

        # Sidebar switch must be added after sidebar is populated (happens after build)
        GLib.idle_add(self._add_sidebar_switch)

        # Bluetooth Status
        sg = Adw.PreferencesGroup(title="Bluetooth Status")
        self._build_status_section(sg)
        self._content_box.append(sg)

        # Paired Devices
        pg = Adw.PreferencesGroup(title="Paired Devices")
        self._build_paired_section(pg)
        self._content_box.append(pg)

        self._tick_source = GLib.timeout_add(5000, self._tick)

        return toolbar_view

    def _load_data(self) -> None:
        self._status = {}
        raw = _run(["--status"])
        parts = raw.split("|")
        if len(parts) >= 7:
            self._status = {
                "radio": parts[0],
                "power_mode": parts[1],
                "discoverable": parts[2],
                "pairable": parts[3],
                "chip": parts[4],
                "ver": parts[5],
                "conns": parts[6],
                "adapter": parts[7] if len(parts) > 7 else "",
                "adapter_mac": parts[8] if len(parts) > 8 else "",
            }

        self._paired_devices = []
        raw_paired = _run(["--paired-detailed"])
        if raw_paired:
            for line in raw_paired.splitlines():
                parts = line.split("|")
                if len(parts) >= 6:
                    cat = parts[2]
                    mac = parts[3]
                    name = parts[4]
                    connected = parts[5] == "yes"
                    self._paired_devices.append({
                        "mac": mac, "name": name, "cat": cat, "connected": connected,
                    })

        self._nearby_devices = []
        raw_nearby = _run(["--nearby-detailed"])
        if raw_nearby and raw_nearby != "ERR_SCAN_OFF":
            for line in raw_nearby.splitlines():
                parts = line.split("|")
                if len(parts) >= 5:
                    cat = parts[2]
                    mac = parts[3]
                    name = parts[4]
                    self._nearby_devices.append({
                        "mac": mac, "name": name, "cat": cat,
                    })

    def _full_refresh(self) -> None:
        self._load_data()
        GLib.idle_add(self._rebuild_device_list)

    def _build_status_section(self, group: Adw.PreferencesGroup) -> None:
        radio_on = self._status.get("radio", "no") == "yes"

        sw = Adw.SwitchRow(
            title="Bluetooth Radio",
            subtitle="Enable or disable the Bluetooth adapter",
        )
        sw.set_active(radio_on)
        sw.connect("notify::active", self._on_radio_toggle)
        group.add(sw)
        self._radio_switch = sw

        rx_status, _rx_dir = "stopped", os.path.expanduser("~/Downloads")
        raw_rx = _run(["--receive-status"])
        if "|" in raw_rx:
            rx_status = raw_rx.split("|", 1)[0]

        rx_sw = Adw.SwitchRow(
            title="Allow receiving files",
            subtitle="Accept incoming Bluetooth file transfers",
        )
        rx_sw.set_active(rx_status == "running")
        rx_sw.connect("notify::active", self._on_rx_switch)
        group.add(rx_sw)
        self._rx_switch = rx_sw

        adapter_mac = self._status.get("adapter_mac", "")
        mac_row = Adw.ActionRow(title="Adapter MAC", subtitle=adapter_mac)
        group.add(mac_row)

        chip = self._status.get("chip", "Unknown")
        chip_row = Adw.ActionRow(title="Adapter Chip", subtitle=chip)
        group.add(chip_row)

        ver = self._status.get("ver", "")
        ver_row = Adw.ActionRow(title="Stack Version", subtitle=f"Bluetooth {ver}")
        group.add(ver_row)

    def _add_sidebar_switch(self) -> bool:
        sidebar = getattr(self._window, "_sidebar", None)
        if sidebar:
            row = sidebar._rows_by_id.get("bluetooth")
            if row is not None:
                if hasattr(row, "_bt_power_switch"):
                    return False
                power_sw = Gtk.Switch()
                power_sw.set_valign(Gtk.Align.CENTER)
                power_sw.set_margin_end(6)
                power_sw.set_active(self._status.get("radio") == "yes")
                power_sw.connect("notify::active", self._on_sidebar_power_toggle)
                row.add_suffix(power_sw)
                row._bt_power_switch = power_sw
                self._sidebar_power_switch = power_sw
        return False

    def _on_sidebar_power_toggle(self, sw: Gtk.Switch, _pspec) -> None:
        if self._setting_value:
            return
        if sw.get_active():
            _run(["--power-on"])
        else:
            _run(["--receive-stop"])
            _run(["--power-off"])

    def _on_radio_toggle(self, sw: Adw.SwitchRow, _pspec) -> None:
        if sw.get_active():
            _run(["--power-on"])
        else:
            _run(["--receive-stop"])
            _run(["--power-off"])

    def _on_rx_switch(self, sw: Adw.SwitchRow, _pspec) -> None:
        if sw.get_active():
            res = _run(["--receive-start"])
            if "OK" not in res:
                self._window.show_toast("Failed to start receiver", timeout=5)
                sw.set_active(False)
            else:
                self._window.show_toast("File reception enabled")
        else:
            _run(["--receive-stop"])
            self._window.show_toast("File reception disabled")

    def _build_paired_section(self, group: Adw.PreferencesGroup) -> None:
        self._paired_listbox = Gtk.ListBox()
        self._paired_listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._paired_listbox.add_css_class("boxed-list")
        group.add(self._paired_listbox)
        self._rebuild_device_list()

    def _show_scan_dialog(self) -> None:
        _run(["--toggle-discovery"])
        _run(["--scan-on"])

        dialog = Adw.Dialog()
        dialog.set_title("Nearby Devices")
        dialog.set_content_width(500)
        dialog.set_content_height(450)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        refresh_btn = Gtk.Button(label="Refresh")
        refresh_btn.connect("clicked", lambda _b: refresh_list())
        header.pack_start(refresh_btn)
        toolbar.add_top_bar(header)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(500)
        clamp.set_tightening_threshold(400)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(8)
        box.set_margin_end(8)

        info_lbl = Gtk.Label(label="Scanning for 3 minutes...")
        info_lbl.set_halign(Gtk.Align.START)
        info_lbl.add_css_class("dim-label")
        box.append(info_lbl)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        listbox.set_vexpand(True)
        listbox.add_css_class("boxed-list")

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(listbox)
        scrolled.set_vexpand(True)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        box.append(frame)

        clamp.set_child(box)
        scrolled2 = Gtk.ScrolledWindow()
        scrolled2.set_child(clamp)
        scrolled2.set_vexpand(True)
        toolbar.set_content(scrolled2)
        dialog.set_child(toolbar)

        def refresh_list():
            raw = _run(["--nearby-detailed"])
            while child := listbox.get_first_child():
                listbox.remove(child)
            if raw and raw != "ERR_SCAN_OFF":
                for line in raw.splitlines():
                    p = line.split("|")
                    if len(p) >= 5:
                        cat, mac, name = p[2], p[3], p[4]
                        row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
                        row_box.set_margin_top(6)
                        row_box.set_margin_bottom(6)
                        row_box.set_margin_start(8)
                        row_box.set_margin_end(8)
                        img = Gtk.Image.new_from_icon_name(_category_icon(cat))
                        img.set_pixel_size(24)
                        img.set_valign(Gtk.Align.CENTER)
                        row_box.append(img)
                        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
                        text_box.set_hexpand(True)
                        n_lbl = Gtk.Label(label=name)
                        n_lbl.set_halign(Gtk.Align.START)
                        n_lbl.set_ellipsize(Pango.EllipsizeMode.END)
                        text_box.append(n_lbl)
                        m_lbl = Gtk.Label(label=mac)
                        m_lbl.set_halign(Gtk.Align.START)
                        m_lbl.add_css_class("dim-label")
                        m_lbl.add_css_class("caption")
                        text_box.append(m_lbl)
                        row_box.append(text_box)
                        pair_btn = Gtk.Button(label="Pair")
                        pair_btn.add_css_class("suggested-action")
                        pair_btn.set_valign(Gtk.Align.CENTER)
                        pair_btn.connect("clicked", lambda _b, m=mac, n=name: (
                            dialog.close(),
                            self._window.show_toast(f"Pairing with {n}..."),
                            threading.Thread(target=lambda: (
                                _run(["--connect", m, n], timeout=15),
                                GLib.idle_add(self._full_refresh),
                            ), daemon=True).start(),
                        ))
                        row_box.append(pair_btn)
                        row = Gtk.ListBoxRow()
                        row.set_child(row_box)
                        listbox.append(row)
            if not listbox.get_first_child():
                empty_lbl = Gtk.Label(label="No devices found yet...")
                empty_lbl.set_margin_top(16)
                empty_lbl.set_margin_bottom(16)
                empty_lbl.set_halign(Gtk.Align.CENTER)
                empty_lbl.add_css_class("dim-label")
                row = Gtk.ListBoxRow()
                row.set_child(empty_lbl)
                listbox.append(row)

        refresh_list()
        source = GLib.timeout_add(2000, refresh_list)

        def _on_dialog_closed(_d):
            try:
                GLib.source_remove(source)
            except Exception:
                pass
        dialog.connect("closed", _on_dialog_closed)
        dialog.present(self._window)

    def _rebuild_device_list(self) -> None:
        if not self._paired_listbox:
            return
        while child := self._paired_listbox.get_first_child():
            self._paired_listbox.remove(child)

        self._device_rows.clear()

        for dev in self._paired_devices:
            mac = dev["mac"]
            cat = dev["cat"]
            is_trusted = subprocess.run(
                ["bluetoothctl", "info", mac],
                capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
            ).stdout.find("Trusted: yes") != -1
            can_send = cat in ("phone", "computer")
            row = _DeviceRow(
                mac=mac,
                name=dev["name"],
                cat=cat,
                connected=dev["connected"],
                trusted=is_trusted,
                audio_capable=self._is_audio(cat),
                can_send=can_send,
                radio_on=self._status.get("radio") == "yes",
                on_connect=self._connect_device,
                on_disconnect=self._disconnect_device,
                on_forget=self._forget_device,
                on_send=self._send_file,
                on_trust=self._toggle_trust,
            )
            self._paired_listbox.append(row)
            self._device_rows[mac] = row

        if not self._paired_devices:
            empty_lbl = Gtk.Label(label="No paired devices")
            empty_lbl.set_margin_top(16)
            empty_lbl.set_margin_bottom(16)
            empty_lbl.add_css_class("dim-label")
            empty_lbl.set_halign(Gtk.Align.CENTER)
            self._paired_listbox.append(empty_lbl)

    @staticmethod
    def _is_audio(cat: str) -> bool:
        return cat in ("audio", "audio+input")

    def _connect_device(self, mac: str) -> None:
        def do_connect():
            res = _run(["--connect", mac], timeout=10)
            if "OK" in res:
                GLib.idle_add(lambda: self._window.show_toast(f"Connected to {mac}"))
                GLib.idle_add(self._full_refresh)
            else:
                GLib.idle_add(lambda: self._window.show_toast(f"Connection failed", timeout=5))
        threading.Thread(target=do_connect, daemon=True).start()

    def _disconnect_device(self, mac: str) -> None:
        _run(["--disconnect", mac])
        self._window.show_toast(f"Disconnected {mac}")
        self._full_refresh()

    def _forget_device(self, mac: str) -> None:
        _run(["--forget", mac])
        self._window.show_toast("Device forgotten")
        self._full_refresh()

    def _send_file(self, mac: str, name: str) -> None:
        from gi.repository import Gio

        dialog = Gtk.FileDialog.new()
        dialog.set_title(f"Select file to send to {name}")

        def on_file_chosen(_dlg, result):
            try:
                gfile = dialog.open_finish(result)
            except GLib.Error:
                return
            if not gfile:
                return
            file_path = gfile.get_path()
            if not file_path or not os.path.isfile(file_path):
                return

            self._window.show_toast(f"Sending to {name}...")
            def do_send():
                res = _run(["--send", mac, file_path], timeout=180)
                if "OK" in res:
                    GLib.idle_add(lambda: self._window.show_toast(f"Sent to {name}"))
                else:
                    GLib.idle_add(lambda: self._window.show_toast(f"Send failed", timeout=5))
            threading.Thread(target=do_send, daemon=True).start()

        dialog.open(self._window, None, on_file_chosen)

    def _toggle_trust(self, mac: str) -> None:
        is_trusted = subprocess.run(
            ["bluetoothctl", "info", mac],
            capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
        ).stdout.find("Trusted: yes") != -1
        if is_trusted:
            _run(["--untrust", mac])
            self._window.show_toast("Trust removed")
        else:
            _run(["--trust", mac])
            self._window.show_toast("Device trusted")
        self._full_refresh()

    def _pair_device(self, mac: str, name: str) -> None:
        def do_pair():
            res = _run(["--connect", mac, name], timeout=15)
            if "OK" in res:
                GLib.idle_add(lambda: self._window.show_toast(f"Paired with {name}"))
                GLib.idle_add(self._full_refresh)
            else:
                GLib.idle_add(lambda: self._window.show_toast(f"Pairing failed", timeout=5))
        threading.Thread(target=do_pair, daemon=True).start()

    def _tick(self) -> bool:
        threading.Thread(target=self._tick_worker, daemon=True).start()
        return True

    def _tick_worker(self) -> None:
        try:
            r = subprocess.run(
                ["bash", _BT_CORE, "--status"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            paired_out = _run(["--paired-detailed"])
            GLib.idle_add(self._apply_status, r.stdout, paired_out)
        except Exception:
            pass

    def _apply_status(self, output: str, paired_out: str) -> None:
        parts = output.strip().split("|")
        if len(parts) < 7:
            return
        self._status["radio"] = parts[0]
        self._status["discoverable"] = parts[2]
        self._status["pairable"] = parts[3]
        self._status["conns"] = parts[6]

        radio_on = parts[0] == "yes"
        if hasattr(self, "_radio_switch"):
            self._radio_switch.set_active(radio_on)

        if hasattr(self, "_sidebar_power_switch"):
            self._setting_value = True
            self._sidebar_power_switch.set_active(radio_on)
            self._setting_value = False

        # Rebuild paired device list with current connection states
        self._paired_devices = []
        if paired_out:
            for line in paired_out.splitlines():
                p = line.split("|")
                if len(p) >= 6:
                    self._paired_devices.append({
                        "mac": p[3], "name": p[4],
                        "cat": p[2], "connected": p[5] == "yes",
                    })
        self._rebuild_device_list()

    # ── Save lifecycle ──

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        self._dirty = False

    def discard(self) -> None:
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._dirty:
            yield PendingChange(
                category="Bluetooth",
                title="Bluetooth Configuration",
                subtitle="Bluetooth settings changed",
                navigate_to="bluetooth",
                icon=_BT_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "bt:status", "label": "Bluetooth Status",
             "description": "Radio power, adapter info, discoverable, receive agent",
             "_group_id": "bluetooth", "_group_label": "Bluetooth", "_section_label": "Status"},
            {"key": "bt:paired", "label": "Paired Devices",
             "description": "List of paired Bluetooth devices",
             "_group_id": "bluetooth", "_group_label": "Bluetooth", "_section_label": "Paired Devices"},
            {"key": "bt:nearby", "label": "Nearby Devices",
             "description": "Scan and pair with nearby Bluetooth devices",
             "_group_id": "bluetooth", "_group_label": "Bluetooth", "_section_label": "Nearby Devices"},
        ]

    def destroy(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None
