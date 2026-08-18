import os
import subprocess
import threading
import time
from collections.abc import Iterable

from gi.repository import Adw, GLib, Gtk, cairo

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

_FIREWALL_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "firewall_core.sh")
_SSH_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "ssh_core.sh")


def _run(script: str, args: list[str]) -> str:
    try:
        r = subprocess.run(
            ["sudo", "-n", script, *args],
            capture_output=True, text=True, timeout=15,
            stdin=subprocess.DEVNULL,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except Exception:
        pass
    try:
        r = subprocess.run(
            ["bash", script, *args],
            capture_output=True, text=True, timeout=15,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _can_sudo() -> bool:
    if os.geteuid() == 0:
        return True
    try:
        r = subprocess.run(
            ["id", "-nG"], capture_output=True, text=True, timeout=5,
            stdin=subprocess.DEVNULL,
        )
        groups = r.stdout.split()
        return bool({"wheel", "sudo"} & set(groups))
    except Exception:
        return False


class FirewallTrafficStats:
    """Reads RX/TX bytes, in/out connections, and blocked packets into rolling buffers."""

    def __init__(self):
        self.rx_mbps: list[float] = []
        self.tx_mbps: list[float] = []
        self.conn_in: list[float] = []
        self.conn_out: list[float] = []
        self.blocked: list[float] = []
        self._last_rx = 0
        self._last_tx = 0
        self._last_blocked = 0
        self._last_time = 0.0
        self._max_samples = 60

    def _read_counters(self):
        rx = tx = 0
        try:
            with open("/proc/net/dev") as f:
                for line in f:
                    if ":" not in line:
                        continue
                    iface, rest = line.split(":", 1)
                    if iface.strip() == "lo":
                        continue
                    parts = rest.split()
                    if len(parts) >= 9:
                        rx += int(parts[0])
                        tx += int(parts[8])
        except (OSError, ValueError, IndexError):
            pass
        return rx, tx

    def _read_blocked(self) -> int:
        try:
            data = _run(_FIREWALL_CORE, ["--status"])
            for line in data.splitlines():
                if line.startswith("blocked_packets="):
                    return int(line.split("=", 1)[1] or 0)
        except (ValueError, OSError):
            pass
        return 0

    def _read_conns(self):
        inc = out = 0
        try:
            r = subprocess.run(
                ["ss", "-tn", "state", "established"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            for line in r.stdout.splitlines():
                fields = line.split()
                if len(fields) < 4:
                    continue
                local = fields[2]
                port = local.rsplit(":", 1)[-1]
                if not port.isdigit():
                    continue
                if int(port) < 32768:
                    inc += 1
                else:
                    out += 1
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
        return inc, out

    def sample(self) -> None:
        rx, tx = self._read_counters()
        inc, out = self._read_conns()
        blocked = self._read_blocked()
        now = time.monotonic()
        if self._last_time > 0:
            dt = now - self._last_time
            if dt > 0:
                self.rx_mbps.append((rx - self._last_rx) * 8 / (dt * 1e6))
                self.tx_mbps.append((tx - self._last_tx) * 8 / (dt * 1e6))
                self.conn_in.append(float(inc))
                self.conn_out.append(float(out))
                self.blocked.append(float(blocked - self._last_blocked))
                for buf in (self.rx_mbps, self.tx_mbps, self.conn_in, self.conn_out, self.blocked):
                    if len(buf) > self._max_samples:
                        buf.pop(0)
        self._last_rx = rx
        self._last_tx = tx
        self._last_blocked = blocked
        self._last_time = now

    def max_rate(self) -> float:
        all_vals = self.rx_mbps + self.tx_mbps
        return max(all_vals) if all_vals else 1.0


class FirewallTrafficGraph(Gtk.DrawingArea):
    """Live RX/TX throughput + in/out connection counts on a single sparkline."""

    def __init__(self) -> None:
        super().__init__()
        self.set_hexpand(True)
        self.set_size_request(-1, 170)
        self.set_valign(Gtk.Align.FILL)

        self._stats = FirewallTrafficStats()
        self.set_draw_func(self._on_draw)
        self.connect("destroy", self._on_destroy)

        self._timer = 0

    def start(self) -> None:
        if self._timer == 0:
            self._stats.sample()
            self._timer = GLib.timeout_add(1000, self._tick)

    def stop(self) -> None:
        if self._timer != 0:
            GLib.source_remove(self._timer)
            self._timer = 0

    def _tick(self) -> bool:
        self._stats.sample()
        self.queue_draw()
        return True

    def _on_destroy(self, *_args) -> None:
        self.stop()

    def _on_draw(self, _da, cr, w, h) -> None:
        if w < 10 or h < 10:
            return
        st = self._stats
        if len(st.rx_mbps) < 2:
            cr.set_operator(cairo.Operator.CLEAR)
            cr.paint()
            cr.set_operator(cairo.Operator.OVER)
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.4)
            cr.set_font_size(10)
            cr.move_to(w / 2 - 40, h / 2)
            cr.show_text("Collecting traffic\u2026")
            return

        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        rx_c = (0.3, 0.6, 1.0, 0.95)
        tx_c = (1.0, 0.65, 0.1, 0.95)
        in_c = (0.2, 1.0, 0.5, 0.95)
        out_c = (1.0, 0.33, 0.7, 0.95)
        blk_c = (1.0, 0.2, 0.2, 0.95)

        lines = [
            (st.rx_mbps, rx_c, "RX"),
            (st.tx_mbps, tx_c, "TX"),
            (st.blocked, blk_c, "BLK"),
            (st.conn_in, in_c, "In"),
            (st.conn_out, out_c, "Out"),
        ]

        margin_t, margin_b = 8, 16
        margin_l, margin_r = 8, 110
        plot_w = w - margin_l - margin_r
        plot_h = h - margin_t - margin_b
        if plot_w <= 0 or plot_h <= 0:
            return

        for data, _color, _label in lines:
            if not data:
                continue
            mx = max(data)
            if mx < 0.001:
                continue
            n = len(data)
            if n < 2:
                continue
            step = plot_w / (n - 1)
            cr.set_source_rgba(*_color)
            cr.set_line_width(1.3)
            cr.set_line_cap(1)
            cr.set_line_join(1)
            cr.move_to(margin_l, margin_t + plot_h - (data[0] / mx) * plot_h)
            for i in range(1, n):
                cr.line_to(margin_l + i * step, margin_t + plot_h - (data[i] / mx) * plot_h)
            cr.stroke()

        cr.set_font_size(9)
        y_pos = margin_t + 4
        rx_cur = st.rx_mbps[-1] if st.rx_mbps else 0
        tx_cur = st.tx_mbps[-1] if st.tx_mbps else 0
        in_cur = int(st.conn_in[-1]) if st.conn_in else 0
        out_cur = int(st.conn_out[-1]) if st.conn_out else 0
        blk_cur = int(st.blocked[-1]) if st.blocked else 0
        for color, label, text in [
            (rx_c, "RX", f"{rx_cur:.2f} Mb/s"),
            (tx_c, "TX", f"{tx_cur:.2f} Mb/s"),
            (blk_c, "BLK", f"{blk_cur} pkts"),
            (in_c, "IN", f"{in_cur} conns"),
            (out_c, "OUT", f"{out_cur} conns"),
        ]:
            cr.set_source_rgba(*color)
            cr.move_to(w - margin_r + 4, y_pos)
            cr.show_text(f"{label}: {text}")
            y_pos += 16


class SecurityPage:
    def __init__(self, window):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._view_stack: Adw.ViewStack | None = None
        self._can_sudo = _can_sudo()
        self._applying = False
        self._firewall_sw: Gtk.Switch | None = None
        self._policy_dd: Gtk.DropDown | None = None
        self._boot_sw: Gtk.Switch | None = None
        self._ping_sw: Gtk.Switch | None = None
        self._outbound_dd: Gtk.DropDown | None = None
        self._fw_group: Adw.PreferencesGroup | None = None
        self._fw_state: dict = {}
        self._fw_rows: list = []
        self._stat_rows: list = []
        self._blocked_rows: list = []
        self._conn_list: Gtk.ListBox | None = None
        self._conn_search: Gtk.SearchEntry | None = None
        self._conn_items: list = []
        self._conn_timer: int = 0
        self._traffic_graph: FirewallTrafficGraph | None = None
        self._stats_group: Adw.PreferencesGroup | None = None
        self._blocked_group: Adw.PreferencesGroup | None = None
        self._conn_group: Adw.PreferencesGroup | None = None
        self._ssh_group: Adw.PreferencesGroup | None = None
        self._ssh_state: dict = {}
        self._ssh_daemon_sw: Gtk.Switch | None = None
        self._ssh_port: Gtk.SpinButton | None = None
        self._ssh_pass_sw: Gtk.Switch | None = None
        self._ssh_pubkey_sw: Gtk.Switch | None = None
        self._ssh_root_dd: Gtk.DropDown | None = None
        self._ssh_empty_sw: Gtk.Switch | None = None
        self._ssh_x11_sw: Gtk.Switch | None = None
        self._ssh_tcp_sw: Gtk.Switch | None = None
        self._ssh_tries: Gtk.SpinButton | None = None
        self._ssh_idle: Gtk.SpinButton | None = None
        self._sessions_group: Adw.PreferencesGroup | None = None
        self._ssh_advanced_group: Adw.PreferencesGroup | None = None
        self._session_list: Gtk.ListBox | None = None
        self._session_search: Gtk.SearchEntry | None = None
        self._session_items: list = []
        self._key_group: Adw.PreferencesGroup | None = None
        self._key_rows: list = []
        self._known_group: Adw.PreferencesGroup | None = None
        self._known_list: Gtk.ListBox | None = None
        self._known_search: Gtk.SearchEntry | None = None
        self._known_items: list = []
        self._faillock_group: Adw.PreferencesGroup | None = None
        self._faillock_state: dict = {}
        self._faillock_deny: Gtk.SpinButton | None = None
        self._faillock_unlock: Gtk.SpinButton | None = None
        self._faillock_root_sw: Gtk.Switch | None = None
        self._faillock_users_group: Adw.PreferencesGroup | None = None
        self._faillock_user_rows: list = []
        self._dirty = False
        self._on_dirty_changed = None

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh security status")
        refresh_btn.connect("clicked", lambda _b: self._reload_all())
        header.pack_start(refresh_btn)

        drops_btn = Gtk.Button(icon_name="view-list-symbolic")
        drops_btn.set_tooltip_text("Recent dropped packets")
        drops_btn.connect("clicked", lambda _b: self._show_drops())
        header.pack_start(drops_btn)

        import_btn = Gtk.Button(icon_name="document-open-symbolic")
        import_btn.set_tooltip_text("Import firewall ruleset")
        import_btn.connect("clicked", lambda _b: self._import_ruleset())
        header.pack_start(import_btn)

        export_btn = Gtk.Button(icon_name="document-save-symbolic")
        export_btn.set_tooltip_text("Export firewall ruleset")
        export_btn.connect("clicked", lambda _b: self._export_ruleset())
        header.pack_start(export_btn)

        view_stack = Adw.ViewStack()
        view_stack.set_vexpand(True)

        self._fw_group = Adw.PreferencesGroup(title="Firewall (nftables)")
        self._ssh_group = Adw.PreferencesGroup(title="SSH")
        self._ssh_advanced_group = Adw.PreferencesGroup(title="Advanced Settings")
        self._sessions_group = Adw.PreferencesGroup(title="Active Sessions")
        self._key_group = Adw.PreferencesGroup(title="Key Management")
        self._known_group = Adw.PreferencesGroup(title="Known Hosts")
        self._faillock_group = Adw.PreferencesGroup(title="Faillock")

        fw_box = self._tab_box()
        fw_box.append(self._fw_group)
        self._fw_box = fw_box
        fw_scrolled = self._tab_scrolled(fw_box)
        view_stack.add_titled_with_icon(fw_scrolled, "firewall", "Firewall", "security-high-symbolic")

        ssh_box = self._tab_box()
        ssh_box.append(self._ssh_group)
        ssh_box.append(self._ssh_advanced_group)
        ssh_box.append(self._sessions_group)
        ssh_box.append(self._key_group)
        ssh_box.append(self._known_group)
        self._ssh_box = ssh_box
        ssh_scrolled = self._tab_scrolled(ssh_box)
        view_stack.add_titled_with_icon(ssh_scrolled, "ssh", "SSH", "network-server-symbolic")

        fl_box = self._tab_box()
        fl_box.append(self._faillock_group)
        self._fl_box = fl_box
        fl_scrolled = self._tab_scrolled(fl_box)
        view_stack.add_titled_with_icon(fl_scrolled, "faillock", "Faillock", "system-lock-screen-symbolic")

        switcher = Adw.ViewSwitcher()
        switcher.set_stack(view_stack)
        switcher.set_policy(Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)

        self._content_box.append(view_stack)
        self._view_stack = view_stack
        view_stack.connect("notify::visible-child", self._on_tab_changed)

        self._build_firewall_tab()
        self._build_ssh_tab()
        self._build_faillock_tab()

        self._reload_all()
        self._on_tab_changed(view_stack, None)
        return toolbar_view

    def _on_tab_changed(self, stack, _pspec) -> None:
        visible = stack.get_visible_child_name()
        if visible == "firewall":
            if self._traffic_graph is not None:
                self._traffic_graph.start()
            if self._conn_timer == 0:
                self._reload_connections()
                self._conn_timer = GLib.timeout_add(5000, self._refresh_connections_tick)
        else:
            if self._traffic_graph is not None:
                self._traffic_graph.stop()
            if self._conn_timer != 0:
                GLib.source_remove(self._conn_timer)
                self._conn_timer = 0

    def _refresh_connections_tick(self) -> bool:
        self._reload_connections()
        return True

    @staticmethod
    def _tab_box() -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        return box

    @staticmethod
    def _tab_scrolled(box: Gtk.Box) -> Gtk.ScrolledWindow:
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(box)
        scrolled.set_vexpand(True)
        return scrolled

    _SERVICES = [
        ("SSH", "22", "tcp"),
        ("HTTP", "80", "tcp"),
        ("HTTPS", "443", "tcp"),
        ("DNS", "53", "udp"),
        ("SMB", "445", "tcp"),
        ("RDP", "3389", "tcp"),
        ("VNC", "5900", "tcp"),
    ]

    _SERVICE_PORTS = {name: (port, proto) for name, port, proto in _SERVICES}

    def _build_firewall_tab(self) -> None:
        group = self._fw_group
        status_row = Adw.ActionRow(title="Firewall Status", subtitle="Checking\u2026")
        status_row.add_prefix(Gtk.Image.new_from_icon_name("security-high-symbolic"))
        self._fw_status_row = status_row
        group.add(status_row)

        sw_row = Adw.ActionRow(title="Enable Firewall")
        sw_row.set_subtitle("Enable and start the nftables firewall")
        sw = Gtk.Switch()
        sw.set_valign(Gtk.Align.CENTER)
        sw.connect("state-set", self._on_firewall_toggle)
        sw_row.add_suffix(sw)
        self._firewall_sw = sw
        group.add(sw_row)

        boot_row = Adw.ActionRow(title="Start at Boot")
        boot_row.set_subtitle("Enable the nftables service at system start")
        boot_sw = Gtk.Switch()
        boot_sw.set_valign(Gtk.Align.CENTER)
        boot_sw.connect("state-set", self._on_boot_toggle)
        boot_row.add_suffix(boot_sw)
        self._boot_sw = boot_sw
        group.add(boot_row)

        policy_row = Adw.ActionRow(title="Default Inbound Policy")
        policy_row.set_subtitle("Drop blocks all unsolicited inbound traffic")
        model = Gtk.StringList.new(["Drop", "Accept"])
        dd = Gtk.DropDown(model=model)
        dd.set_valign(Gtk.Align.CENTER)
        dd.connect("notify::selected", self._on_policy_change)
        policy_row.add_suffix(dd)
        self._policy_dd = dd
        group.add(policy_row)

        out_row = Adw.ActionRow(title="Default Outbound Policy")
        out_row.set_subtitle("Drop blocks all unsolicited outbound traffic")
        out_model = Gtk.StringList.new(["Accept", "Drop"])
        out_dd = Gtk.DropDown(model=out_model)
        out_dd.set_valign(Gtk.Align.CENTER)
        out_dd.connect("notify::selected", self._on_outbound_change)
        out_row.add_suffix(out_dd)
        self._outbound_dd = out_dd
        group.add(out_row)

        ping_row = Adw.ActionRow(title="Allow Ping")
        ping_row.set_subtitle("Respond to ICMP echo-request (ping)")
        ping_sw = Gtk.Switch()
        ping_sw.set_valign(Gtk.Align.CENTER)
        ping_sw.connect("state-set", self._on_ping_toggle)
        ping_row.add_suffix(ping_sw)
        self._ping_sw = ping_sw
        group.add(ping_row)

        stats_group = Adw.PreferencesGroup(title="Traffic Statistics")
        self._stats_group = stats_group
        if self._fw_box is not None:
            self._fw_box.append(stats_group)
        self._traffic_graph = FirewallTrafficGraph()
        graph_row = Adw.ActionRow(title="")
        graph_row.set_activatable(False)
        graph_row.set_child(self._traffic_graph)
        stats_group.add(graph_row)

        ports_group = Adw.PreferencesGroup(title="Allowed Ports")
        self._ports_group = ports_group
        if self._fw_box is not None:
            self._fw_box.append(ports_group)
        self._fw_add_row = self._build_add_port_row(ports_group)

        blocked_group = Adw.PreferencesGroup(title="Blocked Addresses")
        self._blocked_group = blocked_group
        if self._fw_box is not None:
            self._fw_box.append(blocked_group)
        self._build_block_ip_row(blocked_group)

        conn_group = Adw.PreferencesGroup(title="Active Connections")
        self._conn_group = conn_group
        if self._fw_box is not None:
            self._fw_box.append(conn_group)
        self._build_connections_list(conn_group)

    def _build_connections_list(self, group: Adw.PreferencesGroup) -> None:
        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search connections\u2026")
        search.set_hexpand(True)
        search.connect("search-changed", lambda _e: self._rebuild_connections())
        self._conn_search = search
        row = Adw.ActionRow(title="")
        row.set_activatable(False)
        row.set_child(search)
        group.add(row)

        self._conn_list = Gtk.ListBox()
        self._conn_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(self._conn_list)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(210)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

    def _build_add_port_row(self, group: Adw.PreferencesGroup) -> Adw.ActionRow:
        row = Adw.ActionRow(title="Open Port")
        row.set_subtitle("Allow inbound connections on a port")
        svc_model = Gtk.StringList.new(["Custom", "SSH", "HTTP", "HTTPS", "DNS", "SMB", "RDP", "VNC"])
        svc_dd = Gtk.DropDown(model=svc_model)
        svc_dd.set_valign(Gtk.Align.CENTER)
        svc_dd.connect("notify::selected", lambda _d, _pspec: self._on_service_preset(entry, proto_dd, svc_dd))
        row.add_suffix(svc_dd)
        entry = Gtk.Entry()
        entry.set_placeholder_text("Port")
        entry.set_width_chars(6)
        entry.set_valign(Gtk.Align.CENTER)
        row.add_suffix(entry)
        model = Gtk.StringList.new(["both", "tcp", "udp"])
        proto_dd = Gtk.DropDown(model=model)
        proto_dd.set_valign(Gtk.Align.CENTER)
        row.add_suffix(proto_dd)
        btn = Gtk.Button(label="Add")
        btn.add_css_class("suggested-action")
        btn.set_valign(Gtk.Align.CENTER)
        btn.connect("clicked", lambda _b: self._add_port(entry, proto_dd, svc_dd))
        row.add_suffix(btn)
        group.add(row)
        return row

    def _build_block_ip_row(self, group: Adw.PreferencesGroup) -> None:
        row = Adw.ActionRow(title="Block IP")
        row.set_subtitle("Drop traffic from an address")
        entry = Gtk.Entry()
        entry.set_placeholder_text("IP address")
        entry.set_width_chars(12)
        entry.set_valign(Gtk.Align.CENTER)
        row.add_suffix(entry)
        model = Gtk.StringList.new(["both", "tcp", "udp"])
        dd = Gtk.DropDown(model=model)
        dd.set_valign(Gtk.Align.CENTER)
        row.add_suffix(dd)
        btn = Gtk.Button(label="Block")
        btn.add_css_class("destructive-action")
        btn.set_valign(Gtk.Align.CENTER)
        btn.connect("clicked", lambda _b: self._block_ip(entry, dd))
        row.add_suffix(btn)
        self._block_ip_row = row
        group.add(row)

    def _build_ssh_tab(self) -> None:
        group = self._ssh_group
        daemon_row = Adw.ActionRow(title="SSH Daemon")
        daemon_row.set_subtitle("Enable and start the OpenSSH server")
        sw = Gtk.Switch()
        sw.set_valign(Gtk.Align.CENTER)
        sw.connect("state-set", self._on_ssh_daemon_toggle)
        daemon_row.add_suffix(sw)
        self._ssh_daemon_sw = sw
        group.add(daemon_row)

        port_row = Adw.ActionRow(title="SSH Port")
        port_row.set_subtitle("Port the SSH server listens on")
        adj = Gtk.Adjustment(value=22, lower=1, upper=65535, step_increment=1)
        spin = Gtk.SpinButton(adjustment=adj, digits=0)
        spin.set_valign(Gtk.Align.CENTER)
        spin.connect("value-changed", self._on_ssh_port_change)
        port_row.add_suffix(spin)
        self._ssh_port = spin
        group.add(port_row)

        pass_row = Adw.ActionRow(title="Password Authentication")
        pass_sw = Gtk.Switch()
        pass_sw.set_valign(Gtk.Align.CENTER)
        pass_sw.connect("state-set", lambda _s, st: self._apply_ssh_bool("PasswordAuthentication", st))
        pass_row.add_suffix(pass_sw)
        self._ssh_pass_sw = pass_sw
        group.add(pass_row)

        pubkey_row = Adw.ActionRow(title="Public Key Authentication")
        pubkey_sw = Gtk.Switch()
        pubkey_sw.set_valign(Gtk.Align.CENTER)
        pubkey_sw.connect("state-set", lambda _s, st: self._apply_ssh_bool("PubkeyAuthentication", st))
        pubkey_row.add_suffix(pubkey_sw)
        self._ssh_pubkey_sw = pubkey_sw
        group.add(pubkey_row)

        root_row = Adw.ActionRow(title="Root Login")
        root_model = Gtk.StringList.new(["No", "Prohibit Password", "Yes"])
        root_dd = Gtk.DropDown(model=root_model)
        root_dd.set_valign(Gtk.Align.CENTER)
        root_dd.connect("notify::selected", self._on_ssh_root_change)
        root_row.add_suffix(root_dd)
        self._ssh_root_dd = root_dd
        group.add(root_row)

        test_row = Adw.ActionRow(title="Validate Config")
        test_btn = Gtk.Button(label="Test")
        test_btn.set_valign(Gtk.Align.CENTER)
        test_btn.connect("clicked", lambda _b: self._ssh_test())
        test_row.add_suffix(test_btn)
        group.add(test_row)

        restart_row = Adw.ActionRow(title="Restart SSH")
        restart_btn = Gtk.Button(label="Restart")
        restart_btn.set_valign(Gtk.Align.CENTER)
        restart_btn.connect("clicked", lambda _b: self._run_ssh(["--restart"], "SSH restarted"))
        restart_row.add_suffix(restart_btn)
        group.add(restart_row)

        self._build_ssh_advanced()
        self._build_sessions_list()
        self._build_key_group()
        self._build_known_hosts()

    def _build_ssh_advanced(self) -> None:
        group = self._ssh_advanced_group
        if group is None:
            return

        empty_row = Adw.ActionRow(title="Permit Empty Passwords")
        empty_row.set_subtitle("Allow accounts with no password to log in")
        empty_sw = Gtk.Switch()
        empty_sw.set_valign(Gtk.Align.CENTER)
        empty_sw.connect("state-set", lambda _s, st: self._apply_ssh_bool("PermitEmptyPasswords", st))
        empty_row.add_suffix(empty_sw)
        self._ssh_empty_sw = empty_sw
        group.add(empty_row)

        x11_row = Adw.ActionRow(title="X11 Forwarding")
        x11_row.set_subtitle("Forward X11 GUI applications over SSH")
        x11_sw = Gtk.Switch()
        x11_sw.set_valign(Gtk.Align.CENTER)
        x11_sw.connect("state-set", lambda _s, st: self._apply_ssh_bool("X11Forwarding", st))
        x11_row.add_suffix(x11_sw)
        self._ssh_x11_sw = x11_sw
        group.add(x11_row)

        tcp_row = Adw.ActionRow(title="TCP Forwarding")
        tcp_row.set_subtitle("Allow tunneling TCP connections over SSH")
        tcp_sw = Gtk.Switch()
        tcp_sw.set_valign(Gtk.Align.CENTER)
        tcp_sw.connect("state-set", lambda _s, st: self._apply_ssh_bool("AllowTcpForwarding", st))
        tcp_row.add_suffix(tcp_sw)
        self._ssh_tcp_sw = tcp_sw
        group.add(tcp_row)

        tries_row = Adw.ActionRow(title="Max Auth Tries")
        tries_row.set_subtitle("Attempts before the connection is dropped")
        tries_adj = Gtk.Adjustment(value=6, lower=1, upper=20, step_increment=1)
        tries_spin = Gtk.SpinButton(adjustment=tries_adj, digits=0)
        tries_spin.set_valign(Gtk.Align.CENTER)
        tries_spin.connect("value-changed", self._on_ssh_tries_change)
        tries_row.add_suffix(tries_spin)
        self._ssh_tries = tries_spin
        group.add(tries_row)

        idle_row = Adw.ActionRow(title="Idle Timeout (seconds)")
        idle_row.set_subtitle("Disconnect idle clients after this time (0 = never)")
        idle_adj = Gtk.Adjustment(value=0, lower=0, upper=86400, step_increment=60)
        idle_spin = Gtk.SpinButton(adjustment=idle_adj, digits=0)
        idle_spin.set_valign(Gtk.Align.CENTER)
        idle_spin.connect("value-changed", self._on_ssh_idle_change)
        idle_row.add_suffix(idle_spin)
        self._ssh_idle = idle_spin
        group.add(idle_row)

        logs_row = Adw.ActionRow(title="SSH Logs")
        logs_btn = Gtk.Button(label="View Logs")
        logs_btn.set_valign(Gtk.Align.CENTER)
        logs_btn.connect("clicked", lambda _b: self._show_ssh_logs())
        logs_row.add_suffix(logs_btn)
        group.add(logs_row)

    def _build_sessions_list(self) -> None:
        group = self._sessions_group
        if group is None:
            return
        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search sessions\u2026")
        search.set_hexpand(True)
        search.connect("search-changed", lambda _e: self._rebuild_sessions())
        self._session_search = search
        row = Adw.ActionRow(title="")
        row.set_activatable(False)
        row.set_child(search)
        group.add(row)

        self._session_list = Gtk.ListBox()
        self._session_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(self._session_list)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(210)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

    def _build_key_group(self) -> None:
        group = self._key_group
        if group is None:
            return
        gen_row = Adw.ActionRow(title="Generate SSH Key")
        gen_row.set_subtitle("Create a new ed25519 key pair in ~/.ssh")
        gen_btn = Gtk.Button(label="Generate")
        gen_btn.set_valign(Gtk.Align.CENTER)
        gen_btn.connect("clicked", lambda _b: self._run_ssh(["--key-generate"], "SSH key generated"))
        gen_row.add_suffix(gen_btn)
        group.add(gen_row)

    def _build_known_hosts(self) -> None:
        group = self._known_group
        if group is None:
            return
        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search known hosts\u2026")
        search.set_hexpand(True)
        search.connect("search-changed", lambda _e: self._rebuild_known_hosts())
        self._known_search = search
        row = Adw.ActionRow(title="")
        row.set_activatable(False)
        row.set_child(search)
        group.add(row)

        self._known_list = Gtk.ListBox()
        self._known_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(self._known_list)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(210)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

    def _build_faillock_tab(self) -> None:
        group = self._faillock_group
        deny_row = Adw.ActionRow(title="Max Failed Attempts")
        deny_row.set_subtitle("Lock the account after this many failures")
        adj = Gtk.Adjustment(value=5, lower=1, upper=100, step_increment=1)
        spin = Gtk.SpinButton(adjustment=adj, digits=0)
        spin.set_valign(Gtk.Align.CENTER)
        spin.connect("value-changed", self._on_faillock_deny_change)
        deny_row.add_suffix(spin)
        self._faillock_deny = spin
        group.add(deny_row)

        unlock_row = Adw.ActionRow(title="Unlock Time (seconds)")
        unlock_row.set_subtitle("Time before a locked account unlocks")
        adj2 = Gtk.Adjustment(value=600, lower=0, upper=86400, step_increment=60)
        spin2 = Gtk.SpinButton(adjustment=adj2, digits=0)
        spin2.set_valign(Gtk.Align.CENTER)
        spin2.connect("value-changed", self._on_faillock_unlock_change)
        unlock_row.add_suffix(spin2)
        self._faillock_unlock = spin2
        group.add(unlock_row)

        root_row = Adw.ActionRow(title="Lock Root Account Too")
        root_sw = Gtk.Switch()
        root_sw.set_valign(Gtk.Align.CENTER)
        root_sw.connect("state-set", lambda _s, st: self._apply_faillock_bool("even_for_root", st))
        root_row.add_suffix(root_sw)
        self._faillock_root_sw = root_sw
        group.add(root_row)

        reset_row = Adw.ActionRow(title="Reset Failed Attempts")
        reset_btn = Gtk.Button(label="Reset")
        reset_btn.set_valign(Gtk.Align.CENTER)
        reset_btn.connect("clicked", lambda _b: self._run_ssh(["--faillock-reset"], "Failed attempts reset"))
        reset_row.add_suffix(reset_btn)
        group.add(reset_row)

        users_group = Adw.PreferencesGroup(title="Failed & Locked Accounts")
        users_group.set_description("Accounts with recorded login failures. Locked accounts are denied login until the unlock time passes or they are reset.")
        if self._fl_box is not None:
            self._fl_box.append(users_group)
        self._faillock_users_group = users_group
        placeholder = Adw.ActionRow(title="No failed attempts")
        placeholder.set_subtitle("No users have recorded login failures")
        placeholder.set_activatable(False)
        users_group.add(placeholder)
        self._faillock_user_rows = [placeholder]

    # ── Reload ──

    def _reload_all(self) -> None:
        self._reload_firewall()
        self._reload_ssh()
        self._reload_faillock()

    def _reload_firewall(self) -> None:
        def worker():
            data = _run(_FIREWALL_CORE, ["--status"])
            rules = _run(_FIREWALL_CORE, ["--rules"])
            blocked = _run(_FIREWALL_CORE, ["--blocked"])
            state = {}
            for line in data.splitlines():
                if "=" in line:
                    k, _, v = line.partition("=")
                    state[k] = v
            state["rules"] = rules
            state["blocked"] = blocked
            GLib.idle_add(self._apply_firewall_state, state)
        threading.Thread(target=worker, daemon=True).start()

    def _reload_connections(self) -> None:
        def worker():
            data = _run(_FIREWALL_CORE, ["--connections"])
            GLib.idle_add(self._apply_connections, data)
        threading.Thread(target=worker, daemon=True).start()

    def _apply_firewall_state(self, state: dict) -> None:
        self._fw_state = state
        active = state.get("daemon_status") == "active"
        policy = state.get("default_policy", "drop")
        outbound = state.get("outbound_policy", "accept")
        boot = state.get("boot_enabled") == "enabled"
        ping = state.get("ping") == "on"
        count = state.get("rule_count", "0")
        ports = state.get("open_ports", "")
        self._applying = True
        try:
            if self._firewall_sw is not None:
                self._firewall_sw.set_active(active)
            if self._boot_sw is not None:
                self._boot_sw.set_active(boot)
            if self._ping_sw is not None:
                self._ping_sw.set_active(ping)
            if self._policy_dd is not None:
                self._policy_dd.set_selected(1 if policy == "accept" else 0)
            if self._outbound_dd is not None:
                self._outbound_dd.set_selected(1 if outbound == "drop" else 0)
        finally:
            self._applying = False
        if self._fw_status_row is not None:
            self._fw_status_row.set_subtitle(f"Status: {'Active' if active else 'Inactive'} \u00b7 {count} rules \u00b7 Policy: {policy.title()} \u00b7 Ports: {ports or 'none'}")
        self._render_stats(state)
        self._render_ports(state.get("rules", ""))
        self._render_blocked(state.get("blocked", ""))

    @staticmethod
    def _remove_rows(group, rows: list) -> None:
        """Remove tracked rows from a PreferencesGroup.

        Adw.PreferencesGroup wraps added rows in an inner Gtk.ListBox, so
        ``row.get_parent()`` is the ListBox, never the group. Removing from
        the actual parent guarantees rows don't pile up on refresh.
        """
        for row in rows:
            parent = row.get_parent()
            if parent is not None:
                parent.remove(row)

    def _render_stats(self, state: dict) -> None:
        group = self._stats_group
        if group is None:
            return
        self._remove_rows(group, self._stat_rows)
        self._stat_rows = []
        blocked_pkts = state.get("blocked_packets", "0")
        top_ports = state.get("top_ports", "")
        rows = [
            ("Packets Blocked", blocked_pkts),
            ("Top Attacked Ports", top_ports or "none"),
        ]
        for title, val in rows:
            row = Adw.ActionRow(title=title, subtitle=str(val))
            group.add(row)
            self._stat_rows.append(row)

    def _render_ports(self, rules: str) -> None:
        group = self._ports_group
        if group is None:
            return
        self._remove_rows(group, self._fw_rows)
        self._fw_rows = []
        for line in rules.splitlines():
            if not line.startswith("RULES|"):
                continue
            parts = line.split("|")
            if len(parts) < 8:
                continue
            _eid, _r, proto, port, ip, action, packets, bytes_ = parts
            if ip and ip != "-" and port == "-":
                continue
            if ip and ip != "-":
                title = f"{ip}:{port}/{proto}"
                subtitle = f"{action} \u00b7 {packets} pkts"
            else:
                title = f"{port}/{proto}"
                subtitle = f"{action} \u00b7 {packets} pkts"
            row = Adw.ActionRow(title=title, subtitle=subtitle)
            rm_btn = Gtk.Button(icon_name="user-trash-symbolic")
            rm_btn.add_css_class("flat")
            rm_btn.set_valign(Gtk.Align.CENTER)
            rm_btn.set_tooltip_text("Remove rule")
            rm_btn.connect("clicked", lambda _b, rid=_eid: self._remove_rule(rid))
            row.add_suffix(rm_btn)
            group.add(row)
            self._fw_rows.append(row)

    def _render_blocked(self, blocked: str) -> None:
        group = self._blocked_group
        if group is None:
            return
        self._remove_rows(group, self._blocked_rows)
        self._blocked_rows = []
        count = 0
        for line in blocked.splitlines():
            if not line.startswith("BLOCK|"):
                continue
            parts = line.split("|")
            if len(parts) < 5:
                continue
            _b, ip, reason, proto, time_str = parts
            row = Adw.ActionRow(title=ip, subtitle=f"{time_str} \u00b7 {proto} \u00b7 {reason}")
            if reason != "manual":
                badge = Gtk.Label(label="auto")
                badge.add_css_class("tag")
                badge.add_css_class("accent")
                row.add_suffix(badge)
            ub_btn = Gtk.Button(icon_name="network-offline-symbolic")
            ub_btn.add_css_class("flat")
            ub_btn.set_valign(Gtk.Align.CENTER)
            ub_btn.set_tooltip_text("Unblock")
            ub_btn.connect("clicked", lambda _b, addr=ip: self._unblock_ip(addr))
            row.add_suffix(ub_btn)
            group.add(row)
            self._blocked_rows.append(row)
            count += 1
        if count == 0:
            lbl = Gtk.Label(label="No blocked addresses")
            lbl.add_css_class("dim-label")
            lbl.set_margin_top(8)
            lbl.set_margin_bottom(8)
            lbl.set_halign(Gtk.Align.CENTER)
            row = Gtk.ListBoxRow()
            row.set_child(lbl)
            group.add(row)
            self._blocked_rows.append(row)

    def _apply_connections(self, data: str) -> None:
        self._conn_items = []
        for line in data.splitlines():
            if not line.startswith("CONN|"):
                continue
            parts = line.split("|")
            if len(parts) < 7:
                continue
            _c, proto, state, local_addr, remote_addr, pid, proc = parts
            self._conn_items.append((proto, state, local_addr, remote_addr, pid, proc))
        self._rebuild_connections()

    def _rebuild_connections(self) -> None:
        lst = self._conn_list
        if lst is None:
            return
        while child := lst.get_first_child():
            lst.remove(child)
        q = self._conn_search.get_text().lower().strip() if self._conn_search else ""
        count = 0
        for proto, state, local_addr, remote_addr, pid, proc in self._conn_items:
            hay = f"{remote_addr} {local_addr} {proto} {state} {proc}".lower()
            if q and q not in hay:
                continue
            row = Adw.ActionRow(title=remote_addr, subtitle=f"{proto} \u00b7 {local_addr}")
            if proc:
                lbl = Gtk.Label(label=proc)
                lbl.add_css_class("dim-label")
                row.add_suffix(lbl)
            block_btn = Gtk.Button(icon_name="network-offline-symbolic")
            block_btn.add_css_class("flat")
            block_btn.set_valign(Gtk.Align.CENTER)
            block_btn.set_tooltip_text("Block this IP")
            block_btn.connect("clicked", lambda _b, addr=remote_addr: self._block_ip_from_conn(addr))
            row.add_suffix(block_btn)
            if pid:
                close_btn = Gtk.Button(icon_name="window-close-symbolic")
                close_btn.add_css_class("flat")
                close_btn.set_valign(Gtk.Align.CENTER)
                close_btn.set_tooltip_text("Close this connection")
                close_btn.connect("clicked", lambda _b, p=pid: self._close_connection(p))
                row.add_suffix(close_btn)
            lst.append(row)
            count += 1
        if count == 0:
            lbl = Gtk.Label(label="No active connections")
            lbl.add_css_class("dim-label")
            lbl.set_margin_top(8)
            lbl.set_margin_bottom(8)
            lbl.set_halign(Gtk.Align.CENTER)
            row = Gtk.ListBoxRow()
            row.set_child(lbl)
            lst.append(row)

    def _reload_ssh(self) -> None:
        def worker():
            data = _run(_SSH_CORE, ["--status"])
            state = {}
            for line in data.splitlines():
                if "=" in line:
                    k, _, v = line.partition("=")
                    state[k] = v
            sessions = _run(_SSH_CORE, ["--sessions"])
            state["sessions"] = sessions
            keys = _run(_SSH_CORE, ["--key-status"])
            state["keys"] = keys
            known = _run(_SSH_CORE, ["--known-hosts"])
            state["known"] = known
            GLib.idle_add(self._apply_ssh_state, state)
        threading.Thread(target=worker, daemon=True).start()

    def _apply_ssh_state(self, state: dict) -> None:
        self._ssh_state = state
        self._applying = True
        try:
            if self._ssh_daemon_sw is not None:
                self._ssh_daemon_sw.set_active(state.get("daemon_status") == "active")
            if self._ssh_port is not None:
                try:
                    self._ssh_port.set_value(float(state.get("ssh_port", "22")))
                except (TypeError, ValueError):
                    pass
            if self._ssh_pass_sw is not None:
                self._ssh_pass_sw.set_active(state.get("password_auth") == "yes")
            if self._ssh_pubkey_sw is not None:
                self._ssh_pubkey_sw.set_active(state.get("pubkey_auth") == "yes")
            if self._ssh_root_dd is not None:
                root = state.get("root_login", "prohibit-password")
                idx = {"no": 0, "prohibit-password": 1, "yes": 2}.get(root, 1)
                self._ssh_root_dd.set_selected(idx)
            if self._ssh_empty_sw is not None:
                self._ssh_empty_sw.set_active(state.get("empty_passwords") == "yes")
            if self._ssh_x11_sw is not None:
                self._ssh_x11_sw.set_active(state.get("x11_forwarding") == "yes")
            if self._ssh_tcp_sw is not None:
                self._ssh_tcp_sw.set_active(state.get("tcp_forwarding") == "yes")
            if self._ssh_tries is not None:
                try:
                    self._ssh_tries.set_value(float(state.get("max_auth_tries", "6")))
                except (TypeError, ValueError):
                    pass
            if self._ssh_idle is not None:
                try:
                    self._ssh_idle.set_value(float(state.get("idle_timeout", "0")))
                except (TypeError, ValueError):
                    pass
        finally:
            self._applying = False
        self._render_sessions(state.get("sessions", ""))
        self._apply_ssh_keys(state.get("keys", ""))
        self._render_known_hosts(state.get("known", ""))

    def _render_sessions(self, sessions: str) -> None:
        self._session_items = []
        for line in sessions.splitlines():
            if line.startswith("user="):
                parts = dict(p.split("=", 1) for p in line.split("|") if "=" in p)
                self._session_items.append(parts)
        self._rebuild_sessions()

    def _rebuild_sessions(self) -> None:
        lst = self._session_list
        if lst is None:
            return
        while child := lst.get_first_child():
            lst.remove(child)
        q = self._session_search.get_text().lower().strip() if self._session_search else ""
        count = 0
        for parts in self._session_items:
            ip = parts.get("ip", "")
            user = parts.get("user", "")
            since = parts.get("since", "")
            hay = f"{ip} {user} {since}".lower()
            if q and q not in hay:
                continue
            row = Adw.ActionRow(title=ip, subtitle=f"{user} \u00b7 {since}")
            block_btn = Gtk.Button(icon_name="network-offline-symbolic")
            block_btn.add_css_class("flat")
            block_btn.set_valign(Gtk.Align.CENTER)
            block_btn.set_tooltip_text("Block this IP")
            block_btn.connect("clicked", lambda _b, addr=ip: self._block_ip_from_conn(addr))
            row.add_suffix(block_btn)
            close_btn = Gtk.Button(icon_name="window-close-symbolic")
            close_btn.add_css_class("flat")
            close_btn.set_valign(Gtk.Align.CENTER)
            close_btn.set_tooltip_text("Close SSH sessions from this IP")
            close_btn.connect("clicked", lambda _b, addr=ip: self._kill_ssh_ip(addr))
            row.add_suffix(close_btn)
            lst.append(row)
            count += 1
        if count == 0:
            lbl = Gtk.Label(label="No active SSH sessions")
            lbl.add_css_class("dim-label")
            lbl.set_margin_top(8)
            lbl.set_margin_bottom(8)
            lbl.set_halign(Gtk.Align.CENTER)
            row = Gtk.ListBoxRow()
            row.set_child(lbl)
            lst.append(row)

    def _apply_ssh_keys(self, keys: str) -> None:
        group = self._key_group
        if group is None:
            return
        self._remove_rows(group, self._key_rows)
        self._key_rows = []
        section = ""
        for line in keys.splitlines():
            line = line.strip()
            if line == "---host_keys---":
                section = "host"
                continue
            if line == "---user_keys---":
                section = "user"
                continue
            if "=" not in line:
                continue
            parts = dict(p.split("=", 1) for p in line.split("|") if "=" in p)
            if section == "host":
                title = f"Host {parts.get('type', '')}"
                fp = parts.get("fingerprint", "")
            else:
                title = parts.get("file", "~/.ssh/key")
                fp = parts.get("fingerprint", "")
            row = Adw.ActionRow(title=title, subtitle=fp)
            if section == "user":
                copy_btn = Gtk.Button(icon_name="edit-copy-symbolic")
                copy_btn.set_valign(Gtk.Align.CENTER)
                copy_btn.set_tooltip_text("Copy fingerprint")
                copy_btn.connect("clicked", lambda _b, f=fp: self._copy_fingerprint(f))
                row.add_suffix(copy_btn)
            group.add(row)
            self._key_rows.append(row)

    def _copy_fingerprint(self, fingerprint: str) -> None:
        from gi.repository import Gdk
        clipboard = Gdk.Display.get_default().get_clipboard()
        clipboard.set(fingerprint)
        self._window.show_toast("Fingerprint copied")

    def _render_known_hosts(self, known: str) -> None:
        self._known_items = []
        for line in known.splitlines():
            if not line.startswith("host="):
                continue
            parts = dict(p.split("=", 1) for p in line.split("|") if "=" in p)
            self._known_items.append(parts)
        self._rebuild_known_hosts()

    def _rebuild_known_hosts(self) -> None:
        lst = self._known_list
        if lst is None:
            return
        while child := lst.get_first_child():
            lst.remove(child)
        q = self._known_search.get_text().lower().strip() if self._known_search else ""
        count = 0
        for parts in self._known_items:
            host = parts.get("host", "")
            algo = parts.get("algorithm", "")
            hay = f"{host} {algo}".lower()
            if q and q not in hay:
                continue
            row = Adw.ActionRow(title=host, subtitle=algo)
            rm_btn = Gtk.Button(icon_name="user-trash-symbolic")
            rm_btn.set_valign(Gtk.Align.CENTER)
            rm_btn.set_tooltip_text("Remove host")
            rm_btn.connect("clicked", lambda _b, h=host: self._remove_known_host(h))
            row.add_suffix(rm_btn)
            lst.append(row)
            count += 1
        if count == 0:
            lbl = Gtk.Label(label="No known hosts")
            lbl.add_css_class("dim-label")
            lbl.set_margin_top(8)
            lbl.set_margin_bottom(8)
            lbl.set_halign(Gtk.Align.CENTER)
            row = Gtk.ListBoxRow()
            row.set_child(lbl)
            lst.append(row)

    def _remove_known_host(self, host: str) -> None:
        from settings.ui import confirm
        confirm(
            self._window,
            "Remove known host?",
            f"Remove {host} from ~/.ssh/known_hosts?",
            "Remove",
            lambda: self._run_ssh(["--known-hosts-remove", host], f"{host} removed", refresh=True),
        )

    def _reload_faillock(self) -> None:
        def worker():
            data = _run(_SSH_CORE, ["--faillock-status"])
            state = {}
            for line in data.splitlines():
                if "=" in line:
                    k, _, v = line.partition("=")
                    state[k] = v
            users = _run(_SSH_CORE, ["--faillock-users"])
            user_list: list[dict] = []
            for line in users.splitlines():
                entry = {}
                for part in line.split("|"):
                    if "=" in part:
                        k, _, v = part.partition("=")
                        entry[k] = v
                if entry:
                    user_list.append(entry)
            GLib.idle_add(self._apply_faillock_state, state, user_list)
        threading.Thread(target=worker, daemon=True).start()

    def _apply_faillock_state(self, state: dict, user_list: list | None = None) -> None:
        self._faillock_state = state
        self._applying = True
        try:
            if self._faillock_deny is not None:
                try:
                    self._faillock_deny.set_value(float(state.get("deny", "5")))
                except (TypeError, ValueError):
                    pass
            if self._faillock_unlock is not None:
                try:
                    self._faillock_unlock.set_value(float(state.get("unlock_time", "600")))
                except (TypeError, ValueError):
                    pass
            if self._faillock_root_sw is not None:
                self._faillock_root_sw.set_active(state.get("even_for_root") == "true")
        finally:
            self._applying = False
        if user_list is not None:
            self._render_faillock_users(user_list)

    def _render_faillock_users(self, user_list: list[dict]) -> None:
        group = self._faillock_users_group
        if group is None:
            return
        self._remove_rows(group, self._faillock_user_rows)
        self._faillock_user_rows = []
        rows = [u for u in user_list if int(u.get("failures") or 0) > 0]
        if not rows:
            placeholder = Adw.ActionRow(title="No failed attempts")
            placeholder.set_subtitle("No users have recorded login failures")
            placeholder.set_activatable(False)
            group.add(placeholder)
            self._faillock_user_rows = [placeholder]
            return
        for u in sorted(rows, key=lambda x: -int(x.get("failures") or 0)):
            user = u.get("user", "?")
            failures = int(u.get("failures") or 0)
            locked = u.get("locked") == "true"
            reason = u.get("reason", "")
            source = u.get("source", "")
            last = u.get("last", "0")
            try:
                when = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(int(last))) if int(last) > 0 else ""
            except (ValueError, OSError):
                when = ""
            row = Adw.ActionRow(title=user)
            subtitle = f"{failures} failed attempt{'s' if failures != 1 else ''}"
            if locked:
                subtitle += " \u2022 LOCKED"
            if reason:
                subtitle += f" \u2022 {reason}"
            if when:
                subtitle += f" \u2022 last: {when}"
            if source:
                subtitle += f" \u2022 from {source}"
            row.set_subtitle(subtitle)
            reset_btn = Gtk.Button(label="Reset")
            reset_btn.set_valign(Gtk.Align.CENTER)
            reset_btn.connect(
                "clicked",
                lambda _b, u=user: self._run_ssh(["--faillock-reset", u], f"Failed attempts reset for {u}"),
            )
            row.add_suffix(reset_btn)
            group.add(row)
            self._faillock_user_rows.append(row)

    # ── Firewall actions ──

    def _on_firewall_toggle(self, _sw, active: bool) -> bool:
        if self._applying:
            return False
        args = ["--on"] if active else ["--off"]
        self._pkexec(_FIREWALL_CORE, args, "Firewall enabled" if active else "Firewall disabled", refresh=True)
        return False

    def _on_policy_change(self, dd, _pspec) -> None:
        if self._applying:
            return
        policy = "drop" if dd.get_selected() == 0 else "accept"
        self._pkexec(_FIREWALL_CORE, ["--default", policy], f"Default policy set to {policy}", refresh=True)

    def _on_boot_toggle(self, _sw, active: bool) -> bool:
        if self._applying:
            return False
        mode = "enable" if active else "disable"
        self._pkexec(_FIREWALL_CORE, ["--boot", mode], f"Firewall {'enabled' if active else 'disabled'} at boot", refresh=True)
        return False

    def _on_outbound_change(self, dd, _pspec) -> None:
        if self._applying:
            return
        policy = "accept" if dd.get_selected() == 0 else "drop"
        self._pkexec(_FIREWALL_CORE, ["--outbound", policy], f"Outbound policy set to {policy}", refresh=True)

    def _on_ping_toggle(self, _sw, active: bool) -> bool:
        if self._applying:
            return False
        mode = "on" if active else "off"
        self._pkexec(_FIREWALL_CORE, ["--ping", mode], f"Ping {'allowed' if active else 'blocked'}", refresh=True)
        return False

    def _on_service_preset(self, entry: Gtk.Entry, proto_dd: Gtk.DropDown, svc_dd: Gtk.DropDown) -> None:
        name = ["Custom", "SSH", "HTTP", "HTTPS", "DNS", "SMB", "RDP", "VNC"][svc_dd.get_selected()]
        if name == "Custom":
            return
        port, proto = self._SERVICE_PORTS[name]
        entry.set_text(port)
        proto_dd.set_selected(0 if proto == "both" else (1 if proto == "tcp" else 2))

    def _block_ip(self, entry: Gtk.Entry, dd: Gtk.DropDown | None = None) -> None:
        ip = entry.get_text().strip()
        if not ip:
            return
        proto = "both"
        if dd is not None:
            proto = ["both", "tcp", "udp"][dd.get_selected()]
        self._pkexec(_FIREWALL_CORE, ["--block", ip, "manual", proto], f"{ip} blocked ({proto})", refresh=True)
        entry.set_text("")

    def _block_ip_from_conn(self, ip: str) -> None:
        self._pkexec(
            _FIREWALL_CORE,
            ["--block", ip, "manual", "both"],
            f"{ip} blocked",
            refresh=True,
            extra_args=[("--kill-ssh", [ip])],
        )

    def _close_connection(self, pid: str) -> None:
        self._pkexec(_FIREWALL_CORE, ["--kill-connection", pid], f"Connection closed (pid {pid})", refresh=True)

    def _kill_ssh_ip(self, ip: str) -> None:
        self._pkexec(_FIREWALL_CORE, ["--kill-ssh", ip], f"SSH sessions from {ip} closed", refresh=True)

    def _unblock_ip(self, ip: str) -> None:
        self._pkexec(_FIREWALL_CORE, ["--unblock", ip], f"{ip} unblocked", refresh=True)

    def _add_port(self, entry: Gtk.Entry, dd: Gtk.DropDown, svc_dd: Gtk.DropDown | None = None) -> None:
        port = entry.get_text().strip()
        proto = ["both", "tcp", "udp"][dd.get_selected()]
        if svc_dd is not None and svc_dd.get_selected() > 0:
            name = ["Custom", "SSH", "HTTP", "HTTPS", "DNS", "SMB", "RDP", "VNC"][svc_dd.get_selected()]
            port, preset_proto = self._SERVICE_PORTS[name]
            if preset_proto != proto:
                proto = preset_proto
        if not port.isdigit():
            self._window.show_toast("Enter a valid port", timeout=3)
            return
        self._pkexec(_FIREWALL_CORE, ["--allow", port, proto], f"Port {port}/{proto} opened", refresh=True)
        entry.set_text("")

    def _remove_rule(self, rule_id: str) -> None:
        self._pkexec(_FIREWALL_CORE, ["--delete", rule_id], f"Rule {rule_id} removed", refresh=True)

    # ── SSH actions ──

    def _on_ssh_daemon_toggle(self, _sw, active: bool) -> bool:
        if self._applying:
            return False
        args = ["--enable"] if active else ["--disable"]
        self._pkexec(_SSH_CORE, args, "SSH enabled" if active else "SSH disabled", refresh=True)
        return False

    def _on_ssh_port_change(self, spin) -> None:
        if self._applying:
            return
        port = str(int(spin.get_value()))
        self._pkexec(_SSH_CORE, ["--config-set", "Port", port], f"SSH port set to {port}")

    def _apply_ssh_bool(self, key: str, active: bool) -> None:
        if self._applying:
            return
        val = "yes" if active else "no"
        self._pkexec(_SSH_CORE, ["--config-set", key, val], f"{key} set to {val}")

    def _on_ssh_root_change(self, dd, _pspec) -> None:
        if self._applying:
            return
        root = {0: "no", 1: "prohibit-password", 2: "yes"}.get(dd.get_selected(), "prohibit-password")
        self._pkexec(_SSH_CORE, ["--config-set", "PermitRootLogin", root], f"Root login set to {root}")

    def _ssh_test(self) -> None:
        self._pkexec(_SSH_CORE, ["--test"], "sshd_config is valid")

    def _on_ssh_tries_change(self, spin) -> None:
        if self._applying:
            return
        val = str(int(spin.get_value()))
        self._pkexec(_SSH_CORE, ["--config-set", "MaxAuthTries", val], f"Max auth tries set to {val}")

    def _on_ssh_idle_change(self, spin) -> None:
        if self._applying:
            return
        val = str(int(spin.get_value()))
        self._pkexec(_SSH_CORE, ["--config-set", "ClientAliveInterval", val], f"Idle timeout set to {val}s")

    def _show_ssh_logs(self) -> None:
        self._window.show_toast("Fetching SSH logs\u2026", timeout=3)

        def worker():
            data = _run(_SSH_CORE, ["--logs", "40"])
            lines = data.strip().splitlines()
            GLib.idle_add(self._present_ssh_logs, lines)

        threading.Thread(target=worker, daemon=True).start()

    def _present_ssh_logs(self, lines: list) -> None:
        dialog = Adw.MessageDialog.new(self._window, "Recent SSH Logs", "")
        if lines:
            dialog.set_body("\n".join(lines[-40:]))
        else:
            dialog.set_body("No SSH logs available.")
        dialog.add_response("close", "Close")
        dialog.present()

    # ── Faillock actions ──

    def _on_faillock_deny_change(self, spin) -> None:
        if self._applying:
            return
        self._pkexec(_SSH_CORE, ["--faillock-set", "deny", str(int(spin.get_value()))], "Faillock deny updated")

    def _on_faillock_unlock_change(self, spin) -> None:
        if self._applying:
            return
        self._pkexec(_SSH_CORE, ["--faillock-set", "unlock_time", str(int(spin.get_value()))], "Faillock unlock time updated")

    def _apply_faillock_bool(self, key: str, active: bool) -> None:
        if self._applying:
            return
        val = "true" if active else "false"
        self._pkexec(_SSH_CORE, ["--faillock-set", key, val], f"Faillock {key} set to {val}")

    # ── Generic privileged worker ──

    def _pkexec(self, script: str, args: list[str], success: str, refresh: bool = False, extra_args: list | None = None) -> None:
        self._window.show_toast("Applying\u2026", timeout=3)

        def worker():
            cmds = [["sudo", "-n", script, *args]]
            for e_script, e_args in extra_args or []:
                cmds.append(["sudo", "-n", e_script, *e_args])
            try:
                r = subprocess.run(cmds[0], capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
            except Exception as e:
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=str(e), timeout=6))
                return
            out = (r.stdout or "") + (r.stderr or "")
            err = (r.stderr or "").lower()
            sudo_failed = ("password" in err or "not permitted" in err or
                           "not in the sudoers" in err or "no password was provided" in err)
            ok = (r.returncode == 0 or "OK|" in out) and not sudo_failed
            if ok:
                for c in cmds[1:]:
                    try:
                        subprocess.run(c, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
                    except Exception:
                        pass
                GLib.idle_add(lambda: self._window.show_toast(success, timeout=4))
                if refresh:
                    GLib.idle_add(self._reload_all)
                return

            if not sudo_failed:
                tail = "\n".join(out.strip().splitlines()[-8:])
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=tail or str(r.returncode), timeout=8))
                if refresh:
                    GLib.idle_add(self._reload_all)
                return

            full_cmds = [["pkexec", "bash", script, *args]]
            for e_script, e_args in extra_args or []:
                full_cmds.append(["pkexec", "bash", e_script, *e_args])
            try:
                r = subprocess.run(full_cmds[0], capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
            except Exception as e:
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=str(e), timeout=6))
                return
            out = (r.stdout or "") + (r.stderr or "")
            ok = r.returncode == 0 or "OK|" in out
            if ok:
                for c in full_cmds[1:]:
                    try:
                        subprocess.run(c, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
                    except Exception:
                        pass
                GLib.idle_add(lambda: self._window.show_toast(success, timeout=4))
            else:
                tail = "\n".join(out.strip().splitlines()[-8:])
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=tail or str(r.returncode), timeout=8))
            if refresh:
                GLib.idle_add(self._reload_all)

        threading.Thread(target=worker, daemon=True).start()

    def _run_ssh(self, args: list[str], success: str) -> None:
        self._pkexec(_SSH_CORE, args, success, refresh=True)

    def _show_drops(self) -> None:
        self._window.show_toast("Fetching recent drops\u2026", timeout=3)

        def worker():
            data = _run(_FIREWALL_CORE, ["--drops", "30"])
            lines = data.strip().splitlines()
            GLib.idle_add(self._present_drops, lines)

        threading.Thread(target=worker, daemon=True).start()

    def _present_drops(self, lines: list) -> None:
        dialog = Adw.MessageDialog.new(self._window, "Recent Dropped Packets", "")
        if lines:
            body = "\n".join(lines[-30:])
            dialog.set_body(body)
            dialog.set_extra_child(Gtk.Label(label="Shown: last dropped connection attempts"))
        else:
            dialog.set_body("No dropped packets logged yet.")
        dialog.add_response("close", "Close")
        dialog.present()

    def _export_ruleset(self) -> None:
        def on_confirm():
            path = os.path.join(os.path.expanduser("~"), "retro-firewall-rules.nft")
            self._pkexec(_FIREWALL_CORE, ["--export", path], f"Ruleset exported to {path}")

        def on_save(dlg, result):
            try:
                file = dlg.save_finish(result)
                if file is None:
                    return
                path = file.get_path()
                self._pkexec(_FIREWALL_CORE, ["--export", path], f"Ruleset exported to {path}")
            except Exception:
                pass

        file_dialog = Gtk.FileDialog()
        file_dialog.set_title("Export firewall ruleset")
        file_dialog.save(self._window, None, on_save)

    def _import_ruleset(self) -> None:
        def on_open(dlg, result):
            try:
                file = dlg.open_finish(result)
                if file is None:
                    return
                path = file.get_path()
                from settings.ui import confirm
                confirm(
                    self._window,
                    "Import firewall ruleset?",
                    f"Import rules from {path}?\n\nThis replaces the current firewall rules.",
                    "Import",
                    lambda: self._pkexec(_FIREWALL_CORE, ["--import", path], "Ruleset imported", refresh=True),
                )
            except Exception:
                pass

        file_dialog = Gtk.FileDialog()
        file_dialog.set_title("Import firewall ruleset")
        file_dialog.open(self._window, None, on_open)

    def missing_count(self) -> int:
        return 0

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        self._dirty = False

    def discard(self) -> None:
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return iter([])

    def flush_pending(self) -> None:
        pass

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "security:firewall", "label": "Firewall",
             "description": "Enable the nftables firewall, set default policy and open ports",
             "_group_id": "security", "_group_label": "Security", "_section_label": "Firewall"},
            {"key": "security:ssh", "label": "SSH",
             "description": "Configure the SSH daemon, port, auth methods and sessions",
             "_group_id": "security", "_group_label": "Security", "_section_label": "SSH"},
            {"key": "security:faillock", "label": "Faillock",
             "description": "Brute-force protection: max attempts, unlock time, root locking",
             "_group_id": "security", "_group_label": "Security", "_section_label": "Faillock"},
        ]

    def destroy(self) -> None:
        pass


__all__ = ["SecurityPage"]
