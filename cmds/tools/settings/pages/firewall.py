"""Dedicated Firewall page — nftables status, policy, traffic, ports, blocks."""

import os
import threading

from gi.repository import Adw, GLib, Gtk

from settings.pages.security_common import (
    SERVICE_NAMES,
    SERVICE_PORTS,
    FirewallTrafficGraph,
    SecurityPageBase,
    _FIREWALL_CORE,
    _remove_rows,
    _run,
)
from settings.ui import make_page_layout


class FirewallPage(SecurityPageBase):
    def __init__(self, window):
        super().__init__(window)
        self._content_box: Gtk.Box | None = None
        self._firewall_sw: Gtk.Switch | None = None
        self._policy_dd: Gtk.DropDown | None = None
        self._boot_sw: Gtk.Switch | None = None
        self._ping_sw: Gtk.Switch | None = None
        self._outbound_dd: Gtk.DropDown | None = None
        self._fw_status_row: Adw.ActionRow | None = None
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
        self._ports_group: Adw.PreferencesGroup | None = None
        self._blocked_ports_group: Adw.PreferencesGroup | None = None
        self._blocked_group: Adw.PreferencesGroup | None = None
        self._conn_group: Adw.PreferencesGroup | None = None
        self._block_ip_row: Adw.ActionRow | None = None
        self._blocked_ports_rows: list = []

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, content_box, _ = make_page_layout(header=header)
        self._content_box = content_box

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh firewall status")
        refresh_btn.connect("clicked", lambda _b: self._reload())
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

        self._build_firewall()
        self._reload()
        return toolbar_view

    def on_shown(self) -> None:
        if self._traffic_graph is not None:
            self._traffic_graph.start()
        if self._conn_timer == 0:
            self._reload_connections()
            self._conn_timer = GLib.timeout_add(5000, self._refresh_connections_tick)

    def on_hidden(self) -> None:
        if self._traffic_graph is not None:
            self._traffic_graph.stop()
        if self._conn_timer != 0:
            GLib.source_remove(self._conn_timer)
            self._conn_timer = 0

    def _refresh_connections_tick(self) -> bool:
        self._reload_connections()
        return True

    def _build_firewall(self) -> None:
        box = self._content_box
        if box is None:
            return

        status_group = Adw.PreferencesGroup(title="Firewall (nftables)")
        status_row = Adw.ActionRow(title="Firewall Status", subtitle="Checking\u2026")
        status_row.add_prefix(Gtk.Image.new_from_icon_name("security-high-symbolic"))
        self._fw_status_row = status_row
        status_group.add(status_row)

        sw_row = Adw.ActionRow(title="Enable Firewall")
        sw_row.set_subtitle("Enable and start the nftables firewall")
        sw = Gtk.Switch()
        sw.set_valign(Gtk.Align.CENTER)
        sw.connect("state-set", self._on_firewall_toggle)
        sw_row.add_suffix(sw)
        self._firewall_sw = sw
        status_group.add(sw_row)

        boot_row = Adw.ActionRow(title="Start at Boot")
        boot_row.set_subtitle("Enable the nftables service at system start")
        boot_sw = Gtk.Switch()
        boot_sw.set_valign(Gtk.Align.CENTER)
        boot_sw.connect("state-set", self._on_boot_toggle)
        boot_row.add_suffix(boot_sw)
        self._boot_sw = boot_sw
        status_group.add(boot_row)

        policy_row = Adw.ActionRow(title="Default Inbound Policy")
        policy_row.set_subtitle("Drop blocks all unsolicited inbound traffic")
        model = Gtk.StringList.new(["Drop", "Accept"])
        dd = Gtk.DropDown(model=model)
        dd.set_valign(Gtk.Align.CENTER)
        dd.connect("notify::selected", self._on_policy_change)
        policy_row.add_suffix(dd)
        self._policy_dd = dd
        status_group.add(policy_row)

        out_row = Adw.ActionRow(title="Default Outbound Policy")
        out_row.set_subtitle("Drop blocks all unsolicited outbound traffic")
        out_model = Gtk.StringList.new(["Accept", "Drop"])
        out_dd = Gtk.DropDown(model=out_model)
        out_dd.set_valign(Gtk.Align.CENTER)
        out_dd.connect("notify::selected", self._on_outbound_change)
        out_row.add_suffix(out_dd)
        self._outbound_dd = out_dd
        status_group.add(out_row)

        ping_row = Adw.ActionRow(title="Allow Ping")
        ping_row.set_subtitle("Respond to ICMP echo-request (ping)")
        ping_sw = Gtk.Switch()
        ping_sw.set_valign(Gtk.Align.CENTER)
        ping_sw.connect("state-set", self._on_ping_toggle)
        ping_row.add_suffix(ping_sw)
        self._ping_sw = ping_sw
        status_group.add(ping_row)

        box.append(status_group)

        stats_group = Adw.PreferencesGroup(title="Traffic Statistics")
        self._stats_group = stats_group
        box.append(stats_group)
        self._traffic_graph = FirewallTrafficGraph()
        graph_row = Adw.ActionRow(title="")
        graph_row.set_activatable(False)
        graph_row.set_child(self._traffic_graph)
        stats_group.add(graph_row)

        ports_group = Adw.PreferencesGroup(title="Allowed Ports")
        self._ports_group = ports_group
        box.append(ports_group)
        self._build_add_port_row(ports_group)

        blocked_ports_group = Adw.PreferencesGroup(title="Blocked Ports")
        self._blocked_ports_group = blocked_ports_group
        box.append(blocked_ports_group)
        placeholder = Adw.ActionRow(title="No blocked ports")
        placeholder.set_subtitle("Ports that are explicitly blocked")
        placeholder.set_activatable(False)
        blocked_ports_group.add(placeholder)
        self._blocked_ports_rows = [placeholder]

        blocked_group = Adw.PreferencesGroup(title="Blocked Addresses")
        self._blocked_group = blocked_group
        box.append(blocked_group)
        self._build_block_ip_row(blocked_group)

        conn_group = Adw.PreferencesGroup(title="Active Connections")
        self._conn_group = conn_group
        box.append(conn_group)
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
        svc_model = Gtk.StringList.new(SERVICE_NAMES)
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

    # ── Reload ──

    def _reload(self) -> None:
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

    def _render_stats(self, state: dict) -> None:
        group = self._stats_group
        if group is None:
            return
        _remove_rows(group, self._stat_rows)
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
        ports_group = self._ports_group
        blocked_ports_group = self._blocked_ports_group
        _remove_rows(ports_group, self._fw_rows)
        self._fw_rows = []
        if blocked_ports_group is not None:
            _remove_rows(blocked_ports_group, self._blocked_ports_rows)
        self._blocked_ports_rows = []
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
            row._rule_identity = (proto, port, ip, action)
            rm_btn.connect("clicked", lambda _b, r=row: self._remove_rule_row(r))
            row.add_suffix(rm_btn)
            if action == "drop":
                if blocked_ports_group is not None:
                    blocked_ports_group.add(row)
                    self._blocked_ports_rows.append(row)
                continue
            if ports_group is not None:
                ports_group.add(row)
                self._fw_rows.append(row)
        if blocked_ports_group is not None and not self._blocked_ports_rows:
            placeholder = Adw.ActionRow(title="No blocked ports")
            placeholder.set_subtitle("Ports that are explicitly blocked")
            placeholder.set_activatable(False)
            blocked_ports_group.add(placeholder)
            self._blocked_ports_rows = [placeholder]

    def _render_blocked(self, blocked: str) -> None:
        group = self._blocked_group
        if group is None:
            return
        _remove_rows(group, self._blocked_rows)
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
        name = SERVICE_NAMES[svc_dd.get_selected()]
        if name == "Custom":
            return
        port, proto = SERVICE_PORTS[name]
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
            name = SERVICE_NAMES[svc_dd.get_selected()]
            port, preset_proto = SERVICE_PORTS[name]
            if preset_proto != proto:
                proto = preset_proto
        if not port.isdigit():
            self._window.show_toast("Enter a valid port", timeout=3)
            return
        self._pkexec(_FIREWALL_CORE, ["--allow", port, proto], f"Port {port}/{proto} opened", refresh=True)
        entry.set_text("")

    def _remove_rule(self, rule_id: str) -> None:
        self._pkexec(_FIREWALL_CORE, ["--delete", rule_id], f"Rule {rule_id} removed", refresh=True)

    def _remove_rule_row(self, row: Adw.ActionRow) -> None:
        """Remove the rule backing *row*.

        The ruleset's index-based rule ids can shift between renders (a
        prior delete or an external change), leaving a stale id that the
        backend rejects with ``not_found``. Resolve the rule's current id
        by its identity (protocol/port/ip/action) from a fresh ``--rules``
        fetch instead of trusting the id captured at render time.
        """
        identity = row._rule_identity
        if identity is None:
            self._reload()
            return
        proto, port, ip, action = identity

        def worker():
            data = _run(_FIREWALL_CORE, ["--rules"])
            current = None
            for line in data.splitlines():
                if not line.startswith("RULES|"):
                    continue
                parts = line.split("|")
                if len(parts) < 8:
                    continue
                _rid, p, pt, addr, act = parts[1], parts[2], parts[3], parts[4], parts[5]
                if p == proto and pt == port and addr == ip and act == action:
                    current = _rid
                    break
            if current is None:
                GLib.idle_add(self._reload)
                return
            GLib.idle_add(lambda: self._remove_rule(current))

        threading.Thread(target=worker, daemon=True).start()

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

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "firewall:main", "label": "Firewall",
             "description": "Enable the nftables firewall, set default policy and open ports",
             "_group_id": "firewall", "_group_label": "Security", "_section_label": "Firewall"},
        ]


__all__ = ["FirewallPage"]