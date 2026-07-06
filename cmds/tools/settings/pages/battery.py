"""Battery management page — status, saver, thresholds."""

import os
import subprocess
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gdk, GLib, Gtk, cairo

from settings.core.pending import PendingChange
from settings.ui import clear_children, make_page_layout
from settings.ui.row_actions import RowActions

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_BAT_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "battery_core.sh")
_BAT_ICON = "battery-symbolic"


def update_battery_sidebar(window) -> None:
    """Update the Battery sidebar row with charge percentage + LevelBar."""
    try:
        if not any(f.startswith("BAT") for f in os.listdir("/sys/class/power_supply/") if os.path.isdir("/sys/class/power_supply/")):
            return
        sidebar = getattr(window, "_sidebar", None)
        if sidebar is None:
            return
        row = sidebar._rows_by_id.get("battery")
        if row is None:
            return
        if not hasattr(row, "_bat_sidebar_bar"):
            bar = Gtk.LevelBar()
            bar.set_min_value(0)
            bar.set_max_value(100)
            bar.set_size_request(50, 6)
            bar.set_valign(Gtk.Align.CENTER)
            pct_lbl = Gtk.Label()
            pct_lbl.set_valign(Gtk.Align.CENTER)
            pct_lbl.add_css_class("caption")
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
            box.append(bar)
            box.append(pct_lbl)
            row.add_suffix(box)
            row._bat_sidebar_bar = bar
            row._bat_sidebar_pct = pct_lbl
        try:
            result = subprocess.run(["bash", _BAT_CORE, "--info"], capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
            parts = result.stdout.strip().split("|")
            cap = int(parts[0]) if len(parts) >= 1 and parts[0].isdigit() else 0
        except Exception:
            cap = 0
        row._bat_sidebar_bar.set_value(cap)
        row._bat_sidebar_bar.remove_css_class("level-bar-critical")
        row._bat_sidebar_bar.remove_css_class("level-bar-warning")
        if cap < 20:
            row._bat_sidebar_bar.add_css_class("level-bar-critical")
        elif cap < 40:
            row._bat_sidebar_bar.add_css_class("level-bar-warning")
        row._bat_sidebar_pct.set_label(f"{cap}%")
        row._bat_sidebar_pct.set_visible(True)
    except Exception:
        pass


class BatteryStatsGraph(Gtk.DrawingArea):
    """7-day battery usage bar chart drawn with Cairo."""

    def __init__(self):
        super().__init__()
        self.set_hexpand(True)
        self.set_size_request(-1, 100)
        self._data: list[dict] = []
        self._load_data()
        self.set_draw_func(self._on_draw)

    def _load_data(self) -> None:
        from lib.python.variable import get_var
        day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        self._data = []
        for i in range(6, -1, -1):
            raw = get_var(f"BAT_STATS_{i}", "")
            if raw and raw != "null":
                parts = raw.split("|")
                if len(parts) >= 3 and parts[0].count("-") == 2:
                    try:
                        from datetime import datetime
                        dt = datetime.strptime(parts[0], "%Y-%m-%d")
                        day = day_names[dt.weekday()]
                    except Exception:
                        day = "?"
                    cycles = int(parts[1]) if parts[1].isdigit() else 0
                    secs = int(parts[2]) if parts[2].isdigit() else 0
                    avg_min = (secs // cycles // 60) if cycles > 0 else 0
                    self._data.append({"day": day, "cycles": cycles, "avg_min": avg_min})
                else:
                    self._data.append({"day": "?", "cycles": 0, "avg_min": 0})
            else:
                self._data.append({"day": "?", "cycles": 0, "avg_min": 0})

    def _on_draw(self, _da, cr: cairo.Context, w: int, h: int) -> None:
        if w < 20 or h < 10:
            return
        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        n = len(self._data)
        if n == 0:
            return

        margin_b = 22
        margin_t = 16
        margin_l = 6
        margin_r = 6
        bar_area_h = h - margin_b - margin_t
        bar_w = max(4, (w - margin_l - margin_r) / n - 4)
        max_m = max(d["avg_min"] for d in self._data) if self._data else 1
        if max_m < 1:
            max_m = 1

        cr.set_font_size(8)

        # Resolve accent color
        _, accent = self.get_style_context().lookup_color("accent_bg_color")
        bar_color = (accent.red, accent.green, accent.blue, 0.85)

        for i, d in enumerate(self._data):
            x = margin_l + i * ((w - margin_l - margin_r) / n) + 2
            bar_h = (d["avg_min"] / max_m) * bar_area_h if max_m > 0 else 0

            # Bar
            if d["cycles"] > 0:
                cr.set_source_rgba(*bar_color)
            else:
                cr.set_source_rgba(0.5, 0.5, 0.5, 0.3)
            if bar_h > 1:
                cr.rectangle(x, margin_t + bar_area_h - bar_h, bar_w, bar_h)
                cr.fill()

            # Avg label above bar
            if d["avg_min"] > 0:
                text = f"{d['avg_min']}m"
                if d["avg_min"] >= 120:
                    text = f"{d['avg_min'] // 60}h {d['avg_min'] % 60}m"
                cr.set_source_rgba(0.8, 0.8, 0.8, 0.8)
                cr.move_to(x + bar_w / 2 - 6, margin_t + bar_area_h - bar_h - 3)
                cr.show_text(text)

            # Day label
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.6)
            cr.move_to(x + bar_w / 2 - 6, h - 4)
            cr.show_text(d["day"])


class BatteryPage:
    """Battery management — status, saver, thresholds."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._refreshable_box: Gtk.Box
        self._dirty = False
        self._on_dirty_changed = None
        self._orig: dict[str, str] = {}
        self._status: dict[str, str] = {}
        self._pending: dict[str, str] = {}
        self._setting_value = False

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)
        self._refreshable_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self._content_box.append(self._refreshable_box)
        self._load_data()
        self._rebuild_refreshable()
        return toolbar_view

    def _load_data(self) -> None:
        from lib.python.variable import get_var

        def _sysfs(name):
            try:
                for p in ("/sys/class/power_supply/BAT0", "/sys/class/power_supply/BAT1"):
                    with open(f"{p}/{name}") as f:
                        return f.read().strip()
            except Exception:
                return "N/A"

        def _uevent_serial():
            try:
                for p in ("/sys/class/power_supply/BAT0/uevent", "/sys/class/power_supply/BAT1/uevent"):
                    with open(p) as f:
                        for line in f:
                            val = line.strip().split("=", 1)
                            if len(val) == 2 and val[0] == "POWER_SUPPLY_SERIAL_NUMBER" and val[1] not in ("", "SerialNumber"):
                                return val[1]
                return ""
            except Exception:
                return ""

        self._status = {
            "manufacturer": _sysfs("manufacturer"),
            "technology": _sysfs("technology"),
            "cycles": _sysfs("cycle_count"),
            "serial": _uevent_serial(),
        }
        try:
            r = subprocess.run(["bash", _BAT_CORE, "--info"], capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
            parts = r.stdout.strip().split("|")
            if len(parts) >= 7:
                self._status.update({
                    "cap": parts[0], "stat": parts[1], "health": parts[2],
                    "power": f"{float(parts[3]) / 1000000:.2f} W" if parts[3].isdigit() else "?",
                    "volt": f"{float(parts[4]) / 1000000:.2f} V" if parts[4].isdigit() else "?",
                    "model": parts[5], "saver": parts[6],
                    "sot": parts[7] if len(parts) > 7 else "N/A",
                    "estimate": parts[8] if len(parts) > 8 else "N/A",
                })
        except Exception:
            pass

        self._orig = {
            "threshold": get_var("BAT_SAVER_THRESHOLD") or "50",
            "critical": get_var("BAT_NOTIFY_CRITICAL_THRESHOLD") or "15",
            "notify": get_var("BAT_NOTIFY_THRESHOLD") or "30",
            "on_pwr_dis": get_var("BAT_SAVER_ON_PWR_DIS") or "true",
        }

    def _rebuild_refreshable(self) -> None:
        clear_children(self._refreshable_box)
        s = self._status

        # Usage graph (first)
        ug = Adw.PreferencesGroup(title="Usage (Last 7 Days)")
        graph = BatteryStatsGraph()
        graph_row = Adw.ActionRow(title="")
        graph_row.set_activatable(False)
        graph_row.set_child(graph)
        ug.add(graph_row)
        self._refreshable_box.append(ug)

        # Status
        sg = Adw.PreferencesGroup(title="Status")

        # Charge bar (first)
        cap_str = s.get("cap", "0")
        try:
            cap_int = int(cap_str)
        except ValueError:
            cap_int = 0
        bar = Gtk.LevelBar()
        bar.set_min_value(0)
        bar.set_max_value(100)
        bar.set_value(cap_int)
        bar.set_size_request(200, 8)
        if cap_int < 20:
            bar.add_css_class("level-bar-critical")
        elif cap_int < 40:
            bar.add_css_class("level-bar-warning")
        pct_lbl = Gtk.Label(label=f"{cap_int}%")
        pct_lbl.set_valign(Gtk.Align.CENTER)
        pct_lbl.set_margin_start(6)
        bar_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        bar_box.set_halign(Gtk.Align.END)
        bar_box.append(bar)
        bar_box.append(pct_lbl)
        bar_row = Adw.ActionRow(title="Charge")
        bar_row.add_suffix(bar_box)
        sg.add(bar_row)

        model_str = s.get("model", "?")
        mfr = s.get("manufacturer", "?")
        if mfr not in ("?", "N/A", model_str):
            model_str += f"  ({mfr})"
        sg.add(self._info_row("Model", model_str))

        parts = []
        parts.append(s.get("stat", "?"))
        h = s.get("health", "?")
        if h not in ("?", "N/A"):
            parts.append(h.capitalize())
        sv = s.get("saver", "").upper()
        if sv in ("ON", "OFF"):
            parts.append(f"Saver {sv}")
        sg.add(self._info_row("Status", "  ·  ".join(parts)))

        pwr_parts = []
        pw = s.get("power", "")
        if pw and pw != "?":
            pwr_parts.append(pw)
        pv = s.get("volt", "")
        if pv and pv != "?":
            pwr_parts.append(pv)
        cy = s.get("cycles", "N/A")
        if cy not in ("N/A", "0", ""):
            pwr_parts.append(f"{cy} cycles")
        sg.add(self._info_row("Power", "  ·  ".join(pwr_parts) if pwr_parts else "?"))

        extra = []
        if s.get("sot") and s["sot"] not in ("N/A", ""):
            extra.append(f"On battery: {s['sot']}")
        if s.get("estimate") and s["estimate"] not in ("N/A", ""):
            extra.append(f"{s['estimate']}")
        ser = s.get("serial", "")
        if ser:
            extra.append(f"SN: {ser}")
        if extra:
            sg.add(self._info_row("Details", "  ·  ".join(extra)))

        self._refreshable_box.append(sg)

        # Configuration group
        cg = Adw.PreferencesGroup(title="Configuration")

        self._config_rows: list[tuple] = []

        adj = Gtk.Adjustment(value=float(self._orig["notify"]), lower=5, upper=50, step_increment=1, page_increment=5)
        ns = Gtk.SpinButton(adjustment=adj, digits=0)
        ns.set_valign(Gtk.Align.CENTER)
        ns.connect("notify::value", self._on_spin_changed, "notify")
        nwl = Gtk.Label(label="%"); nwl.set_valign(Gtk.Align.CENTER); nwl.set_opacity(0.7); nwl.set_margin_start(4)
        nr = Adw.ActionRow(title="Low battery warning", subtitle="Show notification below this percentage")
        nr.add_suffix(nwl); nr.add_suffix(ns); cg.add(nr)
        self._spin_notify = ns
        na = RowActions(nr, on_discard=lambda: self._discard_row("BAT_NOTIFY_THRESHOLD", "notify"),
                        on_reset=lambda: self._reset_row("BAT_NOTIFY_THRESHOLD", "notify"))
        nr.add_suffix(na.box)
        na.reorder_first()
        self._config_rows.append(("BAT_NOTIFY_THRESHOLD", "notify", ns, na))

        adj = Gtk.Adjustment(value=float(self._orig["critical"]), lower=5, upper=50, step_increment=1, page_increment=5)
        cs = Gtk.SpinButton(adjustment=adj, digits=0)
        cs.set_valign(Gtk.Align.CENTER)
        cs.connect("notify::value", self._on_spin_changed, "critical")
        cwl = Gtk.Label(label="%"); cwl.set_valign(Gtk.Align.CENTER); cwl.set_opacity(0.7); cwl.set_margin_start(4)
        cr = Adw.ActionRow(title="Critical battery warning", subtitle="Critical notification below this percentage")
        cr.add_suffix(cwl); cr.add_suffix(cs); cg.add(cr)
        self._spin_critical = cs
        ca = RowActions(cr, on_discard=lambda: self._discard_row("BAT_NOTIFY_CRITICAL_THRESHOLD", "critical"),
                        on_reset=lambda: self._reset_row("BAT_NOTIFY_CRITICAL_THRESHOLD", "critical"))
        cr.add_suffix(ca.box)
        ca.reorder_first()
        self._config_rows.append(("BAT_NOTIFY_CRITICAL_THRESHOLD", "critical", cs, ca))

        adj = Gtk.Adjustment(value=float(self._orig["threshold"]), lower=0, upper=100, step_increment=1, page_increment=5)
        ts = Gtk.SpinButton(adjustment=adj, digits=0)
        ts.set_valign(Gtk.Align.CENTER)
        ts.connect("notify::value", self._on_spin_changed, "threshold")
        twl = Gtk.Label(label="%"); twl.set_valign(Gtk.Align.CENTER); twl.set_opacity(0.7); twl.set_margin_start(4)
        tr = Adw.ActionRow(title="Auto saver threshold", subtitle="Enable battery saver below this charge level")
        tr.add_suffix(twl); tr.add_suffix(ts); cg.add(tr)
        self._spin_threshold = ts
        ta = RowActions(tr, on_discard=lambda: self._discard_row("BAT_SAVER_THRESHOLD", "threshold"),
                        on_reset=lambda: self._reset_row("BAT_SAVER_THRESHOLD", "threshold"))
        tr.add_suffix(ta.box)
        ta.reorder_first()
        self._config_rows.append(("BAT_SAVER_THRESHOLD", "threshold", ts, ta))

        sr = Adw.SwitchRow(
            title="Enable saver on power disconnect",
            subtitle="Auto-enable battery saver when disconnected from AC power",
        )
        sr.set_active(self._orig.get("on_pwr_dis") == "true")
        sr.connect("notify::active", self._on_switch_changed)
        cg.add(sr)
        self._switch_on_pwr_dis = sr
        sa = RowActions(sr, on_discard=lambda: self._discard_row("BAT_SAVER_ON_PWR_DIS", "on_pwr_dis"),
                        on_reset=lambda: self._reset_row("BAT_SAVER_ON_PWR_DIS", "on_pwr_dis"))
        sr.add_suffix(sa.box)
        sa.reorder_first()
        self._config_rows.append(("BAT_SAVER_ON_PWR_DIS", "on_pwr_dis", sr, sa))

        self._refreshable_box.append(cg)
        GLib.idle_add(self._refresh_managed)

    # ── Managed indicators ──

    def _get_val(self, var: str, key: str) -> str:
        if key == "on_pwr_dis":
            return "true" if self._switch_on_pwr_dis.get_active() else "false"
        return str(int(getattr(self, f"_spin_{key}").get_value()))

    def _refresh_managed(self) -> None:
        from lib.python.variable import get_var as _g
        from lib.python.variable import get_module_default as _md
        for var, key, widget, actions in self._config_rows:
            cur = self._get_val(var, key)
            live = _g(var, "")
            default = _md(var) or live
            is_managed = cur != default
            is_dirty = cur != live
            is_saved = live != default
            actions.update(is_managed=is_managed, is_dirty=is_dirty, is_saved=is_saved)

    def _discard_row(self, var: str, key: str) -> None:
        from lib.python.variable import get_var as _g
        live = _g(var, "")
        self._set_widget(key, live)
        self._pending.pop(var, None)
        self._check_dirty()
        self._refresh_managed()

    def _reset_row(self, var: str, key: str) -> None:
        from lib.python.variable import get_module_default as _md
        default = _md(var)
        if default:
            self._set_widget(key, default)
            self._pending[var] = default
            self._dirty = True
            if self._on_dirty_changed:
                self._on_dirty_changed()
        self._refresh_managed()

    def _set_widget(self, key: str, val: str) -> None:
        self._setting_value = True
        if key == "on_pwr_dis":
            self._switch_on_pwr_dis.set_active(val == "true")
        else:
            try:
                getattr(self, f"_spin_{key}").set_value(float(val))
            except (ValueError, AttributeError):
                pass
        self._setting_value = False

    # ── Change handlers ──

    def _on_spin_changed(self, spin: Gtk.SpinButton, _pspec, key: str) -> None:
        if self._setting_value:
            return
        var_map = {"notify": "BAT_NOTIFY_THRESHOLD", "critical": "BAT_NOTIFY_CRITICAL_THRESHOLD", "threshold": "BAT_SAVER_THRESHOLD"}
        self._pending[var_map.get(key, key)] = str(int(spin.get_value()))
        GLib.idle_add(self._check_dirty)
        GLib.idle_add(self._refresh_managed)

    def _on_switch_changed(self, sw: Adw.SwitchRow, _pspec) -> None:
        if self._setting_value:
            return
        self._pending["BAT_SAVER_ON_PWR_DIS"] = "true" if sw.get_active() else "false"
        GLib.idle_add(self._check_dirty)
        GLib.idle_add(self._refresh_managed)

    def _check_dirty(self) -> None:
        was = self._dirty
        self._dirty = any(
            str(int(getattr(self, f"_spin_{key}").get_value())) != self._orig.get(key, "")
            for key in ("threshold", "critical", "notify")
            if hasattr(self, f"_spin_{key}")
        )
        if (self._switch_on_pwr_dis.get_active() == True) != (self._orig.get("on_pwr_dis") == "true"):
            self._dirty = True
        if was != self._dirty and self._on_dirty_changed:
            self._on_dirty_changed()

    # ── Save lifecycle ──

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        if not self._dirty and not self._pending:
            return
        from lib.python.variable import set_var
        for var, val in self._pending.items():
            set_var(var, val)
        self._pending.clear()
        self._orig = {
            "threshold": str(int(self._spin_threshold.get_value())),
            "critical": str(int(self._spin_critical.get_value())),
            "notify": str(int(self._spin_notify.get_value())),
            "on_pwr_dis": "true" if self._switch_on_pwr_dis.get_active() else "false",
        }
        self._dirty = False
        self._refresh_managed()

    def discard(self) -> None:
        for key in ("threshold", "critical", "notify"):
            if hasattr(self, f"_spin_{key}"):
                getattr(self, f"_spin_{key}").set_value(float(self._orig.get(key, "50")))
        self._switch_on_pwr_dis.set_active(self._orig.get("on_pwr_dis") == "true")
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._dirty:
            yield PendingChange(
                category="Battery",
                title="Battery Configuration",
                subtitle="Saver threshold or notification levels changed",
                navigate_to="battery",
                icon=_BAT_ICON,
                kind="modified",
                revert=self.discard,
            )

    # ── Helpers ──

    @staticmethod
    def _info_row(title: str, content: str) -> Adw.ActionRow:
        row = Adw.ActionRow(title=title)
        lbl = Gtk.Label(label=content)
        lbl.set_halign(Gtk.Align.END)
        lbl.set_opacity(0.8)
        row.add_suffix(lbl)
        return row

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "battery:status", "label": "Battery Status",
             "description": "Charge, model, health, power, voltage, saver, estimate",
             "_group_id": "battery", "_group_label": "Battery", "_section_label": "Status"},
            {"key": "battery:config", "label": "Battery Configuration",
             "description": "Saver threshold, low battery and critical notifications",
             "_group_id": "battery", "_group_label": "Battery", "_section_label": "Configuration"},
        ]
