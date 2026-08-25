"""Shell Desktop page — configure the desktop icon grid and desktop widgets.

Mirrors the Desktop section of the in-shell ``ShellPanel.qml``. Values are
written to ``~/.config/retro/shell/desktop.json``; the shell's ``FileView``
watches that file with ``watchChanges`` and reloads on external writes, so
changes apply live without a shell restart.

In addition to the icon-grid settings this page manages the desktop widget
system:

- **Edit Mode**: a switch that toggles ``desktop.json.editMode``. While on,
  the shell shows drag handles + borders around each widget so the user can
  reposition them; positions persist to ``desktop.json.widgets`` as the user
  drags.
- **Desktop Widgets**: a reorderable list of the widgets placed on the
  desktop. The user can add widgets from ``DESKTOP_WIDGET_CATALOG`` (each is
  only addable once) or remove an existing one.
"""

from collections.abc import Iterable
import json
import os
import shutil
import subprocess
import sys
from typing import TYPE_CHECKING
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from gi.repository import Adw, Gio, GLib, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import (
    DESKTOP_WIDGET_CATALOG,
    DESKTOP_WIDGET_SIZES,
    load_desktop,
    load_desktop_widgets,
    save_desktop,
    save_desktop_widgets,
)
from settings.ui import make_inline_hint, make_page_layout
from settings.ui.color_combo import COLOR_NAMES, color_map, _draw_swatch_hex
from settings.ui.icons import DESKTOP_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row
from settings.ui.reorder import RowReorderController

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

# Available faces/styles per widget type (matched by the shell widgets).
CLOCK_FACES: dict = {
    "clockanalog": ["classic", "numeric", "roman", "dots", "minimal", "sector", "skeleton", "rings", "bold", "tall", "track", "diamond", "bauhaus", "railway"],
    "clockdigital": ["classic", "minimal", "compact", "large"],
    "battery": ["gauge", "juice", "bars"],
}

# Hand styles for the analog clock (matched by the shell widget).
CLOCK_HAND_STYLES: dict = {
    "clockanalog": ["taper", "classic", "thin"],
}

CLOCK_HAND_STYLE_LABELS: dict = {
    "taper": "Tapered",
    "classic": "Classic Lines",
    "thin": "Thin",
}

CLOCK_FACE_LABELS: dict = {
    "classic": "Classic",
    "numeric": "Numeric",
    "roman": "Roman",
    "dots": "Dots",
    "minimal": "Minimal",
    "sector": "Sector",
    "skeleton": "Skeleton",
    "rings": "Rings",
    "bold": "Bold",
    "tall": "Tall",
    "track": "Track",
    "diamond": "Diamond",
    "bauhaus": "Bauhaus",
    "railway": "Railway",
    "compact": "Compact",
    "large": "Large",
    "gauge": "Gauge",
    "juice": "Juice",
    "bars": "Bars",
}


def _is_valid_timezone(name: str) -> bool:
    """Return True if ``name`` is a valid IANA timezone (or UTC/GMT alias)."""
    name = (name or "").strip()
    if not name:
        return False
    if name in ("UTC", "GMT", "Etc/UTC", "Etc/GMT"):
        return True
    try:
        ZoneInfo(name)
        return True
    except (ZoneInfoNotFoundError, ValueError):
        return False


def _make_named_color_combo_row(title: str, current: str, *, subtitle: str = ""):
    ids = list(COLOR_NAMES)
    labels = list(COLOR_NAMES)
    try:
        selected = ids.index(current)
    except ValueError:
        selected = 0

    factory = Gtk.SignalListItemFactory()

    def _setup(_factory, item):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_start(4)
        swatch = Gtk.DrawingArea()
        swatch.set_size_request(18, 18)
        swatch.set_valign(Gtk.Align.CENTER)

        def _draw(w, cr, ww, hh):
            name = getattr(w, "_rl_color_name", "")
            hex_color = color_map().get(name, "#888888")
            _draw_swatch_hex(cr, ww, hh, hex_color)

        swatch.set_draw_func(_draw)
        label = Gtk.Label(xalign=0.0, hexpand=True)
        box.append(swatch)
        box.append(label)
        item.set_child(box)

    def _bind(_factory, item):
        name = item.get_item().get_string() if item.get_item() else ""
        box = item.get_child()
        if box and isinstance(box, Gtk.Box):
            swatch = box.get_first_child()
            if isinstance(swatch, Gtk.DrawingArea):
                swatch._rl_color_name = name
                swatch.queue_draw()
            label = box.get_last_child()
            if isinstance(label, Gtk.Label):
                label.set_text(name)

    factory.connect("setup", _setup)
    factory.connect("bind", _bind)

    row = make_combo_row(title, model=Gtk.StringList.new(labels), selected=selected,
                         subtitle=subtitle, factory=factory)
    return row, ids


class ShellDesktopPage:
    """Shell desktop configuration — writes ``desktop.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_desktop()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

        # Widget list state (stored in desktop_widgets.json)
        self._widgets: list[dict] = load_desktop_widgets()
        self._saved_widgets: list[dict] = [dict(w) for w in self._widgets]
        self._widget_order: list[str] = [w.get("id") for w in self._widgets]
        self._saved_widget_order: list[str] = list(self._widget_order)
        self._removed_ids: set[str] = set()
        self._widget_rows: list[Adw.ActionRow] = []
        self._widget_group: Adw.PreferencesGroup | None = None
        self._edit_row: Adw.SwitchRow | None = None
        self._widget_reorder = RowReorderController(
            move=self._move_widget, iter_rows=lambda: self._widget_rows
        )

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        group = Adw.PreferencesGroup(
            title="Desktop",
            description="Desktop icon grid appearance and behaviour.",
        )
        self._add_switch(group, "enabled", "Enabled",
                         subtitle="Show the desktop on the wallpaper")
        self._add_switch(group, "showIcons", "Show Icons",
                         subtitle="Display icons on the desktop (off shows only widgets)",
                         default_value=True)
        self._add_spin(group, "iconSize", "Icon Size", lower=24, upper=96, suffix="px",
                       subtitle="Size of desktop icons")
        self._add_spin(group, "spacingVertical", "Vertical Spacing", lower=0, upper=48, suffix="px",
                       subtitle="Vertical gap between desktop icon rows")
        self._add_color_combo(group, "textColor", "Text Color",
                              subtitle="Theme color for desktop icon labels")
        content_box.append(group)

        # Desktop widget scope (global vs per monitor)
        scope_group = Adw.PreferencesGroup(
            title="Widget Scope",
            description="Whether desktop widgets appear on all monitors or per monitor.",
        )
        self._add_switch(scope_group, "perMonitor", "Widgets per monitor",
                         subtitle="Each monitor shows only the widgets placed on it "
                                  "(drag a widget onto a screen to assign it)",
                         default_value=False)
        content_box.append(scope_group)

        # Desktop widgets (edit mode + widget list in one group)
        self._widget_group = Adw.PreferencesGroup(
            title="Desktop Widgets",
            description="Add widgets to your desktop. Toggle Edit Mode, then drag them around to position them.",
        )
        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text("Add a desktop widget")
        add_btn.connect("clicked", self._on_add_widget)
        self._widget_group.set_header_suffix(add_btn)

        self._edit_row = Adw.SwitchRow(
            title="Edit Mode",
            subtitle="Show drag handles and reposition desktop widgets",
        )
        self._edit_row.set_active(bool(self._data.get("editMode", False)))

        def _on_edit_toggled(_row, *_args):
            active = self._edit_row.get_active()
            self._data["editMode"] = active
            self._notify_dirty()
            # Tell the running shell to enter/exit edit mode immediately via
            # IPC. Use the absolute shell_core.sh path resolved robustly so
            # it works regardless of PATH inside the settings app.
            retro_dir = os.environ.get("RETRO_DIR") or ""
            if not retro_dir:
                retro = shutil.which("retro")
                if retro:
                    retro_dir = os.path.dirname(os.path.dirname(os.path.abspath(retro)))
            if not retro_dir:
                retro_dir = "/opt/retrolinux"
            core = os.path.join(retro_dir, "scripts", "shell_core.sh")
            try:
                res = subprocess.run(
                    ["bash", core, "--run", f"desktop-edit {'on' if active else 'off'}"],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    timeout=5,
                )
                print(f"[ShellDesktop] editMode toggle -> {'on' if active else 'off'} "
                      f"core={core} rc={res.returncode} out={res.stdout.strip()} err={res.stderr.strip()}",
                      file=sys.stderr)
            except Exception as exc:  # never let IPC failure break the toggle
                print(f"[ShellDesktop] editMode IPC failed: {exc}", file=sys.stderr)

        self._edit_row.connect("notify::active", _on_edit_toggled)
        self._widget_group.add(self._edit_row)
        content_box.append(self._widget_group)
        content_box.append(make_inline_hint(
            "Enable Edit Mode, then drag the widgets on your desktop to position them."
        ))
        self._rebuild_widgets()

        return toolbar

    # ── Widget list ──

    def _rebuild_widgets(self, focus_idx: int = -1) -> None:
        if self._widget_group is None:
            return
        group = self._widget_group
        for row in self._widget_rows:
            group.remove(row)
        self._widget_rows = []

        for idx, wid in enumerate(self._widget_order):
            label, desc, icon = DESKTOP_WIDGET_CATALOG.get(
                wid, (wid, "", "view-list-symbolic")
            )
            row = Adw.ActionRow(title=label, subtitle=desc)
            row.set_subtitle_lines(1)

            icon_img = Gtk.Image.new_from_icon_name(icon)
            icon_img.set_pixel_size(24)
            icon_img.add_css_class("dim-label")
            row.add_prefix(icon_img)

            handle = Gtk.Image.new_from_icon_name("drag-handle-symbolic")
            handle.set_opacity(0.5)
            handle.set_valign(Gtk.Align.CENTER)
            row.add_suffix(handle)

            if wid in CLOCK_FACES:
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Change face")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_face(i))
                row.add_suffix(edit_btn)
            elif wid == "storage":
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Choose storage device")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_storage(i))
                row.add_suffix(edit_btn)
            elif wid in ("network", "network2x4", "network1x4", "network1x3"):
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Network widget options")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_network(i))
                row.add_suffix(edit_btn)
            elif wid == "bluetooth":
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Bluetooth priority")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_bluetooth(i))
                row.add_suffix(edit_btn)
            elif wid == "note":
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Choose note")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_note(i))
                row.add_suffix(edit_btn)
            elif wid in ("batteryring", "batteryring2x4"):
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Battery rings options")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_batteryring(i))
                row.add_suffix(edit_btn)
            elif wid == "feed":
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Feed options")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_feed(i))
                row.add_suffix(edit_btn)
            elif wid in ("photo", "photo2x4", "photo4x2"):
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Choose image")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_photo(i))
                row.add_suffix(edit_btn)
            elif wid == "worldclock":
                edit_btn = Gtk.Button(icon_name="preferences-system-symbolic")
                edit_btn.set_valign(Gtk.Align.CENTER)
                edit_btn.add_css_class("flat")
                edit_btn.set_tooltip_text("Edit timezones")
                edit_btn.connect("clicked", lambda _b, i=idx: self._on_edit_timezones(i))
                row.add_suffix(edit_btn)

            remove_btn = Gtk.Button(icon_name="user-trash-symbolic")
            remove_btn.set_valign(Gtk.Align.CENTER)
            remove_btn.add_css_class("flat")
            remove_btn.set_tooltip_text("Remove from desktop")
            remove_btn.connect("clicked", lambda _b, i=idx: self._on_remove_widget(i))
            row.add_suffix(remove_btn)

            self._widget_reorder.attach(row, idx)
            group.add(row)
            self._widget_rows.append(row)

        if focus_idx >= 0 and focus_idx < len(self._widget_rows):
            self._widget_rows[focus_idx].grab_focus()

    def _move_widget(self, src: int, dst: int) -> bool:
        n = len(self._widgets)
        if dst == src or not (0 <= src < n and 0 <= dst < n):
            return False
        item = self._widgets.pop(src)
        self._widgets.insert(dst, item)
        self._widget_order = [w.get("id") for w in self._widgets]
        self._notify_dirty()
        self._rebuild_widgets(dst)
        return True

    def _on_add_widget(self, _btn=None) -> None:
        available = [w for w in DESKTOP_WIDGET_CATALOG if w not in self._widget_order]
        if not available:
            self._window.show_toast("All widgets are already added", timeout=2)
            return

        group = Adw.PreferencesGroup()
        combo = Adw.ComboRow(title="Widget")
        combo.set_model(Gtk.StringList.new(
            [DESKTOP_WIDGET_CATALOG[w][0] for w in available]
        ))
        combo.set_selected(0)
        group.add(combo)

        dialog = Adw.AlertDialog(
            heading="Add Desktop Widget",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("add", "Add")
        dialog.set_default_response("add")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "add":
                return
            idx = combo.get_selected()
            if 0 <= idx < len(available):
                wid = available[idx]
                width, height = DESKTOP_WIDGET_SIZES.get(wid, (280, 300))
                # Position at center by default (0.5, 0.5 normalized).
                self._widgets.append({
                    "id": wid,
                    "type": wid,
                    "x": 0.5,
                    "y": 0.5,
                    "width": width,
                    "height": height,
                })
                self._widget_order = [w.get("id") for w in self._widgets]
                self._notify_dirty()
                self._rebuild_widgets()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    def _on_remove_widget(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._widgets):
            return
        wid = self._widgets[idx].get("id")
        self._removed_ids.add(wid)
        self._widgets = [w for w in self._widgets if w.get("id") != wid]
        self._widget_order = [w.get("id") for w in self._widgets]
        self._notify_dirty()
        self._rebuild_widgets()

    # ── Clock face editor ──

    def _on_edit_face(self, idx: int) -> None:
        """Let the user pick the face/style of a clock or battery widget."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]
        wid = widget.get("id")
        faces = CLOCK_FACES.get(wid, [])
        if not faces:
            return
        current = widget.get("face") or "classic"
        if current not in faces:
            current = faces[0]

        group = Adw.PreferencesGroup()
        combo = Adw.ComboRow(title="Face")
        combo.set_model(Gtk.StringList.new(
            [CLOCK_FACE_LABELS.get(f, f) for f in faces]
        ))
        combo.set_selected(faces.index(current))
        group.add(combo)

        hand_combo = None
        hand_ids: list[str] = []
        hand_styles = CLOCK_HAND_STYLES.get(wid, [])
        if hand_styles:
            hand_ids = list(hand_styles)
            cur_hand = widget.get("handStyle") or "taper"
            if cur_hand not in hand_ids:
                cur_hand = hand_ids[0]
            hand_combo = Adw.ComboRow(title="Hand style",
                                      subtitle="How the clock hands are drawn")
            hand_combo.set_model(Gtk.StringList.new(
                [CLOCK_HAND_STYLE_LABELS.get(h, h) for h in hand_styles]
            ))
            hand_combo.set_selected(hand_ids.index(cur_hand))
            group.add(hand_combo)

        dialog = Adw.AlertDialog(
            heading="Widget Face",
            body="Choose the face style for this widget.",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "save":
                return
            sel = combo.get_selected()
            if 0 <= sel < len(faces):
                widget["face"] = faces[sel]
            if hand_combo is not None:
                hs = hand_combo.get_selected()
                if 0 <= hs < len(hand_ids):
                    widget["handStyle"] = hand_ids[hs]
            self._notify_dirty()
            self._rebuild_widgets()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Storage device editor ──

    @staticmethod
    def _list_storage_devices() -> list[str]:
        """Detected block-device mount points (e.g. ['/', '/home'])."""
        devices = []

        def _collect(node):
            for mp in node.get("mountpoints", []) or []:
                if mp and not mp.startswith("[") and mp not in devices:
                    devices.append(mp)
            for child in node.get("children", []) or []:
                _collect(child)

        try:
            out = subprocess.run(
                ["lsblk", "-J", "-o", "NAME,MOUNTPOINTS"],
                capture_output=True, text=True, timeout=5,
            )
            if out.returncode == 0 and out.stdout.strip():
                data = json.loads(out.stdout)
                for block in data.get("blockdevices", []):
                    _collect(block)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            pass
        if not devices:
            devices = ["/"]
        return devices

    def _on_edit_storage(self, idx: int) -> None:
        """Let the user pick which storage device the widget displays."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]
        devices = self._list_storage_devices()
        current = widget.get("device") or (devices[0] if devices else "/")
        if current not in devices:
            current = devices[0] if devices else "/"

        group = Adw.PreferencesGroup()
        combo = Adw.ComboRow(title="Storage device")
        combo.set_model(Gtk.StringList.new(devices))
        combo.set_selected(devices.index(current))
        group.add(combo)

        dialog = Adw.AlertDialog(
            heading="Device Storage",
            body="Pick the storage device this widget should measure.",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "save":
                return
            sel = combo.get_selected()
            if 0 <= sel < len(devices):
                widget["device"] = devices[sel]
                self._notify_dirty()
                self._rebuild_widgets()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Network widget editor ──

    def _on_edit_network(self, idx: int) -> None:
        """Let the user choose whether the public IP is hidden by default."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]
        current = widget.get("hideIp", True)

        group = Adw.PreferencesGroup()
        switch = Adw.SwitchRow(title="Hide public IP by default",
                               subtitle="Mask the WAN address; reveal with the eye icon")
        switch.set_active(bool(current))
        group.add(switch)

        dialog = Adw.AlertDialog(
            heading="Network Monitor",
            body="Options for the network widget.",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "save":
                return
            widget["hideIp"] = bool(switch.get_active())
            self._notify_dirty()
            self._rebuild_widgets()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Bluetooth widget editor ──

    def _on_edit_bluetooth(self, idx: int) -> None:
        """Let the user pick which device type is shown first when connected."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]

        priority_options = [
            ("automatic", "Automatic"),
            ("audio", "Headphones / Audio"),
            ("gamepad", "Gamepad"),
            ("phone", "Phone"),
            ("mouse", "Mouse"),
            ("keyboard", "Keyboard"),
            ("watch", "Watch"),
            ("speaker", "Speaker"),
            ("other", "Other"),
        ]
        labels = [label for _pid, label in priority_options]
        ids = [pid for pid, _label in priority_options]
        current = widget.get("devicePriority") or "automatic"
        if current not in ids:
            current = "automatic"

        group = Adw.PreferencesGroup()
        combo = Adw.ComboRow(title="Priority device type",
                             subtitle="Which connected device is shown first")
        combo.set_model(Gtk.StringList.new(labels))
        combo.set_selected(ids.index(current))
        group.add(combo)

        dialog = Adw.AlertDialog(
            heading="Bluetooth Widget",
            body="Choose which type of connected device to display first.",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "save":
                return
            sel = combo.get_selected()
            if 0 <= sel < len(ids):
                widget["devicePriority"] = ids[sel]
                self._notify_dirty()
                self._rebuild_widgets()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Note widget editor ──

    @staticmethod
    def _list_notes() -> list[dict]:
        """Notes from the retroshell notes store: [{id, title, label}]."""
        base = os.path.expanduser("~/.local/share/retroshell-notes")
        try:
            with open(os.path.join(base, "index.json")) as f:
                data = json.load(f)
        except (OSError, ValueError):
            return []
        notes = []
        for nid in data.get("order", []):
            meta = (data.get("notes", {}) or {}).get(nid)
            if not meta:
                continue
            title = meta.get("title", "Untitled")
            ext = ".md" if meta.get("isMarkdown") else ".html"
            preview = ""
            try:
                with open(os.path.join(base, "notes", nid + ext)) as f:
                    for line in f:
                        line = line.strip().strip("#").strip()
                        if line and line != title:
                            preview = line
                            break
            except OSError:
                pass
            label = title
            if preview:
                label = "%s — %s" % (title, preview[:28])
            notes.append({"id": nid, "title": title, "label": label})
        return notes

    def _on_edit_note(self, idx: int) -> None:
        """Let the user pick note, font size, background and fullscreen."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]
        notes = self._list_notes()
        current = widget.get("noteId") or ""

        group = Adw.PreferencesGroup()

        note_combo = None
        ids: list[str] = []
        if notes:
            labels = [n["label"] for n in notes]
            ids = [n["id"] for n in notes]
            sel = 0
            if current in ids:
                sel = ids.index(current)
            note_combo = Adw.ComboRow(title="Note to display",
                                      subtitle="Defaults to the most recent note")
            note_combo.set_model(Gtk.StringList.new(labels))
            note_combo.set_selected(sel)
            group.add(note_combo)

        font_row, font_spin = make_spin_int_row(
            "Font size",
            value=int(widget.get("fontSize", 11)),
            lower=8,
            upper=24,
            step=1,
            page_step=2,
            subtitle="Size of the note text",
        )
        group.add(font_row)
        suffix_lbl = Gtk.Label(label="px")
        suffix_lbl.add_css_class("dim-label")
        suffix_lbl.set_valign(Gtk.Align.CENTER)
        font_row.add_suffix(suffix_lbl)

        fullscreen_switch = Adw.SwitchRow(
            title="Open in fullscreen on click",
            subtitle="Show the note in the full notes editor instead of editing inline",
        )
        fullscreen_switch.set_active(bool(widget.get("openFullscreen", False)))
        group.add(fullscreen_switch)

        dialog = Adw.AlertDialog(
            heading="Note Widget",
            body="Configure the note widget.",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "save":
                return
            if note_combo is not None:
                s = note_combo.get_selected()
                if 0 <= s < len(ids):
                    widget["noteId"] = ids[s]
            widget["fontSize"] = int(font_spin.get_value())
            widget["openFullscreen"] = bool(fullscreen_switch.get_active())
            self._notify_dirty()
            self._rebuild_widgets()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Battery rings widget editor ──

    @staticmethod
    def _list_bluetooth_devices() -> list[dict]:
        """Paired bluetooth devices: [{id, name}] (address + alias)."""
        try:
            out = subprocess.run(
                ["bluetoothctl", "devices"],
                capture_output=True, text=True, timeout=5,
            )
            known = []
            for line in out.stdout.splitlines():
                parts = line.split(" ")
                if len(parts) >= 2 and parts[0] == "Device":
                    known.append((parts[1], " ".join(parts[2:]) or "Unknown device"))

            devices = []
            for addr, name in known[:15]:
                try:
                    info = subprocess.run(
                        ["bluetoothctl", "info", addr],
                        capture_output=True, text=True, timeout=3,
                    )
                    if "Paired: yes" in info.stdout:
                        devices.append({"id": addr, "name": name})
                except (OSError, subprocess.TimeoutExpired):
                    continue
            return devices
        except (OSError, subprocess.TimeoutExpired):
            return []

    def _on_edit_batteryring(self, idx: int) -> None:
        """Let the user choose which devices the battery rings show."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]
        hidden = widget.get("hiddenDevices") or []

        group = Adw.PreferencesGroup()

        host_switch = Adw.SwitchRow(title="Host battery",
                                    subtitle="Show the laptop's battery")
        host_switch.set_active("host" not in hidden)
        group.add(host_switch)

        device_switches = []
        for dev in self._list_bluetooth_devices():
            sw = Adw.SwitchRow(title=dev["name"], subtitle=dev["id"])
            sw.set_active(dev["id"] not in hidden)
            group.add(sw)
            device_switches.append((dev["id"], sw))

        dialog = Adw.AlertDialog(
            heading="Battery Rings",
            body="Choose which devices appear. Only connected devices with a "
                 "battery reading are shown.",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "save":
                return
            new_hidden = []
            if not host_switch.get_active():
                new_hidden.append("host")
            for dev_id, sw in device_switches:
                if not sw.get_active():
                    new_hidden.append(dev_id)
            widget["hiddenDevices"] = new_hidden
            self._notify_dirty()
            self._rebuild_widgets()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Feed editor ──

    def _on_edit_feed(self, idx: int) -> None:
        """Let the user pick source, query, daily.dev key and auto-swipe."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]

        source_options = [
            ("devto", "DEV.to"),
            ("hackernews", "Hacker News"),
            ("dailydev", "daily.dev (needs API key)"),
        ]
        source_labels = [label for _v, label in source_options]
        source_ids = [v for v, _l in source_options]
        cur_source = widget.get("source") or "devto"
        if cur_source not in source_ids:
            cur_source = "devto"

        query_options = [
            ("", "All topics"),
            ("linux", "linux"),
            ("rust", "rust"),
            ("webdev", "webdev"),
            ("javascript", "javascript"),
            ("typescript", "typescript"),
            ("python", "python"),
            ("go", "go"),
            ("java", "java"),
            ("devops", "devops"),
            ("security", "security"),
            ("cloud", "cloud"),
            ("kubernetes", "kubernetes"),
            ("database", "database"),
            ("ai", "ai"),
            ("machine-learning", "machine-learning"),
            ("react", "react"),
            ("opensource", "opensource"),
            ("productivity", "productivity"),
            ("career", "career"),
            ("hardware", "hardware"),
        ]
        query_labels = [label for _v, label in query_options]
        query_ids = [v for v, _l in query_options]
        cur_query = widget.get("tag") or ""
        # Custom topics not in the list → show in the entry instead.
        is_custom = cur_query not in query_ids and cur_query != ""

        group = Adw.PreferencesGroup()

        source_combo = Adw.ComboRow(title="Source", subtitle="Where articles come from")
        source_combo.set_model(Gtk.StringList.new(source_labels))
        source_combo.set_selected(source_ids.index(cur_source))
        group.add(source_combo)

        query_combo = Adw.ComboRow(title="Topic", subtitle="Preset tag / search query")
        query_combo.set_model(Gtk.StringList.new(query_labels))
        query_combo.set_selected(query_ids.index(cur_query) if not is_custom else 0)
        group.add(query_combo)

        custom_entry = Gtk.Entry(placeholder_text="Custom topic (e.g. gamedev, embedded)")
        custom_entry.set_text(cur_query if is_custom else "")
        custom_entry.set_hexpand(True)
        custom_row = Adw.ActionRow(title="Custom topic",
                                   subtitle="Overrides the preset topic")
        custom_row.add_suffix(custom_entry)
        group.add(custom_row)

        key_entry = Gtk.PasswordEntry(placeholder_text="daily.dev API key")
        key_entry.set_text(widget.get("apiKey", ""))
        key_entry.set_hexpand(True)
        key_entry.set_sensitive(cur_source == "dailydev")
        key_row = Adw.ActionRow(title="daily.dev API key",
                                subtitle="Required only for daily.dev")
        key_row.add_suffix(key_entry)
        group.add(key_row)

        def _on_source_changed(_row, *_args):
            sel = source_combo.get_selected()
            is_daily = 0 <= sel < len(source_ids) and source_ids[sel] == "dailydev"
            key_entry.set_sensitive(is_daily)

        source_combo.connect("notify::selected", _on_source_changed)

        auto_switch = Adw.SwitchRow(title="Auto-swipe",
                                    subtitle="Advance to the next article automatically")
        auto_switch.set_active(bool(widget.get("autoSwipe", True)))
        group.add(auto_switch)

        font_interval, interval_spin = make_spin_int_row(
            "Auto-swipe interval",
            value=int(widget.get("swipeInterval", 30)),
            lower=10, upper=120, step=5, page_step=10,
            subtitle="Seconds between automatic swipes",
        )
        group.add(font_interval)
        suffix_lbl = Gtk.Label(label="sec")
        suffix_lbl.add_css_class("dim-label")
        suffix_lbl.set_valign(Gtk.Align.CENTER)
        font_interval.add_suffix(suffix_lbl)

        count_row, count_spin = make_spin_int_row(
            "Articles to preload",
            value=int(widget.get("count", 5)),
            lower=3, upper=10, step=1, page_step=2,
            subtitle="How many articles to load (3–10)",
        )
        group.add(count_row)
        count_suffix = Gtk.Label(label="articles")
        count_suffix.add_css_class("dim-label")
        count_suffix.set_valign(Gtk.Align.CENTER)
        count_row.add_suffix(count_suffix)

        dialog = Adw.AlertDialog(
            heading="Dev Feed",
            body="Configure the article feed widget.",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "save":
                return
            s = source_combo.get_selected()
            if 0 <= s < len(source_ids):
                widget["source"] = source_ids[s]
            custom = custom_entry.get_text().strip()
            if custom:
                widget["tag"] = custom
            else:
                q = query_combo.get_selected()
                if 0 <= q < len(query_ids):
                    widget["tag"] = query_ids[q]
            widget["apiKey"] = key_entry.get_text().strip()
            widget["autoSwipe"] = bool(auto_switch.get_active())
            widget["swipeInterval"] = int(interval_spin.get_value())
            widget["count"] = int(count_spin.get_value())
            self._notify_dirty()
            self._rebuild_widgets()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Photo widget image picker ──

    def _on_edit_photo(self, idx: int) -> None:
        """Let the user pick an image file for the photo widget."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]

        dialog = Gtk.FileDialog()
        dialog.set_title("Choose an image")
        filt = Gtk.FileFilter()
        filt.set_name("Images")
        for mime in ("image/png", "image/jpeg", "image/webp", "image/svg+xml", "image/gif", "image/bmp"):
            filt.add_mime_type(mime)
        filters = Gio.ListStore.new(Gtk.FileFilter)
        filters.append(filt)
        dialog.set_filters(filters)

        current_path = widget.get("imagePath") or ""
        current_name = os.path.basename(current_path) if current_path else ""

        group = Adw.PreferencesGroup()

        path_row = Adw.ActionRow(title="Current image", subtitle=current_name or "(placeholder)")
        group.add(path_row)

        clear_btn = Gtk.Button(label="Clear image")
        clear_btn.set_valign(Gtk.Align.CENTER)
        clear_btn.add_css_class("flat")
        clear_btn.set_tooltip_text("Remove image and show default placeholder")

        def _on_clear(_btn):
            widget["imagePath"] = ""
            self._notify_dirty()
            self._rebuild_widgets()

        clear_btn.connect("clicked", _on_clear)
        path_row.add_suffix(clear_btn)

        border_switch = Adw.SwitchRow(
            title="Show border",
            subtitle="Display the themed inner border around the image",
        )
        border_switch.set_active(bool(widget.get("showBorder", True)))
        group.add(border_switch)

        dlg = Adw.AlertDialog(
            heading="Photo Widget",
            body="Set a custom image for this widget.",
            extra_child=group,
        )
        dlg.add_response("pick", "Choose image")
        dlg.add_response("cancel", "Close")
        dlg.set_default_response("pick")
        dlg.set_close_response("cancel")

        def _on_response(_dlg_obj, response):
            if response == "pick":
                def on_chosen(_file_dlg, result):
                    try:
                        gfile = _file_dlg.open_finish(result)
                    except GLib.Error:
                        return
                    if not gfile:
                        return
                    path = gfile.get_path()
                    if not path or not os.path.isfile(path):
                        return
                    widget["imagePath"] = path
                    widget["showBorder"] = bool(border_switch.get_active())
                    self._notify_dirty()
                    self._rebuild_widgets()

                dialog.open(self._window, None, on_chosen)
            else:
                widget["showBorder"] = bool(border_switch.get_active())
                self._notify_dirty()
                self._rebuild_widgets()

        dlg.connect("response", _on_response)
        dlg.present(self._window)

    # ── World clock timezone editor ──

    def _on_edit_timezones(self, idx: int) -> None:
        """Let the user set up to 4 IANA timezones for the world clock widget."""
        if idx < 0 or idx >= len(self._widgets):
            return
        widget = self._widgets[idx]
        current = widget.get("timezones") or ["UTC"]

        group = Adw.PreferencesGroup()
        group.add(Adw.ActionRow(
            title="Enter up to 4 IANA timezone names",
            subtitle="e.g. UTC, Europe/Paris, America/New_York, Asia/Tokyo",
        ))
        entries = []
        for slot in range(4):
            value = current[slot] if slot < len(current) else ""
            entry = Gtk.Entry(placeholder_text="Timezone %d" % (slot + 1))
            entry.set_text(value)
            entry.set_hexpand(True)
            row = Adw.ActionRow(title="Timezone %d" % (slot + 1))
            row.add_suffix(entry)
            group.add(row)
            entries.append(entry)

        dialog = Adw.AlertDialog(
            heading="World Clock Timezones",
            body="The widget shows one column per timezone (up to 4).",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "save":
                return
            valid = []
            invalid = []
            for entry in entries:
                zone = entry.get_text().strip()
                if not zone:
                    continue
                if _is_valid_timezone(zone):
                    if zone not in valid:
                        valid.append(zone)
                elif zone not in invalid:
                    invalid.append(zone)
                if len(valid) == 4:
                    break
            widget["timezones"] = valid or ["UTC"]
            self._notify_dirty()
            self._rebuild_widgets()
            if invalid:
                warn = Adw.AlertDialog(
                    heading="Invalid Timezones Ignored",
                    body=("The following timezones were not saved because they "
                          "aren't valid IANA names:\n\n") + "\n".join(invalid),
                )
                warn.add_response("ok", "OK")
                warn.set_default_response("ok")
                warn.present(self._window)

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Simple rows (icon grid) ──

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "", default_value: bool = False) -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, default_value)))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=default_value,
            baseline=self._saved.get(key, default_value),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(row, "notify::active", key, mrow)
        return mrow

    def _add_spin(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        *,
        lower: int,
        upper: int,
        suffix: str,
        subtitle: str = "",
    ) -> ManagedRow:
        row, spin = make_spin_int_row(
            label,
            value=int(self._data.get(key, 40)),
            lower=lower,
            upper=upper,
            step=1,
            page_step=5,
            subtitle=subtitle,
        )
        group.add(row)
        if suffix:
            suffix_lbl = Gtk.Label(label=suffix)
            suffix_lbl.add_css_class("dim-label")
            suffix_lbl.set_valign(Gtk.Align.CENTER)
            row.add_suffix(suffix_lbl)

        def get_value():
            return int(spin.get_value())

        def set_silent(value):
            spin.set_value(int(value))

        mrow = ManagedRow(
            row,
            default=40,
            baseline=self._saved.get(key, 40),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(spin, "value-changed", key, mrow)
        return mrow

    def _add_color_combo(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        *,
        subtitle: str = "",
    ) -> ManagedRow:
        current = str(self._data.get(key, "overBackground"))
        row, ids = _make_named_color_combo_row(label, current, subtitle=subtitle)
        group.add(row)

        def get_value():
            idx = row.get_selected()
            return ids[idx] if 0 <= idx < len(ids) else ids[0]

        def set_silent(value):
            try:
                row.set_selected(ids.index(str(value)))
            except ValueError:
                row.set_selected(0)

        mrow = ManagedRow(
            row,
            default="overBackground",
            baseline=self._saved.get(key, "overBackground"),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(row, "notify::selected", key, mrow)
        return mrow

    def _wire_change(self, widget: Gtk.Widget, signal: str, key: str, mrow: ManagedRow) -> None:
        def _changed(*_args):
            self._data[key] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        widget.connect(signal, _changed)

    def _on_change(self, key: str, value) -> None:
        self._data[key] = value
        self._notify_dirty()

    def _merged_widgets(self) -> list[dict]:
        """Build the list to persist, preserving the shell's live state.

        The shell updates widget positions (drag) directly in
        desktop_widgets.json. The settings page only manages the widget list
        (add/remove/reorder), so before writing we re-read the on-disk
        widgets and:
          - keep the shell's latest x/y/locked for any widget we know about,
          - never drop on-disk widgets we weren't aware of (e.g. the page
            loaded before they existed), so an unrelated settings change
            can't wipe them,
          - only drop widgets the user explicitly removed this session.
        """
        disk = {w.get("id"): w for w in load_desktop_widgets() if w.get("id")}
        for wid in self._removed_ids:
            disk.pop(wid, None)

        merged = []
        for w in self._widgets:
            wid = w.get("id")
            existing = disk.pop(wid, None)
            if existing:
                # Preserve the shell's live state (x/y/locked) AND any extra
                # fields the shell or settings page stored (face, timezones).
                entry = dict(existing)
                entry["id"] = wid
                entry["type"] = w.get("type", existing.get("type", wid))
                for extra in ("face", "handStyle", "timezones", "device", "hideIp", "devicePriority", "noteId", "openFullscreen", "fontSize", "hiddenDevices", "tag", "monitor", "source", "apiKey", "autoSwipe", "swipeInterval", "count", "imagePath", "showBorder"):
                    if w.get(extra) is not None:
                        entry[extra] = w[extra]
                merged.append(entry)
            else:
                merged.append(w)  # newly added this session

        # Any on-disk widgets the settings page wasn't aware of (loaded empty
        # or created after the page opened) are kept as-is.
        for wid, existing in disk.items():
            merged.append(existing)
        return merged

    def _write_live(self) -> None:
        save_desktop(self._data)
        save_desktop_widgets(self._merged_widgets())

    def _notify_dirty(self) -> None:
        self._write_live()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return (self._data != self._saved
                or self._widgets != self._saved_widgets)

    def mark_saved(self) -> None:
        save_desktop(self._data)
        save_desktop_widgets(self._merged_widgets())
        self._saved = dict(self._data)
        self._saved_widgets = [dict(w) for w in self._widgets]
        self._saved_widget_order = [w.get("id") for w in self._widgets]
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key))

    def discard(self) -> None:
        self._data = dict(self._saved)
        self._widgets = [dict(w) for w in self._saved_widgets]
        self._widget_order = [w.get("id") for w in self._widgets]
        self._removed_ids = set()
        for mrow in self._rows.values():
            mrow.discard()
        if self._edit_row is not None:
            self._edit_row.set_active(bool(self._data.get("editMode", False)))
        self._write_live()
        self._rebuild_widgets()

    def reload_from_disk(self) -> None:
        """Re-read desktop.json + desktop_widgets.json and sync widgets."""
        self._data = load_desktop()
        self._saved = dict(self._data)
        self._widgets = load_desktop_widgets()
        self._saved_widgets = [dict(w) for w in self._widgets]
        self._widget_order = [w.get("id") for w in self._widgets]
        self._saved_widget_order = list(self._widget_order)
        self._removed_ids = set()
        for key, mrow in self._rows.items():
            value = self._data.get(key)
            mrow.apply_value(value)
            mrow.set_baseline(value)
        if self._edit_row is not None:
            self._edit_row.set_active(bool(self._data.get("editMode", False)))
        self._rebuild_widgets()

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                label = {
                    "enabled": "Enabled",
                    "showIcons": "Show Icons",
                    "iconSize": "Icon Size",
                    "spacingVertical": "Spacing",
                    "textColor": "Text Color",
                }.get(key, "Desktop setting")
                changed.append(label)
        if self._widgets != self._saved_widgets:
            changed.append("Widgets")
        if "editMode" in self._data and self._data.get("editMode") != self._saved.get("editMode"):
            changed.append("Edit Mode")
        if changed:
            yield PendingChange(
                category="Shell Desktop",
                title="Desktop",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_desktop",
                icon=DESKTOP_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_desktop:desktop", "label": "Desktop",
             "description": "Desktop icon grid: size, spacing and text color",
             "_group_id": "shell_desktop", "_group_label": "Desktop", "_section_label": "Desktop"},
            {"key": "shell_desktop:widgets", "label": "Desktop Widgets",
             "description": "Add, remove and reorder desktop widgets",
             "_group_id": "shell_desktop", "_group_label": "Desktop", "_section_label": "Widgets"},
        ]


__all__ = ["ShellDesktopPage"]
