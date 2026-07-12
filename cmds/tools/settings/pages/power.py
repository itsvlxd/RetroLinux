"""Power management page — profiles, wattage limits, auto-optimize."""

import os
import subprocess
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import clear_children, make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_PWR_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "power_core.sh")
_SYS_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "system_core.sh")
_PWR_ICON = "preferences-system-power-symbolic"
_PROFILES = ["performance", "balanced", "saver"]


def _restore() -> None:
    subprocess.Popen(
        ["retro", "power", "restore"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


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

    # ── Data ──

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
