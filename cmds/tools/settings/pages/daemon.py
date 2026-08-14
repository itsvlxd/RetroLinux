"""Daemon management page — status, watchers, logs, events, CPU/memory."""

import glob
import os
import re
import subprocess
import threading
import time
from collections.abc import Iterable
from typing import TYPE_CHECKING

try:
    _CLK_TCK = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
except Exception:
    _CLK_TCK = 100

from gi.repository import Adw, Gdk, GLib, Gtk, Pango, cairo

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_RETRO_DIR = os.environ.get("RETRO_DIR", "/opt/retrolinux")
_DAEMON_SCRIPT = os.path.join(_RETRO_DIR, "daemon", "event_daemon.lua")
_DAEMON_ICON = "system-run-symbolic"
_PID_FILE = "/tmp/retro_event_daemon.pid"
_LOG_DIR = "/tmp/retro_logs"
_WATCHERS_DIR = os.path.join(_RETRO_DIR, "daemon", "watchers")


class DaemonStats:
    """Reads CPU and memory usage from /proc/<pid>/stat and /proc/<pid>/status."""

    def __init__(self):
        self._last_cpu = 0.0
        self._last_time = 0.0
        self.cpu_pcts: list[float] = []
        self.mem_kb: list[float] = []
        self._max_samples = 60

    def sample(self, pid: int) -> None:
        if pid <= 0:
            return
        try:
            with open(f"/proc/{pid}/stat") as f:
                parts = f.read().strip().split()
                utime = int(parts[13])
                stime = int(parts[14])
            with open(f"/proc/{pid}/status") as f:
                text = f.read()
            m = re.search(r"VmRSS:\s+(\d+)", text)
            rss_kb = int(m.group(1)) if m else 0
        except (FileNotFoundError, IndexError, ValueError, OSError):
            return

        now = time.monotonic()
        if self._last_time > 0:
            dt = now - self._last_time
            if dt > 0:
                cpu_total = (utime + stime) - self._last_cpu
                cpu_pct = (cpu_total / _CLK_TCK) / dt * 100
                self.cpu_pcts.append(cpu_pct)
                self.mem_kb.append(float(rss_kb))
                if len(self.cpu_pcts) > self._max_samples:
                    self.cpu_pcts.pop(0)
                    self.mem_kb.pop(0)

        self._last_cpu = utime + stime
        self._last_time = now

    def max_cpu(self) -> float:
        return max(self.cpu_pcts) if self.cpu_pcts else 1.0

    def max_mem(self) -> float:
        return max(self.mem_kb) if self.mem_kb else 1.0

    def clear(self) -> None:
        self.cpu_pcts.clear()
        self.mem_kb.clear()
        self._last_cpu = 0.0
        self._last_time = 0.0


class DaemonGraph(Gtk.DrawingArea):
    """Live CPU usage sparkline rendered with Cairo."""

    def __init__(self):
        super().__init__()
        self.set_hexpand(True)
        self.set_size_request(-1, 80)
        self.set_valign(Gtk.Align.FILL)
        self._stats = DaemonStats()
        self.set_draw_func(self._on_draw)
        self._timer = GLib.timeout_add(1000, self._tick)

    def _tick(self) -> bool:
        pid = self._get_pid()
        if pid > 0:
            self._stats.sample(pid)
        self.queue_draw()
        return True

    @staticmethod
    def _get_pid() -> int:
        try:
            with open(_PID_FILE) as f:
                return int(f.read().strip())
        except (FileNotFoundError, ValueError):
            return 0

    def stop(self) -> None:
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0

    def _on_draw(self, _da, cr, w, h) -> None:
        if w < 10 or h < 10:
            return

        pid = self._get_pid()
        if pid <= 0:
            self._draw_label(cr, w, h, "Daemon not running")
            return

        cpu = self._stats.cpu_pcts
        mem = self._stats.mem_kb
        n = len(cpu)
        if n < 2:
            self._draw_label(cr, w, h, "Collecting\u2026")
            return

        mx_cpu = self._stats.max_cpu()
        mx_mem = self._stats.max_mem()
        if mx_cpu < 0.01:
            mx_cpu = 1.0
        if mx_mem < 1:
            mx_mem = 1.0

        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        margin = 4
        plot_w = w - 2 * margin
        plot_h = (h - 2 * margin) / 2

        def scale_y(val, mx, top):
            return top + plot_h - (val / mx) * plot_h

        # CPU top half
        cpu_top = margin
        self._draw_line(cr, cpu, margin, plot_w,
                        lambda v, mx=mx_cpu, t=cpu_top: scale_y(v, mx, t),
                        Gdk.RGBA(0.3, 0.6, 1.0, 0.9))

        # Memory bottom half
        mem_top = margin + plot_h
        self._draw_line(cr, mem, margin, plot_w,
                        lambda v, mx=mx_mem, t=mem_top: scale_y(v, mx, t),
                        Gdk.RGBA(1.0, 0.65, 0.1, 0.9))

        # Labels
        cr.set_font_size(8)
        cr.set_source_rgba(0.5, 0.5, 0.5, 0.6)
        cur_cpu = cpu[-1]
        cur_mem = mem[-1] / 1024

        cr.move_to(margin + 2, cpu_top + 2)
        cr.show_text(f"CPU: {cur_cpu:.0f}%")
        cr.move_to(margin + 2, mem_top + 2)
        if cur_mem >= 1024:
            cr.show_text(f"RAM: {cur_mem / 1024:.1f} GB")
        else:
            cr.show_text(f"RAM: {cur_mem:.0f} MB")

    def _draw_label(self, cr, w, h, text: str) -> None:
        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)
        cr.set_source_rgba(0.5, 0.5, 0.5, 0.4)
        cr.set_font_size(10)
        cr.move_to(w / 2 - 40, h / 2)
        cr.show_text(text)

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


def _get_pid() -> int:
    try:
        with open(_PID_FILE) as f:
            return int(f.read().strip())
    except (FileNotFoundError, ValueError):
        return 0


def _is_running() -> bool:
    pid = _get_pid()
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _get_uptime() -> str:
    pid = _get_pid()
    if pid <= 0:
        return "N/A"
    try:
        r = subprocess.run(["ps", "-o", "etime=", "-p", str(pid)],
                           capture_output=True, text=True, timeout=3)
        return r.stdout.strip()
    except Exception:
        return "N/A"


def _list_watchers() -> list[dict]:
    watchers = []
    for path in sorted(glob.glob(os.path.join(_WATCHERS_DIR, "*.lua"))):
        name = os.path.basename(path).replace(".lua", "")
        interval = "?"
        try:
            with open(path) as f:
                content = f.read()
            m = re.search(r"interval\s*=\s*(\d+)", content)
            if m:
                interval = f"{m.group(1)}s"
        except OSError:
            pass
        disabled = os.path.exists(os.path.join(_LOG_DIR, f"watcher_{name}.disabled"))
        log_path = os.path.join(_LOG_DIR, f"watcher_{name}.log")
        log_lines = []
        if os.path.exists(log_path):
            try:
                with open(log_path) as f:
                    log_lines = f.read().strip().splitlines()[-10:]
            except OSError:
                pass
        watchers.append({
            "name": name,
            "interval": interval,
            "disabled": disabled,
            "log": log_lines,
        })
    return watchers


def _list_events() -> list[dict]:
    events = []
    events_dir = os.path.join(os.path.dirname(os.path.dirname(_DAEMON_SCRIPT)), "daemon", "events")
    for path in sorted(glob.glob(os.path.join(events_dir, "*.lua"))):
        module_name = os.path.basename(path).replace(".lua", "")
        try:
            with open(path) as f:
                content = f.read()
            for m in re.finditer(r"function\s+Events\.(\w+)", content):
                events.append({"event": m.group(1), "handler": module_name})
        except OSError:
            pass
    return events


class DaemonPage:
    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._dirty = False
        self._on_dirty_changed = None
        self._orig: dict[str, str] = {}
        self._pending: dict[str, str] = {}
        self._tick_source = None

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        # Daemon Overview
        sg = Adw.PreferencesGroup(title="Daemon Overview")
        self._build_status(sg)
        self._content_box.append(sg)

        # Event Watchers
        wg = Adw.PreferencesGroup(title="Event Watchers")
        self._build_watchers(wg)
        self._content_box.append(wg)

        # Events
        eg = Adw.PreferencesGroup(title="Available Events")
        self._build_events(eg)
        self._content_box.append(eg)

        self._tick_source = GLib.timeout_add(5000, self._tick)

        return toolbar_view

    def _build_status(self, group: Adw.PreferencesGroup) -> None:
        running = _is_running()
        pid = _get_pid()
        uptime = _get_uptime()

        state_text = "ACTIVE" if running else "INACTIVE"

        subtitle = f"PID: {pid}  |  Uptime: {uptime}" if running else "Daemon is stopped"

        row = Adw.ActionRow(title="Daemon Engine", subtitle=subtitle)

        badge = Gtk.Label(label=state_text)
        badge.add_css_class("badge")
        badge.set_valign(Gtk.Align.CENTER)
        if running:
            badge.add_css_class("success")
        else:
            badge.set_opacity(0.6)
        row.add_suffix(badge)
        self._state_badge = badge

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        btn_box.set_valign(Gtk.Align.CENTER)

        start_btn = Gtk.Button(label="Start")
        start_btn.set_sensitive(not running)
        start_btn.connect("clicked", lambda _b: self._daemon_action("start"))
        btn_box.append(start_btn)

        stop_btn = Gtk.Button(label="Stop")
        stop_btn.set_sensitive(running)
        stop_btn.connect("clicked", lambda _b: self._daemon_action("stop"))
        btn_box.append(stop_btn)

        restart_btn = Gtk.Button(label="Restart")
        restart_btn.connect("clicked", lambda _b: self._daemon_action("restart"))
        btn_box.append(restart_btn)

        row.add_suffix(btn_box)
        group.add(row)
        self._daemon_overview = row
        self._start_btn = start_btn
        self._stop_btn = stop_btn

        # CPU / Memory graph
        graph = DaemonGraph()
        graph_row = Adw.ActionRow()
        graph_row.set_activatable(False)
        graph_row.set_child(graph)
        group.add(graph_row)
        self._daemon_graph = graph

        # Log toggle
        try:
            from lib.python.variable import get_var
            log_enabled = get_var("RETRO_EVENT_LOG_ENABLED", "true") == "true"
        except Exception:
            log_enabled = True

        self._orig["log_enabled"] = "true" if log_enabled else "false"
        log_sw = Adw.SwitchRow(
            title="Generate Logs",
            subtitle="Write watcher activity to log files",
        )
        log_sw.set_active(log_enabled)
        log_sw.connect("notify::active", self._on_log_toggle)
        group.add(log_sw)

    def _on_log_toggle(self, sw: Adw.SwitchRow, _pspec) -> None:
        val = "true" if sw.get_active() else "false"
        self._pending["RETRO_EVENT_LOG_ENABLED"] = val
        self._dirty = self._pending != self._orig
        if self._on_dirty_changed:
            self._on_dirty_changed()

    def _daemon_action(self, action: str) -> None:
        subprocess.Popen(
            ["retro", "daemon", action],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        threading.Thread(target=lambda a=action: self._poll_status(a), daemon=True).start()

    def _poll_status(self, action: str) -> None:
        for _ in range(10):
            time.sleep(0.5)
            if (action == "stop" and not _is_running()) or \
               (action != "stop" and _is_running()):
                break
        GLib.idle_add(self._refresh_status)

    def _refresh_status(self) -> None:
        running = _is_running()
        pid = _get_pid()
        uptime = _get_uptime()

        state_text = "ACTIVE" if running else "INACTIVE"
        subtitle = f"PID: {pid}  |  Uptime: {uptime}" if running else "Daemon is stopped"
        if hasattr(self, "_daemon_overview"):
            self._daemon_overview.set_subtitle(subtitle)
        if hasattr(self, "_state_badge"):
            self._state_badge.set_label(state_text)
            if running:
                self._state_badge.add_css_class("success")
                self._state_badge.set_opacity(1.0)
            else:
                self._state_badge.remove_css_class("success")
                self._state_badge.set_opacity(0.6)
        self._start_btn.set_sensitive(not running)
        self._stop_btn.set_sensitive(running)

    def _build_watchers(self, group: Adw.PreferencesGroup) -> None:
        search_entry = Gtk.SearchEntry()
        search_entry.set_placeholder_text("Search watchers\u2026")
        search_entry.set_hexpand(True)

        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        search_box.append(search_entry)

        search_row = Adw.ActionRow(title="")
        search_row.set_activatable(False)
        search_row.set_child(search_box)
        group.add(search_row)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        listbox.add_css_class("boxed-list")

        watchers = _list_watchers()

        def rebuild(*_args):
            q = search_entry.get_text().lower().strip()
            while child := listbox.get_first_child():
                listbox.remove(child)

            for w in watchers:
                if q and q not in w["name"].lower():
                    continue

                display_name = w["name"][0].upper() + w["name"][1:] if w["name"] else w["name"]

                if w["disabled"]:
                    row = Adw.ActionRow(title=display_name, subtitle=f"Interval: {w['interval']} \u2014 DISABLED")
                    row.add_css_class("option-default")
                else:
                    row = Adw.ActionRow(title=display_name, subtitle=f"Interval: {w['interval']} \u2014 ACTIVE")
                    row.add_css_class("option-managed")

                power_sw = Gtk.Switch()
                power_sw.set_valign(Gtk.Align.CENTER)
                power_sw.set_active(not w["disabled"])
                power_sw.connect("notify::active", lambda _sw, _pspec, n=w["name"], d=w["disabled"]: self._toggle_watcher(n, _sw.get_active()))

                if w["log"]:
                    expander = Adw.ExpanderRow()
                    expander.set_title(display_name)
                    expander.set_subtitle(f"Interval: {w['interval']}  |  Logs: {len(w['log'])} lines")
                    expander.add_suffix(power_sw)

                    log_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
                    for line in w["log"]:
                        lbl = Gtk.Label(label=line)
                        lbl.set_halign(Gtk.Align.START)
                        lbl.add_css_class("caption")
                        lbl.set_margin_start(6)
                        lbl.set_margin_end(6)
                        lbl.set_margin_top(2)
                        lbl.set_margin_bottom(2)
                        log_box.append(lbl)

                    log_sw = Gtk.ScrolledWindow()
                    log_sw.set_child(log_box)
                    log_sw.set_min_content_height(80)
                    log_sw.set_vexpand(True)
                    log_row = Adw.ActionRow()
                    log_row.set_activatable(False)
                    log_row.set_child(log_sw)
                    expander.add_row(log_row)

                    listbox.append(expander)
                else:
                    row.add_suffix(power_sw)
                    listbox.append(row)

            if not listbox.get_first_child():
                empty_lbl = Gtk.Label(label="No watchers found")
                empty_lbl.set_margin_top(16)
                empty_lbl.set_margin_bottom(16)
                empty_lbl.set_halign(Gtk.Align.CENTER)
                empty_lbl.add_css_class("dim-label")
                r = Gtk.ListBoxRow()
                r.set_child(empty_lbl)
                listbox.append(r)

        search_entry.connect("search-changed", rebuild)
        rebuild()

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(listbox)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(250)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

    @staticmethod
    def _toggle_watcher(name: str, active: bool) -> None:
        disabled_file = os.path.join(_LOG_DIR, f"watcher_{name}.disabled")
        if active:
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

    def _build_events(self, group: Adw.PreferencesGroup) -> None:
        events = _list_events()
        seen: dict[str, list[str]] = {}
        for e in events:
            seen.setdefault(e["event"], []).append(e["handler"])

        search_entry = Gtk.SearchEntry()
        search_entry.set_placeholder_text("Search events\u2026")
        search_entry.set_hexpand(True)

        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        search_box.append(search_entry)

        search_row = Adw.ActionRow(title="")
        search_row.set_activatable(False)
        search_row.set_child(search_box)
        group.add(search_row)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        listbox.add_css_class("boxed-list")

        def rebuild(*_args):
            q = search_entry.get_text().lower().strip()
            while child := listbox.get_first_child():
                listbox.remove(child)

            for event, handlers in sorted(seen.items()):
                if q and q not in event.lower():
                    continue
                subtitle = " \u2192 ".join(handlers)
                row = Adw.ActionRow(title=event, subtitle=f"Handler(s): {subtitle}")
                listbox.append(row)

            if not listbox.get_first_child():
                empty_lbl = Gtk.Label(label="No events found")
                empty_lbl.set_margin_top(16)
                empty_lbl.set_margin_bottom(16)
                empty_lbl.set_halign(Gtk.Align.CENTER)
                empty_lbl.add_css_class("dim-label")
                r = Gtk.ListBoxRow()
                r.set_child(empty_lbl)
                listbox.append(r)

        search_entry.connect("search-changed", rebuild)
        rebuild()

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(listbox)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(200)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

    def _tick(self) -> bool:
        GLib.idle_add(self._refresh_status)
        return True

    # ── Save lifecycle ──

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        if not self._dirty and not self._pending:
            return
        try:
            from lib.python.variable import set_var
            for key, val in self._pending.items():
                set_var(key, val)
        except Exception:
            pass
        self._orig = dict(self._pending)
        self._pending.clear()
        self._dirty = False

    def discard(self) -> None:
        self._pending.clear()
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._dirty:
            yield PendingChange(
                category="Daemon",
                title="Daemon Configuration",
                subtitle="Daemon settings changed",
                navigate_to="daemon",
                icon=_DAEMON_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "daemon:status", "label": "Daemon Engine",
             "description": "Running state, PID, uptime, start/stop/restart",
             "_group_id": "daemon", "_group_label": "Daemon", "_section_label": "Status"},

            {"key": "daemon:watchers", "label": "Event Watchers",
             "description": "List of watchers with enable/disable and logs",
             "_group_id": "daemon", "_group_label": "Daemon", "_section_label": "Watchers"},
            {"key": "daemon:events", "label": "Available Events",
             "description": "All system events and their handlers",
             "_group_id": "daemon", "_group_label": "Daemon", "_section_label": "Events"},
        ]

    def destroy(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None
        if hasattr(self, "_daemon_graph"):
            self._daemon_graph.stop()
