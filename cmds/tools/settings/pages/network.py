"""Network management page — status, WiFi, Ethernet, actions."""

import os
import re
import subprocess
import threading
import time
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gdk, GLib, Gtk, Pango, cairo

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_NET_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "network_core.sh")
_NET_ICON = "network-wireless-symbolic"


def _run(args: list[str], timeout: int = 10) -> str:
    try:
        r = subprocess.run(
            ["bash", _NET_CORE, *args],
            capture_output=True, text=True, timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _parse_kv(out: str) -> dict[str, str]:
    d = {}
    for line in out.splitlines():
        for m in re.finditer(r"(\w+)=([^|]+)", line):
            d[m.group(1)] = m.group(2)
    return d


class NetIOStats:
    """Reads /sys/class/net/<iface>/statistics and maintains a rolling rate buffer."""

    def __init__(self, iface: str):
        self._rx_path = f"/sys/class/net/{iface}/statistics/rx_bytes"
        self._tx_path = f"/sys/class/net/{iface}/statistics/tx_bytes"
        self._last_rx = 0
        self._last_tx = 0
        self._last_time = 0.0
        self.rx_rates: list[float] = []
        self.tx_rates: list[float] = []
        self._max_samples = 60

    def sample(self) -> None:
        try:
            with open(self._rx_path) as f:
                rx = int(f.read().strip())
        except (FileNotFoundError, ValueError, OSError):
            rx = self._last_rx
        try:
            with open(self._tx_path) as f:
                tx = int(f.read().strip())
        except (FileNotFoundError, ValueError, OSError):
            tx = self._last_tx

        now = time.monotonic()
        if self._last_time > 0:
            dt = now - self._last_time
            if dt > 0:
                rx_rate = (rx - self._last_rx) / dt
                tx_rate = (tx - self._last_tx) / dt
                self.rx_rates.append(rx_rate)
                self.tx_rates.append(tx_rate)
                if len(self.rx_rates) > self._max_samples:
                    self.rx_rates.pop(0)
                    self.tx_rates.pop(0)

        self._last_rx = rx
        self._last_tx = tx
        self._last_time = now

    def max_rate(self) -> float:
        all_vals = self.rx_rates + self.tx_rates
        return max(all_vals) if all_vals else 1.0

    def clear(self) -> None:
        self.rx_rates.clear()
        self.tx_rates.clear()
        self._last_rx = 0
        self._last_tx = 0
        self._last_time = 0.0


class NetIOGraph(Gtk.DrawingArea):
    """Live RX/TX network traffic sparkline rendered with Cairo."""

    def __init__(self, iface: str):
        super().__init__()
        self.set_hexpand(True)
        self.set_size_request(-1, 80)
        self.set_valign(Gtk.Align.FILL)

        self._stats = NetIOStats(iface)
        self.set_draw_func(self._on_draw)
        self._timer = GLib.timeout_add(1000, self._tick)
        self._stats.sample()

    def _tick(self) -> bool:
        self._stats.sample()
        self.queue_draw()
        return True

    def stop(self) -> None:
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0

    def _on_destroy(self, *_args) -> None:
        self.stop()

    def _on_draw(self, _da, cr, w, h) -> None:
        if w < 10 or h < 10:
            return

        rx = self._stats.rx_rates
        tx = self._stats.tx_rates
        n = len(rx)
        if n < 2:
            self._draw_no_data(cr, w, h)
            return

        mx = self._stats.max_rate()
        if mx < 0.001:
            mx = 1.0

        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        margin = 4
        plot_w = w - 2 * margin
        plot_h = h - 2 * margin

        def scale_y(val: float) -> float:
            return margin + plot_h - (val / mx) * plot_h

        self._draw_line(cr, rx, margin, plot_w, scale_y,
                        Gdk.RGBA(0.3, 0.6, 1.0, 0.9))
        self._draw_line(cr, tx, margin, plot_w, scale_y,
                        Gdk.RGBA(1.0, 0.65, 0.1, 0.9))

        def fmt_rate(val: float) -> str:
            if val >= 1_073_741_824:
                return f"{val / 1_073_741_824:.1f} GB/s"
            if val >= 1_048_576:
                return f"{val / 1_048_576:.1f} MB/s"
            if val >= 1024:
                return f"{val / 1024:.0f} KB/s"
            return f"{val:.0f} B/s"

        cr.set_font_size(8)
        cr.set_source_rgba(0.5, 0.5, 0.5, 0.6)
        for pct, _label in [(0, "0"), (50, f"{mx/2:.0f}"), (100, f"{mx:.0f}")]:
            y = margin + plot_h - (pct / 100) * plot_h
            cr.move_to(margin + 2, y - 2)
            cr.show_text(fmt_rate(mx * pct / 100))

        cur_r = rx[-1]
        cur_tx = tx[-1]
        cr.set_font_size(9)
        cr.set_source_rgba(0.3, 0.6, 1.0, 0.9)
        cr.move_to(w - 120, 12)
        cr.show_text(f"RX: {fmt_rate(cur_r)}")
        cr.set_source_rgba(1.0, 0.65, 0.1, 0.9)
        cr.move_to(w - 120, 24)
        cr.show_text(f"TX: {fmt_rate(cur_tx)}")

    def _draw_no_data(self, cr, w, h) -> None:
        cr.set_source_rgba(0.5, 0.5, 0.5, 0.4)
        cr.set_font_size(10)
        cr.move_to(w / 2 - 30, h / 2)
        cr.show_text("Collecting\u2026")

    @staticmethod
    def _draw_line(cr, data, margin, plot_w, scale_y, color):
        n = len(data)
        if n < 2:
            return
        step = plot_w / (n - 1) if n > 1 else plot_w

        cr.set_source_rgba(color.red, color.green, color.blue, color.alpha)
        cr.set_line_width(1.5)
        cr.set_line_cap(1)
        cr.set_line_join(1)

        first = True
        for i in range(n):
            x = margin + i * step
            y = scale_y(data[i])
            if first:
                cr.move_to(x, y)
                first = False
            else:
                cr.line_to(x, y)
        cr.stroke()


class NetworkPage:
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
        self._wifi_iface: str = ""
        self._eth_iface: str = ""
        self._networks: list[dict] = []

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh network status")
        refresh_btn.connect("clicked", lambda _b: self._full_refresh())
        header.pack_start(refresh_btn)

        scan_btn = Gtk.Button(icon_name="list-add-symbolic")
        scan_btn.set_tooltip_text("Scan for WiFi networks")
        scan_btn.connect("clicked", lambda _b: self._show_wifi_scan())
        header.pack_start(scan_btn)

        self._load_data()

        # Network Configuration
        sg = Adw.PreferencesGroup(title="Network Configuration")
        self._build_status_section(sg)
        self._content_box.append(sg)

        # Saved WiFi Networks
        if self._wifi_iface:
            swg = Adw.PreferencesGroup(title="Saved WiFi Networks")
            self._build_saved_wifi(swg)
            self._content_box.append(swg)

        # Ethernet
        if self._eth_iface:
            eg = Adw.PreferencesGroup(title="Ethernet")
            self._build_eth_section(eg)
            self._content_box.append(eg)

        # VLANs
        vg = Adw.PreferencesGroup(title="VLANs")
        self._vlan_group = vg
        self._build_vlan_section(vg)
        self._content_box.append(vg)

        self._tick_source = GLib.timeout_add(5000, self._tick)

        GLib.idle_add(self._add_sidebar_switch)

        return toolbar_view

    def _load_data(self) -> None:
        raw = _run(["--network-status"])
        self._status = _parse_kv(raw)

        self._wifi_iface = self._status.get("wifi_iface", "none")
        if self._wifi_iface == "none":
            self._wifi_iface = ""
        self._eth_iface = self._status.get("eth_iface", "none")
        if self._eth_iface == "none":
            self._eth_iface = ""

    def _full_refresh(self) -> None:
        self._load_data()
        if hasattr(self, "_vlan_group") and hasattr(self, "_vlan_items"):
            for item in self._vlan_items:
                try:
                    self._vlan_group.remove(item)
                except Exception:
                    pass
            self._vlan_items.clear()
            self._build_vlan_section(self._vlan_group)
        if hasattr(self, "_saved_networks"):
            self._saved_networks = self._load_saved_wifi()
            self._saved_selected.clear()
            if hasattr(self, "_saved_search"):
                self._saved_search.set_text("")

    def _build_status_section(self, group: Adw.PreferencesGroup) -> None:
        conn_type = self._status.get("connection_type", "none")
        iface = self._status.get("conn_interface", "none")
        ip = self._status.get("conn_ip", "none")
        gw = self._status.get("conn_gateway", "none")
        dns = self._status.get("conn_dns", "none")
        mac = self._status.get("conn_mac", "none")
        internet = self._status.get("internet", "offline")

        # Connection icon + type
        if conn_type == "wifi":
            icon_name = "network-wireless-symbolic"
            type_label = "WiFi"
        elif conn_type == "ethernet":
            icon_name = "network-wired-symbolic"
            type_label = "Ethernet"
        else:
            icon_name = "network-offline-symbolic"
            type_label = "None"

        ssid = self._status.get("wifi_ssid", "") if conn_type == "wifi" else ""
        iface_part = ssid if ssid else (iface if iface != "none" else "")
        subtitle = type_label
        if iface_part:
            subtitle += f" \u00b7 {iface_part}"

        conn_row = Adw.ActionRow(title="Connection", subtitle=subtitle)
        conn_row.add_prefix(Gtk.Image.new_from_icon_name(icon_name))

        inet_lbl = Gtk.Label(label="Online" if internet == "online" else "Offline")
        inet_lbl.add_css_class("success" if internet == "online" else "error")
        inet_lbl.set_valign(Gtk.Align.CENTER)
        conn_row.add_suffix(inet_lbl)
        self._inet_lbl = inet_lbl

        current_ssid = self._status.get("wifi_ssid", "none")
        if current_ssid and current_ssid != "none":
            disc_btn = Gtk.Button(label="Disconnect")
            disc_btn.set_valign(Gtk.Align.CENTER)
            disc_btn.connect("clicked", lambda _b: self._wifi_disconnect())
            conn_row.add_suffix(disc_btn)

        group.add(conn_row)

        net_info = []
        if ip and ip != "none":
            net_info.append(f"IP: {ip}")
        if gw and gw != "none":
            net_info.append(f"GW: {gw}")
        if dns and dns != "none":
            net_info.append(f"DNS: {dns}")
        if mac and mac != "none":
            net_info.append(f"MAC: {mac}")
        if net_info:
            info_row = Adw.ActionRow(title="Details", subtitle=" | ".join(net_info))
            if self._wifi_iface or self._eth_iface:
                config_btn = Gtk.Button(icon_name="document-edit-symbolic")
                config_btn.set_valign(Gtk.Align.CENTER)
                config_btn.set_tooltip_text("Configure IP / Gateway / DNS")
                config_btn.connect("clicked", lambda _b: self._show_config_dialog())
                info_row.add_suffix(config_btn)
            group.add(info_row)
            self._info_row = info_row

        # RX/TX traffic graph
        graph_iface = self._wifi_iface or self._eth_iface
        if graph_iface:
            graph = NetIOGraph(graph_iface)
            graph_row = Adw.ActionRow()
            graph_row.set_activatable(False)
            graph_row.set_child(graph)
            group.add(graph_row)
            self._net_graph = graph

        if self._wifi_iface:
            wifi_state = self._status.get("wifi_state", "down")
            sw = Adw.SwitchRow(
                title="WiFi Card",
                subtitle=f"Interface: {self._wifi_iface}",
            )
            sw.set_active(wifi_state == "UP")
            sw.connect("notify::active", self._on_wifi_toggle)
            group.add(sw)
            self._wifi_switch = sw

        if self._wifi_iface or self._eth_iface:
            dhcp_btn = Gtk.Button(label="Renew DHCP")
            dhcp_btn.add_css_class("suggested-action")
            dhcp_btn.set_valign(Gtk.Align.CENTER)
            dhcp_btn.connect("clicked", lambda _b: self._renew_dhcp())
            dhcp_row = Adw.ActionRow(
                title="Renew DHCP Lease",
                subtitle="Release and renew IP via DHCP",
            )
            dhcp_row.add_suffix(dhcp_btn)
            group.add(dhcp_row)

            dns_btn = Gtk.Button(label="Flush DNS")
            dns_btn.set_valign(Gtk.Align.CENTER)
            dns_btn.connect("clicked", lambda _b: self._flush_dns())
            dns_row = Adw.ActionRow(
                title="Flush DNS Cache",
                subtitle="Clear system DNS resolver cache",
            )
            dns_row.add_suffix(dns_btn)
            group.add(dns_row)

    def _build_eth_section(self, group: Adw.PreferencesGroup) -> None:
        raw = _run(["--ethernet-status", self._eth_iface])
        info = _parse_kv(raw)
        state = info.get("state", "down")
        conn = info.get("connection", "none")
        ip = info.get("ip", "none")
        gw = info.get("gateway", "none")
        dns = info.get("dns", "none")
        mac = info.get("mac", "none")

        state_lbl = Gtk.Label(label=state.upper())
        state_lbl.add_css_class("success" if state == "UP" else "dim-label")
        state_lbl.set_valign(Gtk.Align.CENTER)
        state_row = Adw.ActionRow(title="Status", subtitle=self._eth_iface)
        state_row.add_suffix(state_lbl)
        group.add(state_row)

        if conn and conn != "none":
            conn_row = Adw.ActionRow(title="Connection", subtitle=conn)
            group.add(conn_row)

        if ip and ip != "none":
            ip_row = Adw.ActionRow(title="IP Address", subtitle=ip)
            group.add(ip_row)

        if gw and gw != "none":
            gw_row = Adw.ActionRow(title="Gateway", subtitle=gw)
            group.add(gw_row)

        if dns and dns != "none":
            dns_row = Adw.ActionRow(title="DNS", subtitle=dns)
            group.add(dns_row)

        if mac and mac != "none":
            mac_row = Adw.ActionRow(title="MAC Address", subtitle=mac)
            group.add(mac_row)

    def _build_actions(self, _group: Adw.PreferencesGroup) -> None:
        pass

    def _on_wifi_toggle(self, sw: Adw.SwitchRow, _pspec) -> None:
        if self._setting_value:
            return
        iface = self._wifi_iface
        if sw.get_active():
            _run(["--wifi-on", iface])
            self._window.show_toast(f"WiFi turned on")
        else:
            _run(["--wifi-off", iface])
            self._window.show_toast(f"WiFi turned off")
        GLib.timeout_add(2000, self._full_refresh)

    def _wifi_disconnect(self) -> None:
        _run(["--wifi-disconnect", self._wifi_iface])
        self._window.show_toast("Disconnected from WiFi")
        self._full_refresh()

    def _load_saved_wifi(self) -> list[str]:
        raw = _run(["--wifi-saved"])
        return [l.strip() for l in raw.splitlines() if l.strip()]

    def _build_saved_wifi(self, group: Adw.PreferencesGroup) -> None:
        self._saved_networks = self._load_saved_wifi()
        self._saved_selected: set[str] = set()

        search_entry = Gtk.SearchEntry()
        search_entry.set_placeholder_text("Search saved networks\u2026")
        search_entry.set_hexpand(True)

        bulk_del_btn = Gtk.Button(label="Delete Selected")
        bulk_del_btn.add_css_class("destructive-action")
        bulk_del_btn.set_valign(Gtk.Align.CENTER)
        bulk_del_btn.set_visible(False)

        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        search_box.append(search_entry)
        search_box.append(bulk_del_btn)

        search_row = Adw.ActionRow(title="")
        search_row.set_activatable(False)
        search_row.set_child(search_box)
        group.add(search_row)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        listbox.add_css_class("boxed-list")

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(listbox)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(150)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

        self._saved_listbox = listbox
        self._saved_search = search_entry
        self._saved_bulk_btn = bulk_del_btn

        def rebuild():
            while child := listbox.get_first_child():
                listbox.remove(child)
            q = search_entry.get_text().lower().strip()
            for net in self._saved_networks:
                if q and q not in net.lower():
                    continue
                row = Adw.ActionRow(title=net)
                check = Gtk.CheckButton()
                check.set_valign(Gtk.Align.CENTER)
                if net in self._saved_selected:
                    check.set_active(True)
                def toggle(f=net, c=check):
                    if c.get_active():
                        self._saved_selected.add(f)
                    else:
                        self._saved_selected.discard(f)
                    n = len(self._saved_selected)
                    bulk_del_btn.set_visible(n > 0)
                    if n:
                        bulk_del_btn.set_label(f"Delete Selected ({n})")
                check.connect("toggled", lambda _c, f=net: toggle(f))
                row.add_prefix(check)

                current_ssid = self._status.get("wifi_ssid", "none")
                is_current = current_ssid == net
                if is_current:
                    connect_btn = Gtk.Button(icon_name="media-playback-stop-symbolic")
                    connect_btn.set_valign(Gtk.Align.CENTER)
                    connect_btn.set_tooltip_text("Disconnect")
                    connect_btn.connect("clicked", lambda _b: self._wifi_disconnect())
                else:
                    connect_btn = Gtk.Button(icon_name="media-playback-start-symbolic")
                    connect_btn.set_valign(Gtk.Align.CENTER)
                    connect_btn.set_tooltip_text("Connect")
                    connect_btn.connect("clicked", lambda _b, s=net: self._connect_wifi(s, "Open"))
                row.add_suffix(connect_btn)

                forget_btn = Gtk.Button(icon_name="user-trash-symbolic")
                forget_btn.set_valign(Gtk.Align.CENTER)
                forget_btn.set_tooltip_text("Forget this network")
                forget_btn.connect("clicked", lambda _b, n=net: self._forget_saved_wifi(n))
                row.add_suffix(forget_btn)
                listbox.append(row)

            if not self._saved_networks:
                empty_lbl = Gtk.Label(label="No saved WiFi networks")
                empty_lbl.set_margin_top(16)
                empty_lbl.set_margin_bottom(16)
                empty_lbl.set_halign(Gtk.Align.CENTER)
                empty_lbl.add_css_class("dim-label")
                listbox.append(empty_lbl)

        search_entry.connect("search-changed", lambda e: rebuild())
        bulk_del_btn.connect("clicked", lambda _b: self._bulk_forget_saved())
        rebuild()

    def _forget_saved_wifi(self, name: str) -> None:
        res = _run(["--wifi-forget", name])
        if "result=success" in res:
            self._window.show_toast(f"Forgot {name}")
            self._full_refresh()
        else:
            self._window.show_toast("Failed to forget network", timeout=5)

    def _bulk_forget_saved(self) -> None:
        if not self._saved_selected:
            return
        names = list(self._saved_selected)
        self._saved_selected.clear()
        for name in names:
            _run(["--wifi-forget", name])
        self._window.show_toast(f"Forgot {len(names)} network(s)")
        self._full_refresh()

    def _show_wifi_scan(self) -> None:
        iface = self._wifi_iface
        if not iface:
            return

        _run(["--wifi-on", iface])

        dialog = Adw.Dialog()
        dialog.set_title("Available WiFi Networks")
        dialog.set_content_width(550)
        dialog.set_content_height(500)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        refresh_btn = Gtk.Button(label="Refresh")
        header.pack_start(refresh_btn)
        toolbar.add_top_bar(header)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(550)
        clamp.set_tightening_threshold(450)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(8)
        box.set_margin_end(8)

        info_lbl = Gtk.Label(label="Scanning...")
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

        def populate():
            raw = _run(["--wifi-list", iface])
            while child := listbox.get_first_child():
                listbox.remove(child)
            count = 0
            if raw:
                for line in raw.splitlines():
                    parts = line.split("|")
                    if len(parts) >= 5 and parts[0] == "network":
                        ssid, signal, security, bssid = parts[1], parts[2], parts[3], parts[4]
                        if not ssid:
                            continue
                        count += 1
                        row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
                        row_box.set_margin_top(6)
                        row_box.set_margin_bottom(6)
                        row_box.set_margin_start(8)
                        row_box.set_margin_end(8)

                        icon_name = "network-wireless-signal-excellent-symbolic"
                        sig = int(signal) if signal.isdigit() else 0
                        if sig < 25:
                            icon_name = "network-wireless-signal-weak-symbolic"
                        elif sig < 50:
                            icon_name = "network-wireless-signal-ok-symbolic"
                        elif sig < 75:
                            icon_name = "network-wireless-signal-good-symbolic"

                        img = Gtk.Image.new_from_icon_name(icon_name)
                        img.set_pixel_size(24)
                        img.set_valign(Gtk.Align.CENTER)
                        row_box.append(img)

                        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
                        text_box.set_hexpand(True)
                        n_lbl = Gtk.Label(label=ssid)
                        n_lbl.set_halign(Gtk.Align.START)
                        n_lbl.set_ellipsize(Pango.EllipsizeMode.END)
                        text_box.append(n_lbl)
                        sub_lbl = Gtk.Label(label=f"{signal}%  {security}")
                        sub_lbl.set_halign(Gtk.Align.START)
                        sub_lbl.add_css_class("dim-label")
                        sub_lbl.add_css_class("caption")
                        text_box.append(sub_lbl)
                        row_box.append(text_box)

                        if security != "Open":
                            lock_img = Gtk.Image.new_from_icon_name("channel-secure-symbolic")
                            lock_img.set_valign(Gtk.Align.CENTER)
                            lock_img.set_opacity(0.6)
                            row_box.append(lock_img)

                        c_btn = Gtk.Button(label="Connect")
                        c_btn.add_css_class("suggested-action")
                        c_btn.set_valign(Gtk.Align.CENTER)
                        c_btn.connect("clicked", lambda _b, s=ssid, sec=security: (
                            dialog.close(),
                            self._connect_wifi(s, sec),
                        ))
                        row_box.append(c_btn)

                        row = Gtk.ListBoxRow()
                        row.set_child(row_box)
                        listbox.append(row)

            info_lbl.set_label(f"{count} networks found" if count else "No networks found")

        populate()
        refresh_btn.connect("clicked", lambda _b: populate())
        dialog.present(self._window)

    def _connect_wifi(self, ssid: str, security: str) -> None:
        if security == "Open":
            self._window.show_toast(f"Connecting to {ssid}...")
            def do_connect():
                res = _run(["--wifi-connect", ssid, "", self._wifi_iface])
                if "result=success" in res or "already_connected" in res:
                    GLib.idle_add(lambda: self._window.show_toast(f"Connected to {ssid}"))
                else:
                    GLib.idle_add(lambda: self._window.show_toast(f"Failed to connect", timeout=5))
                GLib.idle_add(self._full_refresh)
            threading.Thread(target=do_connect, daemon=True).start()
        else:
            dialog = Adw.AlertDialog(
                heading=f"Connect to {ssid}",
                body="Enter the WiFi password:",
            )
            entry = Gtk.Entry()
            entry.set_placeholder_text("Password")
            entry.set_input_purpose(Gtk.InputPurpose.PASSWORD)
            entry.set_visibility(False)
            entry.set_valign(Gtk.Align.CENTER)
            entry.set_margin_top(8)

            extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            extra.append(entry)
            dialog.set_extra_child(extra)

            dialog.add_response("cancel", "Cancel")
            dialog.add_response("connect", "Connect")
            dialog.set_response_appearance("connect", Adw.ResponseAppearance.SUGGESTED)
            dialog.set_default_response("cancel")
            dialog.set_close_response("cancel")

            def on_resp(_d, resp: str):
                if resp == "connect":
                    pw = entry.get_text()
                    self._window.show_toast(f"Connecting to {ssid}...")
                    def do_connect():
                        res = _run(["--wifi-connect", ssid, pw, self._wifi_iface])
                        if "result=success" in res or "already_connected" in res:
                            GLib.idle_add(lambda: self._window.show_toast(f"Connected to {ssid}"))
                        else:
                            GLib.idle_add(lambda: self._window.show_toast(f"Failed to connect", timeout=5))
                        GLib.idle_add(self._full_refresh)
                    threading.Thread(target=do_connect, daemon=True).start()

            dialog.connect("response", on_resp)
            dialog.present(self._window)

    def _show_config_dialog(self) -> None:
        iface = self._wifi_iface or self._eth_iface
        if not iface:
            return

        # Refresh status for latest values
        _run(["--network-status"])
        self._load_data()

        cur_ip = self._status.get("conn_ip", "none")
        cur_gw = self._status.get("conn_gateway", "none")
        cur_dns = self._status.get("conn_dns", "none")

        ip_entry = Gtk.Entry()
        ip_entry.set_placeholder_text("IP/CIDR (e.g. 192.168.1.10/24)")
        if cur_ip != "none":
            ip_entry.set_text(cur_ip)
        ip_entry.set_margin_bottom(4)

        gw_entry = Gtk.Entry()
        gw_entry.set_placeholder_text("Gateway (e.g. 192.168.1.1)")
        if cur_gw != "none":
            gw_entry.set_text(cur_gw)
        gw_entry.set_margin_bottom(4)

        dns1_entry = Gtk.Entry()
        dns1_entry.set_placeholder_text("DNS 1 (e.g. 1.1.1.1)")
        if cur_dns != "none":
            dns1_entry.set_text(cur_dns)
        dns1_entry.set_margin_bottom(4)

        dns2_entry = Gtk.Entry()
        dns2_entry.set_placeholder_text("DNS 2 (optional, e.g. 8.8.8.8)")

        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        extra.append(ip_entry)
        extra.append(gw_entry)
        extra.append(dns1_entry)
        extra.append(dns2_entry)

        dialog = Adw.AlertDialog(
            heading=f"Configure {iface}",
            body="Edit values and press Apply to save:",
        )
        dialog.set_extra_child(extra)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("reset", "Reset to DHCP")
        dialog.set_response_appearance("reset", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.add_response("apply", "Apply")
        dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_resp(_d, resp: str):
            if resp == "reset":
                self._window.show_toast(f"Resetting {iface} to DHCP...")
                def do_reset():
                    r = _run(["--dhcp", iface], timeout=30)
                    if "result=success" in r:
                        GLib.idle_add(lambda: self._window.show_toast(f"DHCP enabled on {iface}"))
                    else:
                        GLib.idle_add(lambda: self._window.show_toast(f"DHCP reset failed", timeout=5))
                    GLib.idle_add(self._full_refresh)
                threading.Thread(target=do_reset, daemon=True).start()
            elif resp == "apply":
                ip_val = ip_entry.get_text().strip()
                gw_val = gw_entry.get_text().strip()
                dns1_val = dns1_entry.get_text().strip()
                dns2_val = dns2_entry.get_text().strip()

                errors = []
                if ip_val and not re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$", ip_val):
                    errors.append("IP must be in CIDR format (e.g. 192.168.1.10/24)")
                if gw_val and not re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", gw_val):
                    errors.append("Gateway must be a valid IP (e.g. 192.168.1.1)")
                if dns1_val and not re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", dns1_val):
                    errors.append("DNS1 must be a valid IP (e.g. 1.1.1.1)")
                if dns2_val and not re.match(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$", dns2_val):
                    errors.append("DNS2 must be a valid IP (e.g. 8.8.8.8)")

                if errors:
                    self._window.show_toast(" | ".join(errors), timeout=8)
                    return

                def do_apply():
                    if ip_val:
                        r = _run(["--manual-ip", iface, ip_val, gw_val], timeout=15)
                    if dns1_val:
                        r2 = _run(["--set-dns", iface, dns1_val, dns2_val], timeout=15)
                    GLib.idle_add(lambda: self._window.show_toast("Configuration applied"))
                    GLib.idle_add(self._full_refresh)

                if ip_val or dns1_val:
                    self._window.show_toast(f"Applying configuration on {iface}...")
                    threading.Thread(target=do_apply, daemon=True).start()

        dialog.connect("response", on_resp)
        dialog.present(self._window)

    def _renew_dhcp(self) -> None:
        iface = self._wifi_iface or self._eth_iface
        if not iface:
            return
        self._window.show_toast(f"Renewing DHCP on {iface}...")
        def do_renew():
            _run(["--dhcp", iface], timeout=30)
            GLib.idle_add(lambda: self._window.show_toast(f"DHCP renewed"))
            GLib.idle_add(self._full_refresh)
        threading.Thread(target=do_renew, daemon=True).start()

    def _flush_dns(self) -> None:
        _run(["--dns-flush"])
        self._window.show_toast("DNS cache flushed")

    def _load_vlans(self) -> list[dict]:
        vlans = []
        raw = _run(["--vlan-list"])
        if raw and "result=none" not in raw:
            for line in raw.splitlines():
                p = line.split("|")
                if len(p) >= 4 and p[0] == "vlan":
                    vlans.append({"name": p[1], "id": p[2], "parent": p[3]})
        return vlans

    def _build_vlan_section(self, group: Adw.PreferencesGroup) -> None:
        if not hasattr(self, "_vlan_items"):
            self._vlan_items = []

        create_btn = Gtk.Button(label="Create VLAN")
        create_btn.add_css_class("suggested-action")
        create_btn.set_valign(Gtk.Align.CENTER)
        create_btn.connect("clicked", lambda _b: self._show_vlan_dialog())
        create_row = Adw.ActionRow(title="New VLAN", subtitle="Create a virtual LAN on an interface")
        create_row.add_suffix(create_btn)
        group.add(create_row)
        self._vlan_items.append(create_row)

        vlans = self._load_vlans()
        for vlan in vlans:
            row = Adw.ActionRow(title=vlan["name"],
                                subtitle=f"ID: {vlan['id']}  |  Parent: {vlan['parent']}")
            del_btn = Gtk.Button(icon_name="user-trash-symbolic")
            del_btn.set_valign(Gtk.Align.CENTER)
            del_btn.set_tooltip_text("Delete VLAN")
            del_btn.connect("clicked", lambda _b, n=vlan["name"]: self._delete_vlan(n))
            row.add_suffix(del_btn)
            group.add(row)
            self._vlan_items.append(row)

    def _show_vlan_dialog(self) -> None:
        parent_entry = Gtk.Entry()
        parent_entry.set_placeholder_text("e.g. eth0, enp3s0")
        parent_entry.set_margin_bottom(4)

        id_entry = Gtk.Entry()
        id_entry.set_placeholder_text("VLAN ID (2-4094)")
        id_entry.set_margin_bottom(4)

        name_entry = Gtk.Entry()
        name_entry.set_placeholder_text(f"Name (optional, e.g. eth0.100)")

        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        extra.append(parent_entry)
        extra.append(id_entry)
        extra.append(name_entry)

        dialog = Adw.AlertDialog(
            heading="Create VLAN",
            body="Parent interface, VLAN ID, and optional name:",
        )
        dialog.set_extra_child(extra)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("create", "Create")
        dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_resp(_d, resp: str):
            if resp == "create":
                parent = parent_entry.get_text().strip()
                vid = id_entry.get_text().strip()
                name = name_entry.get_text().strip()
                if not parent or not vid:
                    self._window.show_toast("Parent and ID required", timeout=5)
                    return
                if not vid.isdigit() or not (2 <= int(vid) <= 4094):
                    self._window.show_toast("VLAN ID must be 2-4094", timeout=5)
                    return
                name = name if name else f"{parent}.{vid}"
                res = _run(["--vlan-create", parent, vid, name])
                if "result=success" in res:
                    self._window.show_toast(f"VLAN {name} created")
                    self._full_refresh()
                else:
                    reason = "parent interface may not support VLANs"
                    if "create_failed" in res:
                        reason = f"failed to create on {parent} (WiFi may not support VLANs)"
                    self._window.show_toast(reason, timeout=5)

        dialog.connect("response", on_resp)
        dialog.present(self._window)

    def _delete_vlan(self, name: str) -> None:
        res = _run(["--vlan-delete", name])
        if "result=success" in res:
            self._window.show_toast(f"VLAN {name} deleted")
            self._full_refresh()
        else:
            self._window.show_toast("Failed to delete VLAN", timeout=5)

    def _add_sidebar_switch(self) -> bool:
        sidebar = getattr(self._window, "_sidebar", None)
        if sidebar:
            row = sidebar._rows_by_id.get("network")
            if row is not None:
                if hasattr(row, "_net_power_switch"):
                    return False
                power_sw = Gtk.Switch()
                power_sw.set_valign(Gtk.Align.CENTER)
                power_sw.set_margin_end(6)
                on = self._status.get("wifi_state", "down") == "UP" if self._wifi_iface else False
                power_sw.set_active(on)
                power_sw.connect("notify::active", self._on_sidebar_wifi_toggle)
                row.add_suffix(power_sw)
                row._net_power_switch = power_sw
                self._sidebar_power_switch = power_sw
        return False

    def _on_sidebar_wifi_toggle(self, sw: Gtk.Switch, _pspec) -> None:
        if self._setting_value or not self._wifi_iface:
            return
        if sw.get_active():
            _run(["--wifi-on", self._wifi_iface])
        else:
            _run(["--wifi-off", self._wifi_iface])

    def _tick(self) -> bool:
        threading.Thread(target=self._tick_worker, daemon=True).start()
        return True

    def _tick_worker(self) -> None:
        try:
            raw = _run(["--network-status"])
            GLib.idle_add(self._apply_status, raw)
        except Exception:
            pass

    def _apply_status(self, raw: str) -> None:
        self._status = _parse_kv(raw)

        prev_wifi = self._wifi_iface
        self._wifi_iface = self._status.get("wifi_iface", "none")
        if self._wifi_iface == "none":
            self._wifi_iface = ""
        self._eth_iface = self._status.get("eth_iface", "none")
        if self._eth_iface == "none":
            self._eth_iface = ""

        internet = self._status.get("internet", "offline")
        if hasattr(self, "_inet_lbl"):
            self._inet_lbl.set_label("Online" if internet == "online" else "Offline")
            self._inet_lbl.remove_css_class("success")
            self._inet_lbl.remove_css_class("error")
            self._inet_lbl.add_css_class("success" if internet == "online" else "error")

        # Update Details row with latest IP/GW/DNS
        if hasattr(self, "_info_row"):
            ip = self._status.get("conn_ip", "none")
            gw = self._status.get("conn_gateway", "none")
            dns = self._status.get("conn_dns", "none")
            parts = []
            if ip != "none":
                parts.append(f"IP: {ip}")
            if gw != "none":
                parts.append(f"GW: {gw}")
            if dns != "none":
                parts.append(f"DNS: {dns}")
            self._info_row.set_subtitle(" | ".join(parts))

        wifi_state = self._status.get("wifi_state", "down")
        if hasattr(self, "_wifi_switch"):
            self._setting_value = True
            self._wifi_switch.set_active(wifi_state == "UP")
            self._setting_value = False

        if hasattr(self, "_sidebar_power_switch") and self._wifi_iface:
            self._setting_value = True
            self._sidebar_power_switch.set_active(wifi_state == "UP")
            self._setting_value = False

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
                category="Network",
                title="Network Configuration",
                subtitle="Network settings changed",
                navigate_to="network",
                icon=_NET_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "net:status", "label": "Network Status",
             "description": "Connection type, IP, gateway, DNS, internet",
             "_group_id": "network", "_group_label": "Network", "_section_label": "Status"},
            {"key": "net:wifi", "label": "WiFi",
             "description": "WiFi on/off, connect, disconnect, scan",
             "_group_id": "network", "_group_label": "Network", "_section_label": "WiFi"},
            {"key": "net:ethernet", "label": "Ethernet",
             "description": "Wired connection status",
             "_group_id": "network", "_group_label": "Network", "_section_label": "Ethernet"},
            {"key": "net:actions", "label": "Actions",
             "description": "Renew DHCP, flush DNS",
             "_group_id": "network", "_group_label": "Network", "_section_label": "Actions"},
        ]

    def destroy(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None
        if hasattr(self, "_net_graph"):
            self._net_graph.stop()
