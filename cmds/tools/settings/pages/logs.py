"""System logs management page — view, enable/disable, clear log sources."""

import glob
import os
import time
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_LOG_DIR = "/tmp/retro_logs"
_LOGS_ICON = "text-view-symbolic"
_LINE_OPTIONS = [30, 60, 90, 120]
_TICK_MS = 5000


def _log_paths() -> list[str]:
    return sorted(glob.glob(os.path.join(_LOG_DIR, "watcher_*.log")))


def _count_lines(path: str) -> int:
    try:
        with open(path) as f:
            return sum(1 for _ in f)
    except OSError:
        return 0


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
        # cache: path -> (size, mtime_ns, lines)
        self._line_cache: dict[str, tuple[int, int, int]] = {}
        self._expanders: dict[str, Adw.ExpanderRow] = {}
        self._content_sw: dict[str, Gtk.ScrolledWindow] = {}
        self._content_state: dict[str, tuple[int, int]] = {}
        self._disabled_state: dict[str, bool] = {}
        self._expanded: set[str] = set()

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

        self._tick_source = GLib.timeout_add(_TICK_MS, self._tick)

        return toolbar_view

    # ── Data loading ──

    def _scan_logs(self) -> list[dict]:
        seen = set()
        logs = []
        for path in _log_paths():
            name = os.path.basename(path).replace("watcher_", "").replace(".log", "")
            seen.add(path)
            disabled = os.path.exists(path.replace(".log", ".disabled"))
            try:
                st = os.stat(path)
            except OSError:
                continue
            cached = self._line_cache.get(path)
            if cached and cached[0] == st.st_size and cached[1] == st.st_mtime_ns:
                lines = cached[2]
            else:
                lines = _count_lines(path)
                self._line_cache[path] = (st.st_size, st.st_mtime_ns, lines)
            logs.append({
                "name": name,
                "lines": lines,
                "mtime": st.st_mtime,
                "mtime_ns": st.st_mtime_ns,
                "size": st.st_size,
                "disabled": disabled,
                "path": path,
            })
        for path in list(self._line_cache):
            if path not in seen:
                del self._line_cache[path]
        return logs

    def _load_data(self) -> None:
        self._logs = self._scan_logs()

    def _log_by_name(self, name: str) -> dict | None:
        for log in self._logs:
            if log["name"] == name:
                return log
        return None

    def _full_refresh(self) -> None:
        self._load_data()
        self._rebuild()

    # ── Overview ──

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
        line_sel.connect("notify::selected", lambda *_: self._rebuild())
        lines_row = Adw.ActionRow(title="Log Preview Limit")
        lines_row.add_suffix(sel_box)
        group.add(lines_row)
        self._global_lines = line_sel

    def get_lines_limit(self) -> int:
        if hasattr(self, "_global_lines"):
            return _LINE_OPTIONS[self._global_lines.get_selected()]
        return 30

    # ── Sources ──

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
        q = self._search_entry.get_text().lower().strip() if hasattr(self, "_search_entry") else ""
        while child := self._listbox.get_first_child():
            self._listbox.remove(child)
        self._expanders = {}
        self._content_sw = {}
        self._content_state = {}

        for log in self._logs:
            if q and q not in log["name"].lower():
                continue
            expander = self._make_expander(log)
            self._listbox.append(expander)
            self._expanders[log["name"]] = expander

        # Re-open rows the user had expanded.
        for name in list(self._expanded):
            expander = self._expanders.get(name)
            if expander:
                expander.set_expanded(True)

        if not self._listbox.get_first_child():
            empty_lbl = Gtk.Label(label="No logs found")
            empty_lbl.set_margin_top(16)
            empty_lbl.set_margin_bottom(16)
            empty_lbl.set_halign(Gtk.Align.CENTER)
            empty_lbl.add_css_class("dim-label")
            r = Gtk.ListBoxRow()
            r.set_child(empty_lbl)
            self._listbox.append(r)

    def _make_expander(self, log: dict) -> Adw.ExpanderRow:
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
        self._disabled_state[log["name"]] = log["disabled"]

        def on_expand(e, _pspec, name=log["name"]):
            if e.get_expanded():
                self._expanded.add(name)
                self._refresh_expanded_content(name)
            else:
                self._expanded.discard(name)
        expander.connect("notify::expanded", on_expand)

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

        # Content is built lazily the first time the row is expanded.
        sw = Gtk.ScrolledWindow()
        sw.set_min_content_height(120)
        sw.set_vexpand(True)
        content_row = Adw.ActionRow()
        content_row.set_activatable(False)
        content_row.set_child(sw)
        expander.add_row(content_row)
        self._content_sw[log["name"]] = sw
        return expander

    def _refresh_expanded_content(self, name: str) -> None:
        log = self._log_by_name(name)
        sw = self._content_sw.get(name)
        if not log or not sw:
            return

        key = (log["size"], log["mtime_ns"])
        if self._content_state.get(name) == key:
            return
        self._content_state[name] = key

        lines = _read_log(name, self.get_lines_limit())
        if not lines:
            lbl = Gtk.Label(label="(empty)")
            lbl.set_halign(Gtk.Align.START)
            lbl.add_css_class("dim-label")
            lbl.add_css_class("caption")
            lbl.set_margin_top(8)
            lbl.set_margin_bottom(8)
            lbl.set_margin_start(8)
            sw.set_child(lbl)
            return

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

        sw.set_child(log_box)
        adj = sw.get_vadjustment()
        adj.set_value(adj.get_upper())

        def _scroll_to_bottom():
            adj.set_value(adj.get_upper())
            return False
        GLib.idle_add(_scroll_to_bottom)

    # ── Actions ──

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
        self._full_refresh()

    def _clear_log(self, name: str) -> None:
        log_path = os.path.join(_LOG_DIR, f"watcher_{name}.log")
        try:
            with open(log_path, "w"):
                pass
        except OSError:
            pass
        self._full_refresh()

    # ── Live refresh ──

    def _tick(self) -> bool:
        self._load_data()
        self._apply_tick()
        return True

    def _apply_tick(self) -> None:
        current_names = {l["name"] for l in self._logs}
        if set(self._expanders) != current_names:
            self._rebuild()
            return

        total = len(self._logs)
        active = sum(1 for l in self._logs if not l["disabled"])
        disabled = total - active
        entries = sum(l["lines"] for l in self._logs)
        vals = {"_total_row": str(total), "_active_row": str(active),
                "_disabled_row": str(disabled), "_entries_row": str(entries)}
        for attr, val in vals.items():
            row = getattr(self, attr, None)
            if row is not None:
                last = row.get_last_child()
                if isinstance(last, Gtk.Label):
                    last.set_label(val)

        for log in self._logs:
            expander = self._expanders.get(log["name"])
            if not expander:
                continue
            ago = _relative_time(log["mtime"]) if log["mtime"] else "never"
            expander.set_subtitle(f"{log['lines']} lines  \u00b7  Last: {ago}")
            if self._disabled_state.get(log["name"]) != log["disabled"]:
                expander.remove_css_class("option-default")
                expander.remove_css_class("option-managed")
                expander.add_css_class("option-default" if log["disabled"] else "option-managed")
                self._disabled_state[log["name"]] = log["disabled"]

        # Live-tail expanded logs whose files actually changed.
        for name in list(self._expanded):
            self._refresh_expanded_content(name)

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
