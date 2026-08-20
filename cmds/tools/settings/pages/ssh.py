"""Dedicated SSH page — daemon settings, sessions, keys and known hosts."""

import threading

from gi.repository import Adw, GLib, Gtk

from settings.pages.security_common import (
    SecurityPageBase,
    _SSH_CORE,
    _remove_rows,
    _run,
)
from settings.ui import make_page_layout


class SshPage(SecurityPageBase):
    def __init__(self, window):
        super().__init__(window)
        self._content_box: Gtk.Box | None = None
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
        self._session_list: Gtk.ListBox | None = None
        self._session_search: Gtk.SearchEntry | None = None
        self._session_items: list = []
        self._key_group: Adw.PreferencesGroup | None = None
        self._key_rows: list = []
        self._known_list: Gtk.ListBox | None = None
        self._known_search: Gtk.SearchEntry | None = None
        self._known_items: list = []

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, content_box, _ = make_page_layout(header=header)
        self._content_box = content_box

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh SSH status")
        refresh_btn.connect("clicked", lambda _b: self._reload())
        header.pack_start(refresh_btn)

        self._build_ssh()
        self._reload()
        return toolbar_view

    def _build_ssh(self) -> None:
        box = self._content_box
        if box is None:
            return

        group = Adw.PreferencesGroup(title="SSH")
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

        box.append(group)

        adv_group = Adw.PreferencesGroup(title="Advanced Settings")
        self._build_ssh_advanced(adv_group)
        box.append(adv_group)

        sess_group = Adw.PreferencesGroup(title="Active Sessions")
        self._build_sessions_list(sess_group)
        box.append(sess_group)

        key_group = Adw.PreferencesGroup(title="Key Management")
        self._key_group = key_group
        self._build_key_group(key_group)
        box.append(key_group)

        known_group = Adw.PreferencesGroup(title="Known Hosts")
        self._build_known_hosts(known_group)
        box.append(known_group)

    def _build_ssh_advanced(self, group: Adw.PreferencesGroup) -> None:
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

    def _build_sessions_list(self, group: Adw.PreferencesGroup) -> None:
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

    def _build_key_group(self, group: Adw.PreferencesGroup) -> None:
        gen_row = Adw.ActionRow(title="Generate SSH Key")
        gen_row.set_subtitle("Create a new ed25519 key pair in ~/.ssh")
        gen_btn = Gtk.Button(label="Generate")
        gen_btn.set_valign(Gtk.Align.CENTER)
        gen_btn.connect("clicked", lambda _b: self._run_ssh(["--key-generate"], "SSH key generated"))
        gen_row.add_suffix(gen_btn)
        group.add(gen_row)

    def _build_known_hosts(self, group: Adw.PreferencesGroup) -> None:
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

    # ── Reload ──

    def _reload(self) -> None:
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
        _remove_rows(group, self._key_rows)
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

    def _block_ip_from_conn(self, ip: str) -> None:
        from settings.pages.security_common import _FIREWALL_CORE
        self._pkexec(
            _FIREWALL_CORE,
            ["--block", ip, "manual", "both"],
            f"{ip} blocked",
            refresh=True,
            extra_args=[("--kill-ssh", [ip])],
        )

    def _kill_ssh_ip(self, ip: str) -> None:
        from settings.pages.security_common import _FIREWALL_CORE
        self._pkexec(_FIREWALL_CORE, ["--kill-ssh", ip], f"SSH sessions from {ip} closed", refresh=True)

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "ssh:main", "label": "SSH",
             "description": "Configure the SSH daemon, port, auth methods and sessions",
             "_group_id": "ssh", "_group_label": "Security", "_section_label": "SSH"},
        ]


__all__ = ["SshPage"]