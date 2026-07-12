"""GRUB bootloader configuration page — kernel, theme, resolution, timeout, and toggles."""

import os
import math
import subprocess
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import clear_children, make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_GRUB_ICON = "system-restart-symbolic"
_KERNELS = ["linux", "linux-zen", "linux-lts", "linux-hardened"]
_THEMES = ["retropunk", "retrolinux"]


def _detect_resolutions() -> list[str]:
    """Detect native resolution and compute viable GRUB resolutions."""
    rx, ry = 1920, 1080
    try:
        result = subprocess.run(
            ["xrandr"], capture_output=True, text=True, timeout=5,
            stdin=subprocess.DEVNULL,
        )
        for line in result.stdout.splitlines():
            if "*" in line:
                parts = line.strip().split()
                if parts and "x" in parts[0]:
                    rx, ry = (int(v) for v in parts[0].split("x"))
                    break
    except Exception:
        pass

    g = math.gcd(rx, ry)
    ar_x, ar_y = rx // g, ry // g

    results = []
    for scale in [100, 80, 75, 70, 60, 50, 40]:
        sx = rx * scale // 100
        sy = ry * scale // 100
        if sx < 320 or sy < 240:
            continue
        g2 = math.gcd(sx, sy)
        if sx // g2 == ar_x and sy // g2 == ar_y:
            results.append(f"{sx}x{sy}")

    for alt in ["1920x1080", "1280x720", "1024x768", "800x600"]:
        ax, ay = (int(v) for v in alt.split("x"))
        g2 = math.gcd(ax, ay)
        if ax // g2 <= 16 and ay // g2 <= 10 and alt not in results:
            results.append(alt)

    results.append("auto")
    return results


class GrubPage:
    """GRUB bootloader configuration — sets shell variables, applies via terminal on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._refreshable_box: Gtk.Box
        self._orig: dict[str, str] = {}
        self._dirty = False
        self._on_dirty_changed = None
        self._combo_rows: dict[str, Adw.ComboRow] = {}
        self._resolutions: list[str] = []

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)
        self._resolutions = _detect_resolutions()
        self._refreshable_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self._content_box.append(self._refreshable_box)
        self._load_data()
        self._rebuild_refreshable()
        return toolbar_view

    def _load_data(self) -> None:
        from lib.python.variable import get_var
        self._orig = {
            "kernel": get_var("GRUB_KERNEL") or "linux",
            "theme": get_var("GRUB_THEME_CHOICE") or "retropunk",
            "resolution": get_var("BOOT_VIDEO_GRUB") or self._resolutions[0] if self._resolutions else "1920x1080",
            "timeout": get_var("GRUB_TIMEOUT") or "10",
            "os_prober": get_var("GRUB_OS_PROBER") or "false",
            "snapshots": get_var("GRUB_SNAPSHOTS_ENABLED") or "true",
        }

    def _rebuild_refreshable(self) -> None:
        clear_children(self._refreshable_box)
        cfg = self._orig
        res = self._resolutions or ["1920x1080", "1280x720", "1024x768", "auto"]

        group = Adw.PreferencesGroup(title="GRUB Configuration")

        from settings.ui.managed_row import make_combo_row

        km = Gtk.StringList.new(_KERNELS)
        ki = _KERNELS.index(cfg["kernel"]) if cfg["kernel"] in _KERNELS else 0
        kr = make_combo_row("Kernel", subtitle="Default Linux kernel to boot", model=km, selected=ki)
        kr.connect("notify::selected", self._on_changed, "kernel")
        group.add(kr)
        self._combo_rows["kernel"] = kr

        tm = Gtk.StringList.new(_THEMES)
        ti = _THEMES.index(cfg["theme"]) if cfg["theme"] in _THEMES else 0
        tr = make_combo_row("Theme", subtitle="GRUB boot menu theme", model=tm, selected=ti)
        tr.connect("notify::selected", self._on_changed, "theme")
        group.add(tr)
        self._combo_rows["theme"] = tr

        rm = Gtk.StringList.new(res)
        ri = res.index(cfg["resolution"]) if cfg["resolution"] in res else 0
        rr = make_combo_row("Resolution", subtitle="Boot screen resolution", model=rm, selected=ri)
        rr.connect("notify::selected", self._on_changed, "resolution")
        group.add(rr)
        self._combo_rows["resolution"] = rr

        adj = Gtk.Adjustment(value=float(cfg["timeout"]), lower=1, upper=60, step_increment=1, page_increment=5)
        row = Adw.ActionRow(title="Timeout", subtitle="Seconds before auto-boot")
        spin = Gtk.SpinButton(adjustment=adj, digits=0)
        spin.set_valign(Gtk.Align.CENTER)
        spin.connect("notify::value", self._on_changed, "timeout")
        row.add_suffix(spin)
        group.add(row)
        self._spin = spin

        sr = Adw.SwitchRow(title="OS Prober", subtitle="Detect other operating systems at boot")
        sr.set_active(cfg["os_prober"] == "true")
        sr.connect("notify::active", self._on_changed, "os_prober")
        group.add(sr)
        self._os_prober = sr

        s2 = Adw.SwitchRow(title="Boot Snapshots", subtitle="BTRFS snapshot boot entries")
        s2.set_active(cfg["snapshots"] == "true")
        s2.connect("notify::active", self._on_changed, "snapshots")
        group.add(s2)
        self._snapshots = s2

        self._refreshable_box.append(group)

    def _on_changed(self, *_args) -> None:
        GLib.idle_add(self._check_dirty)

    def _check_dirty(self) -> None:
        was = self._dirty
        self._dirty = False
        res = self._resolutions or ["1920x1080", "1280x720", "1024x768", "auto"]
        for key, combo in self._combo_rows.items():
            choices = res if key == "resolution" else (_THEMES if key == "theme" else _KERNELS)
            idx = combo.get_selected()
            val = choices[idx] if 0 <= idx < len(choices) else ""
            if val != self._orig.get(key, ""):
                self._dirty = True
                break
        if not self._dirty:
            if str(int(self._spin.get_value())) != self._orig.get("timeout", "10"):
                self._dirty = True
        if not self._dirty:
            for sw, key in [(self._os_prober, "os_prober"), (self._snapshots, "snapshots")]:
                val = "true" if sw.get_active() else "false"
                if val != self._orig.get(key, ""):
                    self._dirty = True
                    break
        if was != self._dirty and self._on_dirty_changed:
            self._on_dirty_changed()

    # ── Save lifecycle ──

    def is_dirty(self) -> bool:
        return self._dirty

    def _get_current_values(self) -> dict[str, str]:
        res = self._resolutions or ["1920x1080", "1280x720", "1024x768", "auto"]
        vals = {}
        for key, combo in self._combo_rows.items():
            choices = res if key == "resolution" else (_THEMES if key == "theme" else _KERNELS)
            idx = combo.get_selected()
            vals[key] = choices[idx] if 0 <= idx < len(choices) else ""
        vals["timeout"] = str(int(self._spin.get_value()))
        vals["os_prober"] = "true" if self._os_prober.get_active() else "false"
        vals["snapshots"] = "true" if self._snapshots.get_active() else "false"
        return vals

    def mark_saved(self) -> None:
        if not self._dirty:
            return
        from lib.python.variable import set_var

        vals = self._get_current_values()
        set_var("GRUB_KERNEL", vals["kernel"])
        set_var("GRUB_THEME_CHOICE", vals["theme"])
        set_var("BOOT_VIDEO_GRUB", vals["resolution"])
        set_var("GRUB_TIMEOUT", vals["timeout"])
        set_var("GRUB_OS_PROBER", vals["os_prober"])
        set_var("GRUB_SNAPSHOTS_ENABLED", vals["snapshots"])

        self._orig.update(vals)
        self._dirty = False

        try:
            cmd = "retro grub apply; echo; echo 'Press Enter to close.'; read"
            escaped = cmd.replace("'", "'\\''")
            terminal = f"kitty -- bash -c '{escaped}'"
            lua = f'hl.dsp.exec_cmd("{terminal}", {{ float = true, size = {{ 800, 500 }}, center = true }})'
            subprocess.Popen(
                ["hyprctl", "dispatch", lua],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except (FileNotFoundError, OSError):
            pass

    def discard(self) -> None:
        res = self._resolutions or ["1920x1080", "1280x720", "1024x768", "auto"]
        for key, combo in self._combo_rows.items():
            choices = res if key == "resolution" else (_THEMES if key == "theme" else _KERNELS)
            val = self._orig.get(key, "")
            idx = choices.index(val) if val in choices else 0
            combo.set_selected(idx)
        self._spin.set_value(float(self._orig.get("timeout", "10")))
        self._os_prober.set_active(self._orig.get("os_prober") == "true")
        self._snapshots.set_active(self._orig.get("snapshots") == "true")
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._dirty:
            yield PendingChange(
                category="Bootloader",
                title="GRUB Configuration",
                subtitle="Kernel, theme, resolution, timeout, OS prober, or snapshots changed",
                navigate_to="grub",
                icon=_GRUB_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "grub:config", "label": "GRUB Configuration",
             "description": "Kernel, theme, resolution, timeout, OS prober, snapshots",
             "_group_id": "grub", "_group_label": "Bootloader", "_section_label": "Configuration"},
        ]
