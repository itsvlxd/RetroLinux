"""GRUB bootloader configuration page — kernel, theme, resolution, timeout, and toggles."""

import json
import os
import math
import re
import subprocess
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import clear_children, make_page_layout
from settings.ui.reorder import RowReorderController

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_GRUB_ICON = "system-restart-symbolic"
_KERNELS = ["linux", "linux-zen", "linux-lts", "linux-hardened"]
_THEMES = ["retropunk", "retrolinux"]

_RETRO_DIR = os.environ.get("RETRO_DIR", "/opt/retrolinux")
_GRUB_CFG = "/boot/grub/grub.cfg"
_GRUB_SPLICER = os.path.join(_RETRO_DIR, "scripts", "python", "grub_manual_entries.py")

_BLOCK_TITLE_RE = re.compile(r"^[\t ]*(?:menuentry|submenu)[\t ]+([\"'])(.*?)\1")


def _manual_store_path() -> str:
    """Path of the persistent manual-entries store (user-writable)."""
    retro_config = os.environ.get("RETRO_CONFIG", "")
    if not retro_config:
        retro_config = os.path.join(os.environ.get("HOME", ""), ".config", "retro")
    return os.path.join(retro_config, "grub", "manual-entries.cfg")


def _parse_grub_entries() -> list[dict]:
    """Return the top-level menuentry/submenu blocks from /boot/grub/grub.cfg."""
    try:
        result = subprocess.run(
            ["python3", _GRUB_SPLICER, "--parse", _GRUB_CFG],
            capture_output=True, text=True, timeout=10,
            stdin=subprocess.DEVNULL,
        )
        if result.returncode != 0:
            return []
        data = json.loads(result.stdout or "[]")
        return data if isinstance(data, list) else []
    except (json.JSONDecodeError, FileNotFoundError, OSError, subprocess.TimeoutExpired):
        return []


def _parse_manual_entries() -> dict[str, str]:
    """Return the manual overrides as {key: block}."""
    try:
        result = subprocess.run(
            ["python3", _GRUB_SPLICER, "--parse-store", _manual_store_path()],
            capture_output=True, text=True, timeout=10,
            stdin=subprocess.DEVNULL,
        )
        data = json.loads(result.stdout or "[]")
        return {
            item["key"]: item["block"]
            for item in data
            if isinstance(item, dict) and item.get("key") and item.get("block")
        }
    except (json.JSONDecodeError, FileNotFoundError, OSError, subprocess.TimeoutExpired):
        return {}


def _write_manual_entries(overrides: dict[str, str]) -> bool:
    """Persist the manual overrides to the store, keeping any saved order."""
    return _write_store(overrides, _read_menu_order())


def _read_menu_order() -> list[str]:
    """Return the persisted menu order as a key list (empty when unset)."""
    try:
        with open(_manual_store_path(), encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return []
    order: list[str] = []
    in_order = False
    for line in lines:
        if line == "### RETRO_MENU_ORDER ###":
            in_order = True
        elif line == "### END RETRO_MENU_ORDER ###":
            in_order = False
        elif in_order and line.strip():
            order.append(line.strip())
    return order


def _write_store(overrides: dict[str, str], order: list[str]) -> bool:
    """Write overrides plus an optional order section; returns success."""
    path = _manual_store_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        parts = [
            f"### RETRO_MANUAL_ENTRY: {key} ###\n{block.rstrip()}\n### END RETRO_MANUAL_ENTRY ###"
            for key, block in overrides.items()
        ]
        if order:
            parts.append(
                "### RETRO_MENU_ORDER ###\n"
                + "\n".join(order)
                + "\n### END RETRO_MENU_ORDER ###"
            )
        with open(path, "w") as f:
            if parts:
                f.write("\n\n".join(parts))
                f.write("\n")
        return True
    except OSError:
        return False


def _persist_menu_order(order: list[str]) -> bool:
    """Persist the menu order to the store, keeping existing overrides."""
    return _write_store(_parse_manual_entries(), order)


def _block_title(block: str) -> str:
    match = _BLOCK_TITLE_RE.match(block)
    return match.group(2) if match else ""


def _block_summary(block: str) -> str:
    lines = block.splitlines()[1:-1]
    return next((line.strip() for line in lines if line.strip()), "")[:120]


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
        self._entries_group: Adw.PreferencesGroup
        self._entry_rows: list[Gtk.Widget] = []
        self._orig: dict[str, str] = {}
        self._dirty = False
        self._on_dirty_changed = None
        self._combo_rows: dict[str, Adw.ComboRow] = {}
        self._resolutions: list[str] = []
        self._merged: list[dict] = []
        self._reorder = RowReorderController(
            move=self._move_entry,
            iter_rows=lambda: self._entry_rows,
        )

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        regen_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        regen_btn.set_tooltip_text("Regenerate GRUB config")
        regen_btn.add_css_class("flat")
        regen_btn.connect("clicked", self._on_regen)
        header.pack_start(regen_btn)

        self._resolutions = _detect_resolutions()
        self._refreshable_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self._content_box.append(self._refreshable_box)
        self._load_data()
        self._rebuild_refreshable()

        self._entries_group = Adw.PreferencesGroup(
            title="Boot Menu Entries",
            description="Entries shown at boot. Drag to reorder; edit an entry to keep "
                        "your own version. Regenerate re-applies both after rebuilding "
                        "from the template.",
        )
        self._content_box.append(self._entries_group)
        self._rebuild_entries()

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

    # ── Boot Menu Entries ──

    def _rebuild_entries(self) -> None:
        if not hasattr(self, "_entries_group"):
            return
        for row in self._entry_rows:
            self._entries_group.remove(row)
        self._entry_rows = []
        manual = _parse_manual_entries()
        entries = _parse_grub_entries()

        merged: list[dict] = []
        seen: set[str] = set()
        for entry in entries:
            seen.add(entry["key"])
            display = dict(entry)
            block = manual.get(entry["key"])
            if block is not None:
                display["text"] = block
                display["title"] = _block_title(block) or entry["title"]
                display["summary"] = _block_summary(block)
                display["manual"] = True
            else:
                display["summary"] = _block_summary(display.get("text", ""))
                display["manual"] = False
            merged.append(display)

        for key in manual:
            if key in seen:
                continue
            block = manual[key]
            merged.append({
                "kind": "menuentry",
                "title": _block_title(block) or key,
                "id": key, "key": key, "text": block,
                "summary": _block_summary(block),
                "manual": True,
            })

        order = _read_menu_order()
        if order:
            pos = {key: i for i, key in enumerate(order)}
            merged.sort(key=lambda entry: pos.get(entry["key"], len(order)))

        self._merged = merged

        for idx, entry in enumerate(merged):
            row = Adw.ActionRow(title=entry["title"])
            row.set_subtitle(f'{entry["kind"]} · {entry["summary"] or "—"}')

            if entry["manual"]:
                badge = Gtk.Label(label="manual")
                badge.add_css_class("badge")
                badge.add_css_class("active-badge")
                badge.set_valign(Gtk.Align.CENTER)
                row.add_suffix(badge)

            edit_btn = Gtk.Button(icon_name="document-edit-symbolic")
            edit_btn.set_valign(Gtk.Align.CENTER)
            edit_btn.set_tooltip_text("Edit entry")
            edit_btn.connect("clicked", lambda _b, entry=entry: self._on_edit_entry(entry))
            row.add_suffix(edit_btn)

            if entry["manual"]:
                trash_btn = Gtk.Button(icon_name="user-trash-symbolic")
                trash_btn.set_valign(Gtk.Align.CENTER)
                trash_btn.set_tooltip_text("Revert to template")
                trash_btn.connect("clicked", lambda _b, entry=entry: self._revert_manual(entry))
                row.add_suffix(trash_btn)

            self._reorder.attach(row, idx)
            self._entries_group.add(row)
            self._entry_rows.append(row)

        if not merged:
            row = Adw.ActionRow(title="No boot entries found")
            row.set_subtitle("Run Regenerate to rebuild the boot menu from the template.")
            row.set_sensitive(False)
            self._entries_group.add(row)
            self._entry_rows.append(row)

    # ── Drag-and-drop reorder ──

    def _move_entry(self, src: int, dst: int) -> bool:
        if src == dst or not (0 <= src < len(self._merged) and 0 <= dst < len(self._merged)):
            return False
        entry = self._merged.pop(src)
        self._merged.insert(dst, entry)
        order = [e["key"] for e in self._merged]
        if _persist_menu_order(order):
            self._window.show_toast("Menu order saved \u2014 applies on Regenerate", timeout=3)
        else:
            self._window.show_toast("Failed to save menu order", timeout=3)
        self._rebuild_entries()
        return True

    def _on_edit_entry(self, entry: dict) -> None:
        from settings.ui.grub_entry_edit_dialog import GrubEntryEditDialog

        manual = _parse_manual_entries().get(entry["key"])
        GrubEntryEditDialog.present_singleton(
            self._window,
            entry=entry,
            manual=manual,
            on_apply=self._save_manual,
            on_revert=self._revert_key,
        )

    def _save_manual(self, key: str, block: str) -> None:
        overrides = _parse_manual_entries()
        overrides[key] = block
        if _write_manual_entries(overrides):
            self._window.show_toast("Entry saved \u2014 kept across regenerations", timeout=3)
        else:
            self._window.show_toast("Failed to save entry", timeout=3)
        self._rebuild_entries()

    def _revert_key(self, key: str) -> None:
        overrides = _parse_manual_entries()
        if key in overrides:
            del overrides[key]
            _write_manual_entries(overrides)
            self._window.show_toast("Reverted to template entry", timeout=2)
        self._rebuild_entries()

    def _revert_manual(self, entry: dict) -> None:
        from settings.ui import confirm

        confirm(
            self._window,
            heading="Revert to template?",
            body=f'\u201c{entry["title"]}\u201d will go back to the version generated '
                 "from the template on the next regeneration.",
            label="Revert",
            on_confirm=lambda: self._revert_key(entry["key"]),
        )

    def _on_regen(self, _btn) -> None:
        self._window.show_toast("Regenerating GRUB config\u2026", timeout=3)
        self._launch_kitty("sudo grub-mkconfig -o /boot/grub/grub.cfg && retro grub apply")
        for delay in (6, 14, 26):
            GLib.timeout_add(delay * 1000, self._rebuild_entries)

    @staticmethod
    def _launch_kitty(command: str) -> None:
        cmd = f"kitty -- bash -c '{command}; echo; echo Press Enter to close.; read'"
        lua = f'hl.dsp.exec_cmd("{cmd}", {{ float = true, size = {{ 800, 500 }}, center = true }})'
        subprocess.Popen(
            ["hyprctl", "dispatch", lua],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

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

        self._launch_kitty("retro grub apply")

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
            {"key": "grub:entries", "label": "Boot Menu Entries",
             "description": "Edit GRUB menu entries; regenerate the boot menu",
             "_group_id": "grub", "_group_label": "Bootloader", "_section_label": "Boot Menu"},
        ]
