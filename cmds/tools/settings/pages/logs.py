"""System logs management page — view, enable/disable, clear log sources."""

import os
import glob
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

_LOG_DIR = "/tmp/retro_logs"
_LOGS_ICON = "text-view-symbolic"
_LINE_OPTIONS = [30, 60, 90, 120]


def _scan_logs() -> list[dict]:
    logs = []
    for path in sorted(glob.glob(os.path.join(_LOG_DIR, "watcher_*.log"))):
        basename = os.path.basename(path)
        name = basename.replace("watcher_", "").replace(".log", "")
        disabled = os.path.exists(path.replace(".log", ".disabled"))
        lines = 0
        mtime = 0
        try:
            stat = os.stat(path)
            mtime = stat.st_mtime
            with open(path) as f:
                for _ in f:
                    lines += 1
        except OSError:
            pass
        logs.append({"name": name, "lines": lines, "mtime": mtime, "disabled": disabled, "path": path})
    return logs


def _relative_time(ts: float) -> str:
    diff = time.time() - ts
    if diff < 60:
        return f"{int(diff)}s ago"
    if diff < 3600:
        return f"{int(diff / 60)}m ago"
    if diff < 86400:
        return f"{int(diff / 3600)}h ago"
    return f"{int(diff / 86400)}d ago"


def _read_log(name: str, limit: int = 30) -> list[str]:
    path = os.path.join(_LOG_DIR, f"watcher_{name}.log")
    try:
        with open(path) as f:
            lines = f.read().strip().splitlines()
        return lines[-limit:]
    except OSError:
        return []


class LogsPage:
    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._dirty = False
        self._on_dirty_changed = None
        self._tick_source = None
        self._logs: list[dict] = []
        self._expanded_count = 0

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh logs")
        refresh_btn.connect("clicked", lambda _b: self._full_refresh())
        header.pack_start(refresh_btn)

        # Log Overview
        og = Adw.PreferencesGroup(title="Log Overview")
        self._build_overview(og)
        self._content_box.append(og)

        # Log Sources
        sg = Adw.PreferencesGroup(title="Log Sources")
        self._build_sources(sg)
        self._content_box.append(sg)

        self._tick_source = GLib.timeout_add(10000, self._tick)

        return toolbar_view

    def _load_data(self) -> None:
        self._logs = _scan_logs()

    def _full_refresh(self) -> None:
        self._load_data()
        GLib.idle_add(self._rebuild)

    def _build_overview(self, group: Adw.PreferencesGroup) -> None:
        self._load_data()
        total = len(self._logs)
        active = sum(1 for l in self._logs if not l["disabled"])
        disabled = total - active
        entries = sum(l["lines"] for l in self._logs)

        def make_row(title: str, desc: str, val: str) -> Adw.ActionRow:
            r = Adw.ActionRow(title=title, subtitle=desc)
            lbl = Gtk.Label(label=val)
            lbl.set_valign(Gtk.Align.CENTER)
            r.add_suffix(lbl)
            group.add(r)
            return r

        total_row = make_row("Total Sources", "Registered log source files", str(total))
        active_row = make_row("Active", "Log sources currently recording", str(active))
        disabled_row = make_row("Disabled", "Log sources paused via .disabled", str(disabled))
        entries_row = make_row("Entries", "Total log lines across all sources", str(entries))
        self._total_row = total_row
        self._active_row = active_row
        self._disabled_row = disabled_row
        self._entries_row = entries_row

        # Global lines selector
        sel_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        sel_box.set_valign(Gtk.Align.CENTER)
        sel_lbl = Gtk.Label(label="Lines to show:")
        sel_lbl.add_css_class("caption")
        sel_box.append(sel_lbl)
        line_sel = Gtk.DropDown.new_from_strings([str(n) for n in _LINE_OPTIONS])
        line_sel.set_selected(0)
        sel_box.append(line_sel)
        lines_row = Adw.ActionRow(title="Log Preview Limit")
        lines_row.add_suffix(sel_box)
        group.add(lines_row)
        self._global_lines = line_sel

    def get_lines_limit(self) -> int:
        if hasattr(self, "_global_lines"):
            return _LINE_OPTIONS[self._global_lines.get_selected()]
        return 30

    def _build_sources(self, group: Adw.PreferencesGroup) -> None:
        search_entry = Gtk.SearchEntry()
        search_entry.set_placeholder_text("Search logs\u2026")
        search_entry.set_hexpand(True)
        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        search_box.append(search_entry)
        search_row = Adw.ActionRow(title="")
        search_row.set_activatable(False)
        search_row.set_child(search_box)
        group.add(search_row)
        self._search_entry = search_entry

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        listbox.add_css_class("boxed-list")
        self._listbox = listbox

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(listbox)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(400)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

        search_entry.connect("search-changed", lambda e: self._rebuild())
        self._rebuild()

    def _rebuild(self) -> None:
        self._expanded_count = 0
        q = self._search_entry.get_text().lower().strip() if hasattr(self, "_search_entry") else ""
        limit = self.get_lines_limit()
        while child := self._listbox.get_first_child():
            self._listbox.remove(child)

        for log in self._logs:
            if q and q not in log["name"].lower():
                continue

            display_name = log["name"][0].upper() + log["name"][1:]
            ago = _relative_time(log["mtime"]) if log["mtime"] else "never"
            subtitle = f"{log['lines']} lines  \u00b7  Last: {ago}"

            expander = Adw.ExpanderRow()
            expander.set_title(display_name)
            expander.set_subtitle(subtitle)
            if log["disabled"]:
                expander.add_css_class("option-default")
            else:
                expander.add_css_class("option-managed")

            def on_expand_track(e, _pspec):
                if e.get_expanded():
                    self._expanded_count += 1
                else:
                    self._expanded_count -= 1
            expander.connect("notify::expanded", on_expand_track)

            power_sw = Gtk.Switch()
            power_sw.set_valign(Gtk.Align.CENTER)
            power_sw.set_active(not log["disabled"])
            power_sw.connect("notify::active", lambda sw, n=log["name"]: self._toggle_log(n, sw.get_active()))
            expander.add_suffix(power_sw)

            clear_btn = Gtk.Button(icon_name="user-trash-symbolic")
            clear_btn.set_valign(Gtk.Align.CENTER)
            clear_btn.set_tooltip_text("Clear")
            clear_btn.connect("clicked", lambda _b, n=log["name"]: self._clear_log(n))
            expander.add_suffix(clear_btn)

            # Build log content synchronously right now
            lines = _read_log(log["name"], limit)
            if lines:
                log_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
                for line in lines:
                    color = None
                    if "[ERROR]" in line:
                        color = "red"
                    elif "[WARN]" in line:
                        color = "#e5a50a"
                    if color:
                        lbl = Gtk.Label()
                        lbl.set_markup(f'<span foreground="{color}">{line}</span>')
                    else:
                        lbl = Gtk.Label(label=line)
                    lbl.set_halign(Gtk.Align.START)
                    lbl.add_css_class("caption")
                    lbl.set_margin_start(6)
                    lbl.set_margin_end(6)
                    lbl.set_margin_top(1)
                    lbl.set_margin_bottom(1)
                    log_box.append(lbl)
                log_sw = Gtk.ScrolledWindow()
                log_sw.set_child(log_box)
                log_sw.set_min_content_height(120)
                log_sw.set_vexpand(True)
                log_row = Adw.ActionRow()
                log_row.set_activatable(False)
                log_row.set_child(log_sw)
                expander.add_row(log_row)
            else:
                lbl = Gtk.Label(label="(empty)")
                lbl.set_halign(Gtk.Align.START)
                lbl.add_css_class("dim-label")
                lbl.add_css_class("caption")
                lbl.set_margin_top(8)
                lbl.set_margin_bottom(8)
                lbl.set_margin_start(8)
                empty_row = Adw.ActionRow()
                empty_row.set_activatable(False)
                empty_row.set_child(lbl)
                expander.add_row(empty_row)

            self._listbox.append(expander)

        if not self._listbox.get_first_child():
            empty_lbl = Gtk.Label(label="No logs found")
            empty_lbl.set_margin_top(16)
            empty_lbl.set_margin_bottom(16)
            empty_lbl.set_halign(Gtk.Align.CENTER)
            empty_lbl.add_css_class("dim-label")
            r = Gtk.ListBoxRow()
            r.set_child(empty_lbl)
            self._listbox.append(r)

    def _toggle_log(self, name: str, enable: bool) -> None:
        disabled_file = os.path.join(_LOG_DIR, f"watcher_{name}.disabled")
        if enable:
            try:
                os.remove(disabled_file)
            except OSError:
                pass
        else:
            try:
                with open(disabled_file, "w") as f:
                    f.write("")
            except OSError:
                pass
        GLib.idle_add(self._full_refresh)

    def _clear_log(self, name: str) -> None:
        log_path = os.path.join(_LOG_DIR, f"watcher_{name}.log")
        try:
            with open(log_path, "w"):
                pass
        except OSError:
            pass
        GLib.idle_add(self._full_refresh)

    def _tick(self) -> bool:
        if self._expanded_count > 0:
            return True
        threading.Thread(target=self._tick_worker, daemon=True).start()
        return True

    def _tick_worker(self) -> None:
        new_logs = _scan_logs()
        GLib.idle_add(self._apply_tick, new_logs)

    def _apply_tick(self, new_logs: list[dict]) -> None:
        if self._expanded_count > 0:
            return
        self._logs = new_logs
        total = len(self._logs)
        active = sum(1 for l in self._logs if not l["disabled"])
        disabled = total - active
        entries = sum(l["lines"] for l in self._logs)
        vals = {"_total_row": str(total), "_active_row": str(active),
                "_disabled_row": str(disabled), "_entries_row": str(entries)}
        for attr, val in vals.items():
            if hasattr(self, attr):
                row = getattr(self, attr)
                last = row.get_last_child()
                if isinstance(last, Gtk.Label):
                    last.set_label(val)
        self._rebuild()

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
                category="Logs",
                title="Log Configuration",
                subtitle="Log settings changed",
                navigate_to="logs",
                icon=_LOGS_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "logs:overview", "label": "Log Overview",
             "description": "Total sources, active, disabled, entries",
             "_group_id": "logs", "_group_label": "Logs", "_section_label": "Overview"},
            {"key": "logs:sources", "label": "Log Sources",
             "description": "View, enable, disable, and clear log sources",
             "_group_id": "logs", "_group_label": "Logs", "_section_label": "Sources"},
        ]

    def destroy(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None
