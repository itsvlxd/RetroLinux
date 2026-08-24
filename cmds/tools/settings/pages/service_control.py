"""Service control page — manage systemd services with start/stop/restart/enable/disable."""

import subprocess
import threading
import time
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk, Pango

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_SERVICE_CORE = "/opt/retrolinux/scripts/service_core.sh"
_SERVICE_ICON = "system-service-symbolic"
_REFRESH_MS = 10000


def _run_core(*args: str) -> str:
    try:
        r = subprocess.run(
            ["bash", _SERVICE_CORE, *args],
            capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _list_services(filter_type: str = "all") -> list[dict]:
    result = _run_core("--list", filter_type)
    if not result or "result=none" in result:
        return []
    services = []
    for line in result.splitlines():
        parts = line.split("|")
        if len(parts) >= 6 and parts[0] == "service":
            services.append({
                "name": parts[1],
                "load": parts[2],
                "active": parts[3],
                "sub": parts[4],
                "description": parts[5],
            })
    return services


class _ServiceRow(Gtk.ListBoxRow):
    """A single service row with status and action buttons."""

    def __init__(self, svc: dict, on_action):
        super().__init__()
        self._name = svc["name"]
        self._on_action = on_action

        active = svc.get("active", "inactive")
        sub = svc.get("sub", "")
        desc = svc.get("description", "")
        is_active = active in ("active", "running")
        is_failed = active == "failed"

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(8)
        box.set_margin_end(8)

        # Status icon
        if is_failed:
            icon_name = "dialog-error-symbolic"
            icon_css = "error"
        elif is_active:
            icon_name = "emblem-ok-symbolic"
            icon_css = "success"
        else:
            icon_name = "process-stop-symbolic"
            icon_css = "dim-label"

        icon_img = Gtk.Image.new_from_icon_name(icon_name)
        icon_img.set_valign(Gtk.Align.CENTER)
        icon_img.set_pixel_size(20)
        icon_img.add_css_class(icon_css)
        box.append(icon_img)

        # Text
        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        text_box.set_hexpand(True)

        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        name_lbl = Gtk.Label(label=self._name)
        name_lbl.set_halign(Gtk.Align.START)
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        name_box.append(name_lbl)

        if is_active:
            state_lbl = Gtk.Label(label=sub.upper())
            state_lbl.add_css_class("badge")
            state_lbl.add_css_class("success")
            name_box.append(state_lbl)
        elif is_failed:
            state_lbl = Gtk.Label(label="FAILED")
            state_lbl.add_css_class("badge")
            state_lbl.add_css_class("error")
            name_box.append(state_lbl)

        text_box.append(name_box)

        if desc:
            desc_lbl = Gtk.Label(label=desc)
            desc_lbl.set_halign(Gtk.Align.START)
            desc_lbl.set_ellipsize(Pango.EllipsizeMode.END)
            desc_lbl.add_css_class("dim-label")
            desc_lbl.add_css_class("caption")
            text_box.append(desc_lbl)

        box.append(text_box)

        # Action buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        btn_box.set_valign(Gtk.Align.CENTER)

        # Log button
        log_btn = Gtk.Button(icon_name="utilities-terminal-symbolic")
        log_btn.set_tooltip_text("View logs")
        log_btn.set_size_request(32, 32)
        log_btn.add_css_class("flat")
        log_btn.connect("clicked", lambda _b: self._open_logs())
        btn_box.append(log_btn)

        if is_active:
            stop = Gtk.Button(icon_name="media-playback-stop-symbolic")
            stop.set_tooltip_text("Stop")
            stop.set_size_request(32, 32)
            stop.connect("clicked", lambda _b: on_action("stop", self._name))
            btn_box.append(stop)

            restart = Gtk.Button(icon_name="view-refresh-symbolic")
            restart.set_tooltip_text("Restart")
            restart.set_size_request(32, 32)
            restart.connect("clicked", lambda _b: on_action("restart", self._name))
            btn_box.append(restart)
        else:
            start = Gtk.Button(icon_name="media-playback-start-symbolic")
            start.set_tooltip_text("Start")
            start.set_size_request(32, 32)
            start.connect("clicked", lambda _b: on_action("start", self._name))
            btn_box.append(start)

        box.append(btn_box)
        self.set_child(box)

        # CSS class based on state
        if is_active:
            self.add_css_class("option-managed")
        else:
            self.add_css_class("option-default")

    def _open_logs(self) -> None:
        """Open journalctl logs for this service in a dialog."""
        dialog = Adw.Dialog()
        dialog.set_title(f"Logs — {self._name}")
        dialog.set_content_width(700)
        dialog.set_content_height(500)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        # Log text view
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)

        text_view = Gtk.TextView()
        text_view.set_editable(False)
        text_view.set_monospace(True)
        text_view.set_wrap_mode(Gtk.WrapMode.NONE)
        text_view.add_css_class("view")

        # Load logs in background
        def load_logs():
            try:
                r = subprocess.run(
                    ["journalctl", "-u", self._name, "-n", "200", "--no-pager", "-o", "short-iso"],
                    capture_output=True, text=True, timeout=10,
                )
                logs = r.stdout or "No logs available"
            except Exception as e:
                logs = f"Error loading logs: {e}"

            def apply_logs():
                text_view.get_buffer().set_text(logs)
                # Scroll to bottom
                adj = scrolled.get_vadjustment()
                adj.set_value(adj.get_upper() - adj.get_page_size())

            GLib.idle_add(apply_logs)

        threading.Thread(target=load_logs, daemon=True).start()

        scrolled.set_child(text_view)
        toolbar.set_content(scrolled)
        dialog.set_child(toolbar)
        dialog.present(self.get_root())


class ServiceControlPage:
    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None
        self._content_box: Gtk.Box | None = None
        self._timer = 0
        self._services: list[dict] = []
        self._filter = "all"
        self._search = ""
        self._listbox: Gtk.ListBox | None = None
        self._count_label: Gtk.Label | None = None

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        # Refresh button
        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh services")
        refresh_btn.connect("clicked", lambda _: self._refresh())
        header.pack_start(refresh_btn)

        # ── Status section ──
        status_group = Adw.PreferencesGroup(title="Service Status", description="Overview of system services managed by systemd.")

        self._count_label = Gtk.Label(label="Loading\u2026")
        self._count_label.set_valign(Gtk.Align.CENTER)
        self._count_label.add_css_class("dim-label")
        count_row = Adw.ActionRow(title="Total Services", subtitle="Number of services matching the current filter")
        count_row.add_suffix(self._count_label)
        status_group.add(count_row)

        clean_btn = Gtk.Button(label="Reset Failed State")
        clean_btn.set_valign(Gtk.Align.CENTER)
        clean_btn.add_css_class("destructive-action")
        clean_btn.set_tooltip_text("Reset all failed services")
        clean_btn.connect("clicked", lambda _: self._clean_failed())
        clean_row = Adw.ActionRow(title="Reset Failed", subtitle="Clear the failed state of all services")
        clean_row.add_suffix(clean_btn)
        status_group.add(clean_row)

        self._content_box.append(status_group)

        # ── Search and Filter row ──
        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search services\u2026")
        search.set_hexpand(True)
        search.connect("search-changed", self._on_search_changed)
        self._search_entry = search

        self._filter_dd = Gtk.DropDown(model=Gtk.StringList.new([
            "All", "Running", "Failed", "Enabled",
        ]))
        self._filter_dd.set_valign(Gtk.Align.CENTER)
        self._filter_dd.connect("notify::selected", self._on_filter_changed)

        search_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        search_bar.set_margin_start(12)
        search_bar.set_margin_end(12)
        search_bar.set_margin_top(8)
        search_bar.set_margin_bottom(8)
        search_bar.append(search)
        search_bar.append(self._filter_dd)
        self._content_box.append(search_bar)

        # ── Service list ──
        list_group = Adw.PreferencesGroup(title="Services", description="Click a service to start, stop, or restart it. Active services are shown in green.")
        self._listbox = Gtk.ListBox()
        self._listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._listbox.add_css_class("boxed-list")
        list_group.add(self._listbox)
        self._content_box.append(list_group)

        self._refresh()
        return toolbar_view

    def _on_filter_changed(self, _dd, _pspec) -> None:
        idx = self._filter_dd.get_selected()
        self._filter = ["all", "running", "failed", "enabled"][idx]
        self._refresh()

    # ── Actions ──

    def _on_search_changed(self, _entry: Gtk.SearchEntry) -> None:
        self._search = self._search_entry.get_text().lower().strip()
        self._rebuild_list()

    def _refresh(self) -> None:
        def load():
            svcs = _list_services(self._filter)
            GLib.idle_add(self._apply, svcs)
        threading.Thread(target=load, daemon=True).start()

    def _apply(self, svcs: list[dict]) -> None:
        self._services = svcs
        self._rebuild_list()
        n = len(svcs)
        self._count_label.set_text(f"{n} service{'s' if n != 1 else ''}")

    def _rebuild_list(self) -> None:
        if not self._listbox:
            return
        while child := self._listbox.get_first_child():
            self._listbox.remove(child)

        q = self._search
        filtered = [s for s in self._services
                    if not q or q in s["name"].lower() or q in s.get("description", "").lower()]

        if not filtered:
            empty = Gtk.Label(label="No services found")
            empty.set_margin_top(24)
            empty.set_margin_bottom(24)
            empty.set_halign(Gtk.Align.CENTER)
            empty.add_css_class("dim-label")
            row = Gtk.ListBoxRow()
            row.set_child(empty)
            row.set_activatable(False)
            self._listbox.append(row)
            return

        for svc in filtered:
            row = _ServiceRow(svc, self._do_action)
            self._listbox.append(row)

    def _do_action(self, action: str, name: str) -> None:
        def run():
            _run_core(f"--{action}", name)
            time.sleep(0.3)
            GLib.idle_add(self._refresh)
        threading.Thread(target=run, daemon=True).start()

    def _clean_failed(self) -> None:
        def run():
            _run_core("--clean-failed")
            time.sleep(0.3)
            GLib.idle_add(self._refresh)
        threading.Thread(target=run, daemon=True).start()

    # ── Lifecycle ──

    def on_shown(self) -> None:
        self._timer = GLib.timeout_add(_REFRESH_MS, self._on_tick)

    def on_hidden(self) -> None:
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0

    def _on_tick(self) -> bool:
        self._refresh()
        return True

    def is_dirty(self) -> bool:
        return False

    def mark_saved(self) -> None:
        pass

    def discard(self) -> None:
        pass

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return []

    def get_search_entries(self) -> list[dict]:
        return [{
            "key": "service:control",
            "label": "Services",
            "description": "Manage systemd services, start/stop/restart, enable/disable",
            "_group_id": "service_control",
            "_group_label": "Services",
            "_section_label": "System",
        }]


__all__ = ["ServiceControlPage"]
