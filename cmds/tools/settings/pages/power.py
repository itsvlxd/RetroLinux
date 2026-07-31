"""Power management page — profiles, wattage limits, auto-optimize."""

import os
import subprocess
import time
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GdkPixbuf, GLib, Gtk, cairo

from settings.core.pending import PendingChange
from settings.ui import clear_children, make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_PWR_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "power_core.sh")
_SYS_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "system_core.sh")
_DRIVER_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "driver_core.sh")
_BRAND_DIR = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "assets", "brands")
_PWR_ICON = "preferences-system-power-symbolic"
_PROFILES = ["performance", "balanced", "saver"]


def _restore() -> None:
    subprocess.Popen(
        ["retro", "power", "restore"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


class SystemUsageStats:
    """Reads CPU%, RAM%, GPU% and temps from /proc and /sys."""

    def __init__(self) -> None:
        self._cpu_prev: tuple[int, int] = (0, 0)
        self._last_time = 0.0
        self.cpu_pcts: list[float] = []
        self.ram_pcts: list[float] = []
        self.gpu_pcts: list[float] = []
        self.cpu_temps: list[float] = []
        self.gpu_temps: list[float] = []
        self._max_samples = 60

    def _read_cpu(self) -> float:
        try:
            with open("/proc/stat") as f:
                parts = f.readline().strip().split()
            idle = int(parts[4]) + int(parts[5])
            total = sum(int(x) for x in parts[1:])
            prev_idle, prev_total = self._cpu_prev
            if prev_total > 0:
                idle_delta = idle - prev_idle
                total_delta = total - prev_total
                pct = 100 * (1 - idle_delta / total_delta) if total_delta > 0 else 0
            else:
                pct = 0
            self._cpu_prev = (idle, total)
            return max(0, min(100, pct))
        except Exception:
            return 0

    def _read_ram(self) -> float:
        try:
            with open("/proc/meminfo") as f:
                data = {}
                for line in f:
                    if ":" in line:
                        k, v = line.split(":", 1)
                        data[k] = int(v.strip().split()[0])
            used = data.get("MemTotal", 1) - data.get("MemAvailable", data.get("MemFree", 0))
            return (used / data.get("MemTotal", 1)) * 100 if data.get("MemTotal", 1) > 0 else 0
        except Exception:
            return 0

    def _read_gpu_usage(self) -> float:
        try:
            for d in os.listdir("/sys/class/drm/"):
                if not d.startswith("card"):
                    continue
                p = f"/sys/class/drm/{d}/device/gpu_busy_percent"
                if os.path.isfile(p):
                    return float(open(p).read().strip())
                # Intel xe / i915: compute from frequency ratio
                for gt_dir in (f"/sys/class/drm/{d}/gt",):
                    if not os.path.isdir(gt_dir):
                        break
                    for gt in os.listdir(gt_dir):
                        act_f = f"{gt_dir}/{gt}/rps_act_freq_mhz"
                        max_f = f"{gt_dir}/{gt}/rps_max_freq_mhz"
                        if os.path.isfile(act_f) and os.path.isfile(max_f):
                            act = int(open(act_f).read().strip())
                            mx = int(open(max_f).read().strip())
                            return (act / mx) * 100 if mx > 0 else 0
            return 0
        except Exception:
            return 0

    def _read_cpu_temp(self) -> float:
        try:
            for z in sorted(os.listdir("/sys/class/thermal/")):
                if not z.startswith("thermal_zone"):
                    continue
                path = f"/sys/class/thermal/{z}"
                ttype = open(f"{path}/type").read().strip()
                if ttype in ("x86_pkg_temp", "cpu-thermal"):
                    return int(open(f"{path}/temp").read().strip()) / 1000
            return 0
        except Exception:
            return 0

    def _read_gpu_temp(self) -> float:
        try:
            for d in os.listdir("/sys/class/drm/"):
                if d.startswith("card"):
                    hwmon = f"/sys/class/drm/{d}/device/hwmon"
                    if os.path.isdir(hwmon):
                        for hm in os.listdir(hwmon):
                            p = f"{hwmon}/{hm}/temp1_input"
                            if os.path.isfile(p):
                                return int(open(p).read().strip()) / 1000
            return 0
        except Exception:
            return 0

    def sample(self) -> None:
        self.cpu_pcts.append(self._read_cpu())
        self.ram_pcts.append(self._read_ram())
        self.gpu_pcts.append(self._read_gpu_usage())
        self.cpu_temps.append(self._read_cpu_temp())
        self.gpu_temps.append(self._read_gpu_temp())
        for lst in (self.cpu_pcts, self.ram_pcts, self.gpu_pcts, self.cpu_temps, self.gpu_temps):
            if len(lst) > self._max_samples:
                lst.pop(0)

    def max_val(self) -> float:
        all_vals = self.cpu_pcts + self.ram_pcts + self.gpu_pcts + self.cpu_temps + self.gpu_temps
        return max(all_vals) if all_vals else 100.0


class SystemUsageGraph(Gtk.DrawingArea):
    """Live CPU/GPU/RAM usage sparkline — single plot, legend on side."""

    def __init__(self) -> None:
        super().__init__()
        self.set_hexpand(True)
        self.set_size_request(-1, 160)
        self.set_valign(Gtk.Align.FILL)

        self._stats = SystemUsageStats()
        self.set_draw_func(self._on_draw)
        self._timer = GLib.timeout_add(1000, self._tick)
        self._stats.sample()

    def _tick(self) -> bool:
        self._stats.sample()
        self.queue_draw()
        return True

    def _on_draw(self, _da, cr, w, h) -> None:
        if w < 10 or h < 10:
            return
        st = self._stats
        if len(st.cpu_pcts) < 2:
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.4)
            cr.set_font_size(10)
            cr.move_to(w / 2 - 30, h / 2)
            cr.show_text("Collecting…")
            return

        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        has_gpu_temp = bool(st.gpu_temps and any(v > 0 for v in st.gpu_temps[-5:]))

        lines = [
            (st.cpu_pcts, (0.3, 0.6, 1.0, 0.9), "CPU", "%"),
            (st.cpu_temps, (1.0, 0.65, 0.1, 0.9), "CPU°", "°C"),
            (st.gpu_pcts, (0.2, 1.0, 0.5, 0.9), "GPU", "%"),
        ]
        if has_gpu_temp:
            lines.append((st.gpu_temps, (0.2, 0.8, 0.8, 0.9), "GPU°", "°C"))
        lines.append((st.ram_pcts, (1.0, 0.33, 0.7, 0.9), "RAM", "%"))

        all_vals = [v for data, _, _, _ in lines for v in data if len(data) > 1]
        mx = max(all_vals) if all_vals else 100.0
        if mx < 1.0:
            mx = 1.0

        margin_t, margin_b = 8, 16
        margin_l, margin_r = 8, 100
        plot_w = w - margin_l - margin_r
        plot_h = h - margin_t - margin_b
        if plot_w <= 0 or plot_h <= 0:
            return

        def sc_y(v):
            return margin_t + plot_h - (v / mx) * plot_h

        # Draw all lines on the same plot
        for data, color, _label, _unit in lines:
            n = len(data)
            if n < 2:
                continue
            step = plot_w / (n - 1)
            cr.set_source_rgba(*color)
            cr.set_line_width(1.2)
            cr.set_line_cap(1)
            cr.move_to(margin_l, sc_y(data[0]))
            for i in range(1, n):
                cr.line_to(margin_l + i * step, sc_y(data[i]))
            cr.stroke()

        # Legend on the right side
        cr.set_font_size(9)
        y_pos = margin_t + 4
        for _, color, label, unit in lines:
            data = getattr(st, {
                "CPU": "cpu_pcts", "CPU°": "cpu_temps",
                "GPU": "gpu_pcts", "GPU°": "gpu_temps", "RAM": "ram_pcts",
            }[label])
            val = data[-1] if data else 0
            cr.set_source_rgba(*color)
            cr.move_to(w - margin_r + 4, y_pos)
            cr.show_text(f"{label}: {val:.0f}{unit}")
            y_pos += 16


class PowerPage:
    """Power management — profile, limits, and auto-optimize."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._dirty = False
        self._on_dirty_changed = None
        self._orig: dict[str, str] = {}
        self._spin_rows: dict[str, Gtk.SpinButton] = {}
        self._pwr_btn_row: Adw.ComboRow | None = None
        self._pwr_btn_long_row: Adw.ComboRow | None = None
        self._lid_row: Adw.ComboRow | None = None
        self._has_hibernate = False
        self._check_hibernate()

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)
        self._load_data()

        # Combined hero + usage graph card
        cpu_model = self._get_cpu_model()
        gpu_model = self._get_gpu_model()

        usage_group = Adw.PreferencesGroup(title="System")
        hero = self._make_hero_row(cpu_model, gpu_model)
        if hero is not None:
            usage_group.add(hero)

        graph = SystemUsageGraph()
        graph_row = Adw.ActionRow(title="")
        graph_row.set_activatable(False)
        graph_row.set_child(graph)
        usage_group.add(graph_row)
        self._content_box.append(usage_group)

        group = Adw.PreferencesGroup(title="Power Configuration")

        # Profile dropdown
        from settings.ui.managed_row import make_combo_row
        model = Gtk.StringList.new([p.capitalize() for p in _PROFILES])
        cur = self._orig.get("profile", "balanced")
        idx = _PROFILES.index(cur) if cur in _PROFILES else 1
        cr = make_combo_row("Active Profile", subtitle="Switch between Performance, Balanced, or Power Saver", model=model, selected=idx)
        cr.connect("notify::selected", self._on_profile_changed)
        self._profile_row = cr
        group.add(cr)

        # AC + BAT limits as SpinRows
        for label, desc, var, key in [
            ("AC Saver", "AC power limit for power-saver mode", "PWR_AC_SAVER", "ac_saver"),
            ("AC Balanced", "AC power limit for balanced mode", "PWR_AC_BALANCED", "ac_balanced"),
            ("AC Performance", "AC power limit for maximum performance mode", "PWR_AC_PERFORMANCE", "ac_performance"),
            ("BAT Saver", "Battery power limit for power-saver mode", "PWR_BAT_SAVER", "bat_saver"),
            ("BAT Balanced", "Battery power limit for balanced mode", "PWR_BAT_BALANCED", "bat_balanced"),
            ("BAT Performance", "Battery power limit for maximum performance mode", "PWR_BAT_PERFORMANCE", "bat_performance"),
        ]:
            val = int(self._orig.get(key, "15")) if self._orig.get(key, "").isdigit() else 15
            adj = Gtk.Adjustment(value=val, lower=1, upper=200, step_increment=1, page_increment=5)
            row = Adw.ActionRow(title=label, subtitle=desc)
            spin = Gtk.SpinButton(adjustment=adj, digits=0)
            spin.set_valign(Gtk.Align.CENTER)
            wl = Gtk.Label(label="W")
            wl.set_valign(Gtk.Align.CENTER)
            wl.set_opacity(0.7)
            wl.set_margin_start(4)
            spin.connect("notify::value", self._on_spin_changed, key)
            row.add_suffix(wl)
            row.add_suffix(spin)
            group.add(row)
            self._spin_rows[key] = spin

        # Optimize
        opt_row = Adw.ActionRow(
            title="Auto-optimize",
            subtitle="Detects your CPU model and applies recommended wattage limits from the RetroLinux database",
        )
        opt_btn = Gtk.Button(label="Optimize")
        opt_btn.set_valign(Gtk.Align.CENTER)
        opt_btn.add_css_class("suggested-action")
        opt_btn.connect("clicked", lambda _b: self._run_optimize())
        opt_row.add_suffix(opt_btn)
        group.add(opt_row)

        self._content_box.append(group)

        # ── Hardware Buttons ──────────────────────────────────────────
        btn_group = Adw.PreferencesGroup(title="Hardware Buttons")
        btn_group.set_description(
            "What happens when you press the power button, hold it, or "
            "close the laptop lid. Changes are applied via systemd-logind "
            "and require a restart to take full effect."
        )

        from settings.ui.managed_row import make_combo_row

        def _make_logind_combo(var: str, title: str, subtitle: str) -> Adw.ComboRow:
            actions, labels = self._get_logind_options()
            val = self._orig.get(var, "suspend")
            if val not in actions:
                val = "suspend"
            try:
                idx = actions.index(val)
            except ValueError:
                idx = 0
            model = Gtk.StringList.new(labels)
            row = make_combo_row(title, subtitle=subtitle, model=model, selected=idx)
            row.connect("notify::selected", self._on_logind_changed, var)
            return row

        self._pwr_btn_row = _make_logind_combo(
            "pwr_btn", "Power Button",
            "Action when the power button is pressed briefly",
        )
        btn_group.add(self._pwr_btn_row)

        self._pwr_btn_long_row = _make_logind_combo(
            "pwr_btn_long", "Power Button Long Press",
            "Action when the power button is held for 5+ seconds",
        )
        btn_group.add(self._pwr_btn_long_row)

        self._lid_row = _make_logind_combo(
            "lid_close", "Lid Close",
            "Action when the laptop lid is closed",
        )
        btn_group.add(self._lid_row)

        self._content_box.append(btn_group)
        return toolbar_view

    def _check_hibernate(self) -> None:
        try:
            r = subprocess.run(
                ["bash", _SYS_CORE, "--hibernate-available"],
                capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL,
            )
            self._has_hibernate = "available" in r.stdout
        except Exception:
            self._has_hibernate = False

    def _get_cpu_model(self) -> str:
        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("model name"):
                        m = line.split(":", 1)[1].strip()
                        m = m.replace("(R)", "").replace("(TM)", "").replace("(r)", "").replace("(tm)", "")
                        m = m.replace("  ", " ").strip()
                        return m
        except Exception:
            return ""
        return ""

    def _get_cpu_info(self) -> dict[str, int]:
        info = {"cores": 0, "threads": 0}
        try:
            cores = set()
            threads = 0
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("core id"):
                        cores.add(int(line.split(":")[1].strip()))
                    if line.startswith("processor"):
                        threads += 1
            info["cores"] = len(cores)
            info["threads"] = threads
        except Exception:
            pass
        return info

    def _get_gpu_model(self) -> str:
        try:
            r = subprocess.run(["lspci"], capture_output=True, text=True, timeout=5)
            for line in r.stdout.splitlines():
                if "VGA" in line or "3D" in line or "Display" in line:
                    m = ":".join(line.split(":")[1:]).strip()
                    if "[" in m and "]" in m:
                        inner = m[m.index("[") + 1:m.index("]")]
                        return inner
                    m = m.split(" [")[0]
                    for pfx in ("Intel Corporation ", "Advanced Micro Devices, Inc. ", "NVIDIA Corporation "):
                        if m.startswith(pfx):
                            m = m[len(pfx):]
                            break
                    return m.strip()
        except Exception:
            return ""
        return ""

    def _resolve_brand_path(self, vendor: str, component: str, model: str = "") -> str | None:
        if vendor == "intel":
            if component == "gpu":
                if any(k in model for k in ("Arc", "Meteor", "Lunar", "Battlemage")):
                    return os.path.join(_BRAND_DIR, "intel-arc.png")
                return os.path.join(_BRAND_DIR, "intel-core.png")
            return os.path.join(_BRAND_DIR, "intel-core.png")
        if vendor == "nvidia":
            return os.path.join(_BRAND_DIR, "nvidia-rtx.png") if "RTX" in model else os.path.join(_BRAND_DIR, "nvidia-gtx.png")
        if vendor == "amd":
            if component == "gpu" and "Radeon" in model:
                return os.path.join(_BRAND_DIR, "amd-radeon.png")
            return os.path.join(_BRAND_DIR, "amd.png")
        return None

    def _make_hero_row(self, cpu_model: str, gpu_model: str) -> Adw.ActionRow | None:
        if not cpu_model and not gpu_model:
            return None

        cpu_info = self._get_cpu_info()
        title = cpu_model or "System"
        subtitle_parts = []
        if gpu_model:
            subtitle_parts.append(gpu_model)
        if cpu_info["cores"] > 0:
            subtitle_parts.append(f"{cpu_info['cores']}C / {cpu_info['threads']}T")
        subtitle = " · ".join(subtitle_parts) if subtitle_parts else ""

        row = Adw.ActionRow(title=title, subtitle=subtitle)
        row.set_activatable(False)
        return row

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)
        self._load_data()

        # Combined hero + usage graph card
        cpu_model = self._get_cpu_model()
        gpu_model = self._get_gpu_model()
        usage_group = Adw.PreferencesGroup(title="System")
        hero = self._make_hero_row(cpu_model, gpu_model)
        if hero is not None:
            usage_group.add(hero)
        graph = SystemUsageGraph()
        graph_row = Adw.ActionRow(title="")
        graph_row.set_activatable(False)
        graph_row.set_child(graph)
        usage_group.add(graph_row)
        self._content_box.append(usage_group)

        group = Adw.PreferencesGroup(title="Power Configuration")

        # Profile dropdown
        from settings.ui.managed_row import make_combo_row
        model = Gtk.StringList.new([p.capitalize() for p in _PROFILES])
        cur = self._orig.get("profile", "balanced")
        idx = _PROFILES.index(cur) if cur in _PROFILES else 1
        cr = make_combo_row("Active Profile", subtitle="Switch between Performance, Balanced, or Power Saver", model=model, selected=idx)
        cr.connect("notify::selected", self._on_profile_changed)
        self._profile_row = cr
        group.add(cr)

        for label, desc, var, key in [
            ("AC Saver", "AC power limit for power-saver mode", "PWR_AC_SAVER", "ac_saver"),
            ("AC Balanced", "AC power limit for balanced mode", "PWR_AC_BALANCED", "ac_balanced"),
            ("AC Performance", "AC power limit for maximum performance mode", "PWR_AC_PERFORMANCE", "ac_performance"),
            ("BAT Saver", "Battery power limit for power-saver mode", "PWR_BAT_SAVER", "bat_saver"),
            ("BAT Balanced", "Battery power limit for balanced mode", "PWR_BAT_BALANCED", "bat_balanced"),
            ("BAT Performance", "Battery power limit for maximum performance mode", "PWR_BAT_PERFORMANCE", "bat_performance"),
        ]:
            val = int(self._orig.get(key, "15")) if self._orig.get(key, "").isdigit() else 15
            adj = Gtk.Adjustment(value=val, lower=1, upper=200, step_increment=1, page_increment=5)
            row = Adw.ActionRow(title=label, subtitle=desc)
            spin = Gtk.SpinButton(adjustment=adj, digits=0)
            spin.set_valign(Gtk.Align.CENTER)
            wl = Gtk.Label(label="W")
            wl.set_valign(Gtk.Align.CENTER)
            wl.set_opacity(0.7)
            wl.set_margin_start(4)
            spin.connect("notify::value", self._on_spin_changed, key)
            row.add_suffix(wl)
            row.add_suffix(spin)
            group.add(row)
            self._spin_rows[key] = spin

        opt_row = Adw.ActionRow(
            title="Auto-optimize",
            subtitle="Detects your CPU model and applies recommended wattage limits from the RetroLinux database",
        )
        opt_btn = Gtk.Button(label="Optimize")
        opt_btn.set_valign(Gtk.Align.CENTER)
        opt_btn.add_css_class("suggested-action")
        opt_btn.connect("clicked", lambda _b: self._run_optimize())
        opt_row.add_suffix(opt_btn)
        group.add(opt_row)
        self._content_box.append(group)

        btn_group = Adw.PreferencesGroup(title="Hardware Buttons")
        btn_group.set_description(
            "What happens when you press the power button, hold it, or "
            "close the laptop lid. Changes are applied via systemd-logind "
            "and require a restart to take full effect."
        )
        from settings.ui.managed_row import make_combo_row as _mcr
        def _make_logind_combo(var: str, title: str, subtitle: str) -> Adw.ComboRow:
            actions, labels = self._get_logind_options()
            val = self._orig.get(var, "suspend")
            if val not in actions:
                val = "suspend"
            try:
                idx = actions.index(val)
            except ValueError:
                idx = 0
            model = Gtk.StringList.new(labels)
            row = _mcr(title, subtitle=subtitle, model=model, selected=idx)
            row.connect("notify::selected", self._on_logind_changed, var)
            return row

        self._pwr_btn_row = _make_logind_combo("pwr_btn", "Power Button", "Action when the power button is pressed briefly")
        btn_group.add(self._pwr_btn_row)
        self._pwr_btn_long_row = _make_logind_combo("pwr_btn_long", "Power Button Long Press", "Action when the power button is held for 5+ seconds")
        btn_group.add(self._pwr_btn_long_row)
        self._lid_row = _make_logind_combo("lid_close", "Lid Close", "Action when the laptop lid is closed")
        btn_group.add(self._lid_row)
        self._content_box.append(btn_group)
        return toolbar_view

    def _load_data(self) -> None:
        from lib.python.variable import get_var

        self._orig = {}
        for var, key in [
            ("PWR_AC_SAVER", "ac_saver"),
            ("PWR_AC_BALANCED", "ac_balanced"),
            ("PWR_AC_PERFORMANCE", "ac_performance"),
            ("PWR_BAT_SAVER", "bat_saver"),
            ("PWR_BAT_BALANCED", "bat_balanced"),
            ("PWR_BAT_PERFORMANCE", "bat_performance"),
            ("PWR_POWER_BTN", "pwr_btn"),
            ("PWR_POWER_BTN_LONG", "pwr_btn_long"),
            ("PWR_LID_CLOSE", "lid_close"),
        ]:
            self._orig[key] = get_var(var) or ""

        try:
            r = subprocess.run(["bash", _PWR_CORE, "--get"], capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
            self._orig["profile"] = r.stdout.strip() or "balanced"
        except Exception:
            self._orig["profile"] = "balanced"

    # ── Callbacks ──

    def _on_profile_changed(self, row: Adw.ComboRow, _pspec) -> None:
        idx = row.get_selected()
        if 0 <= idx < len(_PROFILES):
            profile = _PROFILES[idx]
            try:
                subprocess.run(["bash", _PWR_CORE, "--set", profile], capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL)
            except Exception:
                pass

    def _on_spin_changed(self, spin: Gtk.SpinButton, _pspec, key: str) -> None:
        from lib.python.variable import set_var
        val = str(int(spin.get_value()))
        var_name = next(v for v, k in [
            ("PWR_AC_SAVER", "ac_saver"), ("PWR_AC_BALANCED", "ac_balanced"),
            ("PWR_AC_PERFORMANCE", "ac_performance"), ("PWR_BAT_SAVER", "bat_saver"),
            ("PWR_BAT_BALANCED", "bat_balanced"), ("PWR_BAT_PERFORMANCE", "bat_performance"),
        ] if k == key)
        set_var(var_name, val)
        _restore()
        GLib.idle_add(self._check_dirty)

    _LOGIND_ACTIONS = ["suspend", "hibernate", "poweroff", "reboot", "ignore", "lock"]
    _LOGIND_LABELS = ["Suspend", "Hibernate", "Power Off", "Reboot", "Do Nothing", "Lock Screen"]

    def _get_logind_options(self) -> tuple[list[str], list[str]]:
        actions = list(self._LOGIND_ACTIONS)
        labels = list(self._LOGIND_LABELS)
        if not self._has_hibernate:
            idx = actions.index("hibernate")
            actions.pop(idx)
            labels.pop(idx)
        return actions, labels

    def _on_logind_changed(self, row: Adw.ComboRow, _pspec, var: str) -> None:
        actions, _labels = self._get_logind_options()
        idx = row.get_selected()
        if 0 <= idx < len(actions):
            val = actions[idx]
            var_name = {
                "pwr_btn": "PWR_POWER_BTN", "pwr_btn_long": "PWR_POWER_BTN_LONG",
                "lid_close": "PWR_LID_CLOSE",
            }.get(var, "")
            if var_name:
                from lib.python.variable import set_var
                set_var(var_name, val)
            self._check_dirty()

    def _run_optimize(self) -> None:
        try:
            opt = subprocess.run(
                ["bash", _PWR_CORE, "--optimize"],
                capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL,
            )
            parts = opt.stdout.strip().split("|")
            if len(parts) < 3:
                self._window.show_toast("No power profile found for this CPU", timeout=5, copy=True)
                return
            ac_csv, bat_csv = parts[1], parts[2]
            ac_s, ac_b, ac_p = ac_csv.split(",")
            bat_s, bat_bb, bat_p = bat_csv.split(",")

            from lib.python.variable import set_var
            updates = {
                "ac_saver": ac_s, "ac_balanced": ac_b, "ac_performance": ac_p,
                "bat_saver": bat_s, "bat_balanced": bat_bb, "bat_performance": bat_p,
            }
            for key, val in updates.items():
                set_var(next(v for v, k in [
                    ("PWR_AC_SAVER", "ac_saver"), ("PWR_AC_BALANCED", "ac_balanced"),
                    ("PWR_AC_PERFORMANCE", "ac_performance"), ("PWR_BAT_SAVER", "bat_saver"),
                    ("PWR_BAT_BALANCED", "bat_balanced"), ("PWR_BAT_PERFORMANCE", "bat_performance"),
                ] if k == key), val)
                self._orig[key] = val
                if key in self._spin_rows:
                    self._spin_rows[key].set_value(int(val))

            self._orig["profile"] = "balanced"
            _restore()
            self._window.show_toast("Optimization applied")
        except Exception as e:
            self._window.show_toast(f"Optimization failed — {e}", timeout=5, copy=True)

    # ── Dirty ──

    _LOGIND_KEYS = ("pwr_btn", "pwr_btn_long", "lid_close")
    _LOGIND_VARS = ("PWR_POWER_BTN", "PWR_POWER_BTN_LONG", "PWR_LID_CLOSE")

    def _check_dirty(self) -> None:
        was = self._dirty
        self._dirty = False
        for key, spin in self._spin_rows.items():
            if str(int(spin.get_value())) != self._orig.get(key, ""):
                self._dirty = True
                break
        if not self._dirty:
            for key in self._LOGIND_KEYS:
                from lib.python.variable import get_var
                var_name = dict(zip(self._LOGIND_KEYS, self._LOGIND_VARS))[key]
                if get_var(var_name, "") != self._orig.get(key, ""):
                    self._dirty = True
                    break
        if was != self._dirty and self._on_dirty_changed:
            self._on_dirty_changed()

    # ── Save lifecycle ──

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        if not self._dirty:
            return
        from lib.python.variable import set_var, get_var
        for key, spin in self._spin_rows.items():
            val = str(int(spin.get_value()))
            var_name = next(v for v, k in [
                ("PWR_AC_SAVER", "ac_saver"), ("PWR_AC_BALANCED", "ac_balanced"),
                ("PWR_AC_PERFORMANCE", "ac_performance"), ("PWR_BAT_SAVER", "bat_saver"),
                ("PWR_BAT_BALANCED", "bat_balanced"), ("PWR_BAT_PERFORMANCE", "bat_performance"),
            ] if k == key)
            set_var(var_name, val)
            self._orig[key] = val
        for key, var_name in [("pwr_btn", "PWR_POWER_BTN"), ("pwr_btn_long", "PWR_POWER_BTN_LONG"), ("lid_close", "PWR_LID_CLOSE")]:
            self._orig[key] = get_var(var_name, "suspend")
        self._dirty = False
        _restore()

    def discard(self) -> None:
        for key, spin in self._spin_rows.items():
            val = int(self._orig.get(key, "15")) if self._orig.get(key, "").isdigit() else 15
            spin.set_value(val)
        actions, _labels = self._get_logind_options()
        for key, row in [("pwr_btn", self._pwr_btn_row), ("pwr_btn_long", self._pwr_btn_long_row), ("lid_close", self._lid_row)]:
            if row is not None:
                val = self._orig.get(key, "suspend")
                if val not in actions:
                    val = "suspend"
                try:
                    idx = actions.index(val)
                except ValueError:
                    idx = 0
                row.set_selected(idx)
        self._dirty = False

    def flush_pending(self) -> None:
        self._run_terminal("retro system apply")

    @staticmethod
    def _run_terminal(command: str) -> None:
        escaped = command.replace("'", "'\\''")
        cmd = f"kitty -- bash -c '{escaped}; echo; echo Press Enter to close.; read'"
        lua = f'hl.dsp.exec_cmd("{cmd}", {{ float = true, size = {{ 800, 500 }}, center = true }})'
        subprocess.Popen(
            ["hyprctl", "dispatch", lua],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._dirty:
            yield PendingChange(
                category="Power",
                title="Power Limits",
                subtitle="AC and battery wattage limits changed",
                navigate_to="power",
                icon=_PWR_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "power:config", "label": "Power Configuration",
             "description": "Profile, wattage limits, and auto-optimize",
             "_group_id": "power", "_group_label": "Power", "_section_label": "Configuration"},
        ]
