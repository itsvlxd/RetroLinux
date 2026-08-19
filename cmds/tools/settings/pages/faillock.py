"""Dedicated Faillock page — brute-force protection and failed login tracking."""

import threading
import time

from gi.repository import Adw, GLib, Gtk

from settings.pages.security_common import (
    SecurityPageBase,
    _SSH_CORE,
    _remove_rows,
    _run,
)
from settings.ui import make_page_layout


class FaillockPage(SecurityPageBase):
    def __init__(self, window):
        super().__init__(window)
        self._content_box: Gtk.Box | None = None
        self._faillock_state: dict = {}
        self._faillock_deny: Gtk.SpinButton | None = None
        self._faillock_unlock: Gtk.SpinButton | None = None
        self._faillock_root_sw: Gtk.Switch | None = None
        self._faillock_users_group: Adw.PreferencesGroup | None = None
        self._faillock_user_rows: list = []

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, content_box, _ = make_page_layout(header=header)
        self._content_box = content_box

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh faillock status")
        refresh_btn.connect("clicked", lambda _b: self._reload())
        header.pack_start(refresh_btn)

        self._build_faillock()
        self._reload()
        return toolbar_view

    def _build_faillock(self) -> None:
        box = self._content_box
        if box is None:
            return

        group = Adw.PreferencesGroup(title="Faillock")
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

        box.append(group)

        users_group = Adw.PreferencesGroup(title="Failed &amp; Locked Accounts")
        users_group.set_description("Accounts with recorded login failures. Locked accounts are denied login until the unlock time passes or they are reset.")
        box.append(users_group)
        self._faillock_users_group = users_group
        placeholder = Adw.ActionRow(title="No failed attempts")
        placeholder.set_subtitle("No users have recorded login failures")
        placeholder.set_activatable(False)
        users_group.add(placeholder)
        self._faillock_user_rows = [placeholder]

    # ── Reload ──

    def _reload(self) -> None:
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
        _remove_rows(group, self._faillock_user_rows)
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

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "faillock:main", "label": "Faillock",
             "description": "Brute-force protection: max attempts, unlock time, root locking",
             "_group_id": "faillock", "_group_label": "Security", "_section_label": "Faillock"},
        ]


__all__ = ["FaillockPage"]