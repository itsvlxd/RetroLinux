"""Fan control page — detect fans, set modes, edit curves, live RPM/Temp display."""

import json
import os
import subprocess
import threading
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk, Pango

from settings.core.pending import PendingChange
from settings.data.fan_curve_data import curve_from_str, curve_to_str, get_fan_curve_store
from settings.ui import make_page_layout
from settings.ui.icons import FAN_CONTROL_ICON
from settings.ui.fan_curve_editor import FanCurveEditorDialog

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_RETRO_DIR = os.environ.get("RETRO_DIR", "/opt/retrolinux")
_FANS_CORE = os.path.join(_RETRO_DIR, "scripts", "fans_core.sh")

_REFRESH_MS = 2000
_sudoers_done = False
_profile_change_pending = False
_acpi_profiles = []


def _ensure_fan_sudoers() -> None:
    global _sudoers_done
    if _sudoers_done:
        return
    _sudoers_done = True
    try:
        r = subprocess.run(
            ["sudo", "-n", _FANS_CORE, "--json"],
            capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL,
        )
        if r.returncode == 0:
            return
    except Exception:
        pass
    try:
        subprocess.run(
            ["pkexec", "bash", _FANS_CORE, "--ensure-sudoers"],
            capture_output=True, text=True, timeout=15, stdin=subprocess.DEVNULL,
        )
    except Exception:
        pass


def _run_core(*args: str) -> str:
    try:
        r = subprocess.run(
            ["bash", _FANS_CORE, *args],
            capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _run_core_pkexec(*args: str) -> bool:
    try:
        r = subprocess.run(
            ["sudo", "-n", _FANS_CORE, *args],
            capture_output=True, text=True, timeout=15, stdin=subprocess.DEVNULL,
        )
        if r.returncode == 0 and r.stdout.strip().startswith("OK"):
            return True
        r = subprocess.run(
            ["pkexec", "bash", _FANS_CORE, *args],
            capture_output=True, text=True, timeout=15, stdin=subprocess.DEVNULL,
        )
        return r.returncode == 0 and r.stdout.strip().startswith("OK")
    except Exception:
        return False


def _load_acpi_profiles() -> list[str]:
    """Load available ACPI platform profile choices from the system."""
    try:
        with open("/sys/firmware/acpi/platform_profile_choices", "r") as f:
            profiles = [line.strip() for line in f.read().splitlines() if line.strip()]
        return profiles
    except (FileNotFoundError, PermissionError):
        return ["Quiet", "Balanced", "Performance"]


class _FanRow:
    def __init__(self, fan: dict, on_change):
        self._fan = fan
        self._on_change = on_change
        self._fan_id = fan["id"]
        self._signals: list = []

        self._row = Adw.ActionRow(title=fan["label"])
        self._row.set_subtitle(f"{fan['rpm']}rpm ({fan['pct']}%) [{fan['temp']}]")

        # RPM/PCT label (live)
        self._status_lbl = Gtk.Label(label=f"{fan['rpm']}rpm  {fan['pct']}%")
        self._status_lbl.set_valign(Gtk.Align.CENTER)
        self._status_lbl.add_css_class("dim-label")
        self._row.add_suffix(self._status_lbl)

        # Mode selector
        self._mode_model = Gtk.StringList.new(["Auto", "Curve", "Manual"])
        self._mode_row = Gtk.DropDown(model=self._mode_model)
        mode_idx = {"auto": 0, "curve": 1, "manual": 2}.get(fan.get("mode", "auto"), 0)
        self._mode_row.set_selected(mode_idx)
        self._mode_row.set_valign(Gtk.Align.CENTER)
        sid = self._mode_row.connect("notify::selected", self._on_mode_changed)
        self._signals.append((self._mode_row, sid))
        self._row.add_suffix(self._mode_row)

        # Curve edit button
        self._curve_btn = Gtk.Button(icon_name="draw-arc-symbolic")
        self._curve_btn.set_valign(Gtk.Align.CENTER)
        self._curve_btn.add_css_class("flat")
        self._curve_btn.set_tooltip_text("Edit fan curve")
        self._curve_btn.connect("clicked", self._on_edit_curve)
        self._row.add_suffix(self._curve_btn)

        # Speed spin (visible only in manual mode)
        self._speed_adj = Gtk.Adjustment(value=fan.get("speed", 100), lower=0, upper=100, step_increment=1)
        self._speed_spin = Gtk.SpinButton(adjustment=self._speed_adj, digits=0)
        self._speed_spin.set_valign(Gtk.Align.CENTER)
        self._speed_spin.set_width_chars(4)
        sid2 = self._speed_spin.connect("value-changed", self._on_speed_changed)
        self._signals.append((self._speed_spin, sid2))
        self._row.add_suffix(self._speed_spin)

        self._speed_lbl = Gtk.Label(label="%")
        self._speed_lbl.add_css_class("dim-label")
        self._row.add_suffix(self._speed_lbl)

        self._update_visibility()

    @property
    def widget(self):
        return self._row

    @property
    def fan_id(self):
        return self._fan_id

    def update_from(self, fan: dict) -> None:
        self._fan = fan
        self._status_lbl.set_text(f"{fan['rpm']}rpm  {fan['pct']}%")
        self._row.set_subtitle(f"{fan['rpm']}rpm ({fan['pct']}%) [{fan['temp']}]")

    def _update_visibility(self) -> None:
        mode = self._mode_row.get_selected()
        show_curve = mode == 1
        show_speed = mode == 2
        self._curve_btn.set_visible(show_curve)
        self._speed_spin.set_visible(show_speed)
        self._speed_lbl.set_visible(show_speed)

    def _on_mode_changed(self, _dd, _pspec) -> None:
        mode_names = {0: "auto", 1: "curve", 2: "manual"}
        mode = mode_names.get(self._mode_row.get_selected(), "auto")
        self._update_visibility()
        threading.Thread(target=_run_core_pkexec, args=("--set-mode", self._fan_id, mode), daemon=True).start()
        self._on_change()

    def _on_speed_changed(self, spin) -> None:
        pct = int(spin.get_value())
        threading.Thread(target=_run_core_pkexec, args=("--set-speed", self._fan_id, str(pct)), daemon=True).start()
        self._on_change()

    def _on_edit_curve(self, _btn) -> None:
        win = self._row.get_root()
        while win and not isinstance(win, Adw.Window):
            win = win.get_parent()
        initial = self._fan.get("curve", "")
        FanCurveEditorDialog(
            win, initial_curve=initial, on_curve_saved=self._on_curve_saved,
            fan_label=self._fan.get("label", ""),
        )

    def _on_curve_saved(self, name: str) -> None:
        pts = get_fan_curve_store().get_curve_points(name)
        curve_str = curve_to_str(pts)
        threading.Thread(target=_run_core_pkexec, args=("--set-curve", self._fan_id, curve_str), daemon=True).start()
        self._on_change()

    def disconnect_signals(self) -> None:
        for obj, sid in self._signals:
            obj.disconnect(sid)
        self._signals.clear()


class FanControlPage:
    """Fan control settings page."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None
        self._dirty = False
        self._content_box: Gtk.Box | None = None
        self._fan_rows: list[_FanRow] = []
        self._timer = 0

        # Overview widgets
        self._master_switch: Gtk.Switch | None = None
        self._engine_lbl: Gtk.Label | None = None
        self._temp_lbl: Gtk.Label | None = None
        self._profile_dd: Gtk.DropDown | None = None
        self._acpi_lbl: Gtk.Label | None = None

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        _ensure_fan_sudoers()
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh fan data")
        refresh_btn.connect("clicked", lambda _: self._refresh())
        header.pack_start(refresh_btn)

        # Profile group — ACPI platform profiles
        profile_group = Adw.PreferencesGroup(title="Profile")

        # Load available ACPI profiles from the system
        global _acpi_profiles
        _acpi_profiles = _load_acpi_profiles()
        profile_model = Gtk.StringList.new(_acpi_profiles)
        self._profile_dd = Gtk.DropDown(model=profile_model)
        self._profile_dd.set_valign(Gtk.Align.CENTER)
        self._profile_dd.connect("notify::selected", self._on_profile_changed)
        prof_row = Adw.ActionRow(title="Profile", subtitle="ACPI platform profile")
        prof_row.add_suffix(self._profile_dd)
        profile_group.add(prof_row)

        # ACPI platform profile status label
        self._acpi_lbl = Gtk.Label(label="", halign=Gtk.Align.START)
        self._acpi_lbl.set_valign(Gtk.Align.CENTER)
        acpi_row = Adw.ActionRow(title="ACPI Platform Profile")
        acpi_row.add_suffix(self._acpi_lbl)
        profile_group.add(acpi_row)

        self._content_box.append(profile_group)

        # Fan list
        self._fans_group = Adw.PreferencesGroup(title="Fans")
        self._content_box.append(self._fans_group)

        self._refresh()
        return toolbar_view

    def _refresh(self) -> None:
        data = _run_core("--json")
        if not data:
            return
        try:
            info = json.loads(data)
        except (json.JSONDecodeError, ValueError):
            return

        # Fans
        fans = info.get("fans", [])
        existing_ids = {r.fan_id for r in self._fan_rows}
        new_ids = {f["id"] for f in fans}

        # Remove stale rows
        for row in list(self._fan_rows):
            if row.fan_id not in new_ids:
                row.disconnect_signals()
                self._fans_group.remove(row.widget)
                self._fan_rows.remove(row)

        # Add/update rows
        for fan in fans:
            existing = next((r for r in self._fan_rows if r.fan_id == fan["id"]), None)
            if existing:
                existing.update_from(fan)
            else:
                row = _FanRow(fan, self._mark_dirty)
                self._fan_rows.append(row)
                self._fans_group.add(row.widget)

        # Profile — use ACPI profiles from the system
        global _acpi_profiles
        _acpi_profiles = _load_acpi_profiles()
        if self._profile_dd:
            profile_model = Gtk.StringList.new(_acpi_profiles)
            self._profile_dd.set_model(profile_model)
            # Select the first available profile
            if _acpi_profiles:
                self._profile_dd.set_selected(0)

        if self._acpi_lbl:
            acpi = info.get("acpi_choices", "")
            self._acpi_lbl.set_text(acpi if acpi else "Not available")

    def _on_profile_changed(self, _dd, _pspec) -> None:
        global _profile_change_pending
        _profile_change_pending = True
        # Schedule the flag to be cleared after 3 seconds
        GLib.timeout_add(3000, lambda _: (_profile_change_pending.__class__.__setattr__("_profile_change_pending", False)))
        profile = self._profile_dd.get_selected()
        if profile is not None and profile < len(_acpi_profiles):
            profile_name = _acpi_profiles[profile]
            threading.Thread(target=_run_core_pkexec, args=("--set-profile", profile_name), daemon=True).start()
        self._mark_dirty()

    def _mark_dirty(self) -> None:
        self._dirty = True
        if self._on_dirty_changed:
            self._on_dirty_changed()

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
        return self._dirty

    def mark_saved(self) -> None:
        self._dirty = False

    def discard(self) -> None:
        self._dirty = False
        self._refresh()

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return []

    def get_search_entries(self) -> list[dict]:
        return [{
            "key": "fan_control:control",
            "label": "Fan Control",
            "description": "Manage fan speeds, curves and cooling profiles",
            "_group_id": "fan_control",
            "_group_label": "Fan Control",
            "_section_label": "System",
        }]

    def destroy(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None