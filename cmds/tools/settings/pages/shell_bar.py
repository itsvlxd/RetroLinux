"""Shell Bar page — configure the Retro Shell top bar (``bar.json``).

Mirrors the Bar and Auto-hide sections of the in-shell ``ShellPanel.qml``
(its Frame section lives in the separate ``shell_frame`` page). Values are
written to ``~/.config/retro/shell/bar.json``; the shell's ``FileView``
watches that file with ``watchChanges`` and reloads on external writes, so
changes apply live without a shell restart.

Writes are gated by the settings window's save/discard lifecycle: edits
are staged in memory (``_data`` vs the ``_saved`` snapshot) and only
persisted on Save, exactly like the other standalone pages.
"""

from collections.abc import Iterable
import shutil
from typing import TYPE_CHECKING, cast

from gi.repository import Adw, GLib, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import (
    BAR_DEFAULTS,
    BAR_ITEMS,
    BAR_LEFT_DEFAULT_ORDER,
    BAR_LEFT_ITEMS,
    BAR_MIN_ITEMS,
    BAR_RIGHT_DEFAULT_ORDER,
    BAR_RIGHT_ITEMS,
    CLOCK_DEFAULT_ORDER,
    CLOCK_ITEMS,
    CLOCK_MIN_ITEMS,
    TOOLBOX_ITEMS,
    TOOLBOX_MIN_ITEMS,
    load_bar,
    save_bar,
)
from settings.ui import make_page_layout
from settings.ui.icons import BAR_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row
from settings.ui.reorder import RowReorderController

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow


def _which(binary: str) -> bool:
    return shutil.which(binary) is not None


def _markup(text: str) -> str:
    """Escape text for use as an Adw row title/subtitle (parsed as markup)."""
    return GLib.markup_escape_text(text, -1)

# (key, config default) pairs rendered as an Adw.SwitchRow
_SWITCH_KEYS = (
    ("launcherIconTint", "Launcher Icon Tint"),
    ("launcherIconFullTint", "Launcher Icon Full Tint"),
    ("use12hFormat", "Use 12h Format"),
    ("enableFirefoxPlayer", "Enable Firefox Player"),
    ("pinnedOnStartup", "Pinned on Startup"),
    ("hoverToReveal", "Hover to Reveal"),
    ("showPinButton", "Show Pin Button"),
    ("availableOnFullscreen", "Available on Fullscreen"),
)

_POSITION_OPTIONS = [
    ("top", "Top"),
    ("bottom", "Bottom"),
    ("left", "Left"),
    ("right", "Right"),
]

_PILL_OPTIONS = [
    ("default", "Default"),
    ("squished", "Squished"),
]

_BATTERY_STYLE_OPTIONS = [
    ("arch", "Arch"),
    ("bar", "Bar"),
]


class ShellBarPage:
    """Shell bar configuration — writes ``bar.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_bar()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

        # Toolbox order (persisted in bar.json)
        self._tools_order: list[str] = list(
            self._data.get("toolboxOrder") or list(TOOLBOX_ITEMS)
        )
        self._saved_tools_order: list[str] = list(self._tools_order)
        self._toolbox_rows: list[Adw.ActionRow] = []
        self._toolbox_group: Adw.ExpanderRow | None = None
        self._toolbox_reorder = RowReorderController(
            move=self._move_toolbox, iter_rows=lambda: self._toolbox_rows
        )

        # Clock popup section order (persisted in bar.json). The "clock" bar
        # item doubles as the accordion revealing these reorderable sections.
        self._clock_order: list[str] = list(
            self._data.get("clockOrder") or list(CLOCK_DEFAULT_ORDER)
        )
        self._saved_clock_order: list[str] = list(self._clock_order)
        self._clock_rows: list[Adw.ActionRow] = []
        self._clock_group: Adw.ExpanderRow | None = None
        self._clock_reorder = RowReorderController(
            move=self._move_clock, iter_rows=lambda: self._clock_rows
        )

        # Bar item order, shared across the left/right groups. ``_bar_order``
        # is the global drag order; ``_bar_side`` maps each id to its side so an
        # item can be dragged between the two groups. Persisted as
        # ``barLeftOrder``/``barRightOrder``.
        self._bar_order: list[str] = list(
            self._data.get("barLeftOrder") or list(BAR_LEFT_DEFAULT_ORDER)
        ) + list(self._data.get("barRightOrder") or list(BAR_RIGHT_DEFAULT_ORDER))
        self._bar_side: dict[str, str] = {}
        for it in (self._data.get("barLeftOrder") or list(BAR_LEFT_DEFAULT_ORDER)):
            self._bar_side[it] = "left"
        for it in (self._data.get("barRightOrder") or list(BAR_RIGHT_DEFAULT_ORDER)):
            self._bar_side[it] = "right"
        self._saved_bar_order: list[str] = list(self._bar_order)
        self._saved_bar_side: dict[str, str] = dict(self._bar_side)
        self._left_rows: list[Adw.ActionRow] = []
        self._right_rows: list[Adw.ActionRow] = []
        self._left_group: Adw.PreferencesGroup | None = None
        self._right_group: Adw.PreferencesGroup | None = None
        self._bar_reorder = RowReorderController(
            move=self._move_bar,
            iter_rows=lambda: self._left_rows + self._right_rows,
        )

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        bar_group = Adw.PreferencesGroup(
            title="Bar",
            description="Position, launcher icon, and clock format.",
        )
        self._build_bar_group(bar_group)
        content_box.append(bar_group)

        self._left_group = Adw.PreferencesGroup(
            title="Left Bar",
            description="Items on the left of the bar. Drag to reorder or "
                        "move an item to the right side.",
        )
        self._build_bar_group_rows(self._left_group, "left")
        content_box.append(self._left_group)

        self._right_group = Adw.PreferencesGroup(
            title="Right Bar",
            description="Items on the right of the bar. Drag to reorder or "
                        "move an item to the left side.",
        )
        self._build_bar_group_rows(self._right_group, "right")
        content_box.append(self._right_group)

        autohide_group = Adw.PreferencesGroup(
            title="Auto-hide",
            description="When the bar hides itself and how it comes back.",
        )
        self._build_autohide_group(autohide_group)
        content_box.append(autohide_group)

        return toolbar

    # ── Groups ──

    def _build_bar_group(self, group: Adw.PreferencesGroup) -> None:
        self._add_combo(group, "position", "Position", _POSITION_OPTIONS,
                        subtitle="Which screen edge the bar is attached to")
        self._add_entry(group, "launcherIcon", "Launcher Icon",
                        placeholder="Symbol or path to icon…",
                        subtitle="Symbol name or path to a custom icon")
        for key, label, sub in (
            ("launcherIconTint", "Launcher Icon Tint", "Tint the launcher icon with the theme accent"),
            ("launcherIconFullTint", "Launcher Icon Full Tint", "Tint the whole icon, not just its outline"),
        ):
            self._add_switch(group, key, label, subtitle=sub)
        self._add_spin(group, "launcherIconSize", "Launcher Icon Size",
                       lower=12, upper=64, suffix="px",
                       subtitle="Size of the launcher icon")
        self._add_combo(group, "pillStyle", "Pill Style", _PILL_OPTIONS,
                        subtitle="Shape of the launcher pill")
        self._add_combo(group, "batteryStyle", "Battery Style", _BATTERY_STYLE_OPTIONS,
                        subtitle="Progress ring around the icon, or a small bar beneath it")
        for key, label, sub in (
            ("use12hFormat", "Use 12h Format", "Show the clock in 12-hour format"),
            ("enableFirefoxPlayer", "Enable Firefox Player", "Show Firefox media controls in the bar"),
            ("showWeatherTemp", "Show Weather Temperature", "Display temperature in Celsius next to the weather icon"),
            ("showDayOfWeek", "Show Day of Week", "Show the day abbreviation (Mon, Tue...) beside the clock"),
        ):
            self._add_switch(group, key, label, subtitle=sub)

    def _build_autohide_group(self, group: Adw.PreferencesGroup) -> None:
        self._add_switch(group, "pinnedOnStartup", "Pinned on Startup",
                         subtitle="Keep the bar visible when the session starts")
        self._add_switch(group, "hoverToReveal", "Hover to Reveal",
                         subtitle="Show the bar when the mouse reaches the edge")
        self._add_spin(group, "hoverRegionHeight", "Hover Region Height",
                       lower=0, upper=32, suffix="px",
                       subtitle="Height of the edge region that reveals the bar")
        self._add_switch(group, "showPinButton", "Show Pin Button",
                         subtitle="Show a button to pin the bar")
        self._add_switch(group, "availableOnFullscreen", "Available on Fullscreen",
                         subtitle="Keep the bar visible over fullscreen apps")

    # ── Left / Right bar reorder ──

    def _build_bar_group_rows(self, group: Adw.PreferencesGroup, side: str) -> None:
        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text(f"Add an item to the {'left' if side == 'left' else 'right'} side")
        add_btn.connect("clicked", lambda _b, s=side: self._on_add_bar(s))
        group.set_header_suffix(add_btn)
        self._rebuild_bar()

    def _rebuild_bar(self, focus_idx: int = -1) -> None:
        if self._left_group is None or self._right_group is None:
            return
        for row in self._left_rows:
            self._left_group.remove(row)
        for row in self._right_rows:
            self._right_group.remove(row)
        self._left_rows = []
        self._right_rows = []
        self._toolbox_group = None
        self._toolbox_rows = []
        self._clock_group = None
        self._clock_rows = []

        for idx, item in enumerate(self._bar_order):
            side = self._bar_side.get(item, "left")
            title, sub, icon_name = BAR_ITEMS.get(item, (item, "", "view-list-symbolic"))
            group = self._left_group if side == "left" else self._right_group
            side_items = [it for it in self._bar_order if self._bar_side.get(it) == side]

            # The Toolbox bar item doubles as the accordion for the toolbox
            # item order: expanding it reveals the tools in the shell toolbox.
            row: Adw.ActionRow
            if item == "tools":
                expander = Adw.ExpanderRow(title=_markup(title), subtitle=_markup(sub), expanded=False)
                self._toolbox_group = expander
                add_btn = Gtk.Button(icon_name="list-add-symbolic")
                add_btn.set_valign(Gtk.Align.CENTER)
                add_btn.add_css_class("flat")
                add_btn.set_tooltip_text("Add a toolbox item or separator")
                add_btn.connect("clicked", self._on_add_toolbox)
                expander.add_suffix(add_btn)
                row = cast(Adw.ActionRow, expander)
            # The Time, Weather & Calendar bar item doubles as the accordion
            # for the clock popup section order.
            elif item == "clock":
                expander = Adw.ExpanderRow(title=_markup(title), subtitle=_markup(sub), expanded=False)
                self._clock_group = expander
                add_btn = Gtk.Button(icon_name="list-add-symbolic")
                add_btn.set_valign(Gtk.Align.CENTER)
                add_btn.add_css_class("flat")
                add_btn.set_tooltip_text("Add a clock popup section")
                add_btn.connect("clicked", self._on_add_clock)
                expander.add_suffix(add_btn)
                row = cast(Adw.ActionRow, expander)
            else:
                row = Adw.ActionRow(title=_markup(title), subtitle=_markup(sub))
            row.set_subtitle_lines(2)

            icon = Gtk.Image.new_from_icon_name(icon_name)
            icon.set_pixel_size(24)
            icon.add_css_class("dim-label")
            row.add_prefix(icon)

            handle = Gtk.Image.new_from_icon_name("drag-handle-symbolic")
            handle.set_opacity(0.5)
            handle.set_valign(Gtk.Align.CENTER)
            row.add_suffix(handle)

            remove_btn = Gtk.Button(icon_name="user-trash-symbolic")
            remove_btn.set_valign(Gtk.Align.CENTER)
            remove_btn.add_css_class("flat")
            remove_btn.set_tooltip_text("Remove from bar")
            remove_btn.set_sensitive(len(side_items) > BAR_MIN_ITEMS)
            remove_btn.connect("clicked", lambda _b, i=idx: self._on_remove_bar(i))
            row.add_suffix(remove_btn)

            # Every row shares the single controller, using its global combined
            # index so an item can be dragged between the left and right groups.
            # The accordion rows (tools/clock) host nested reorderable children,
            # so their whole-row drag is bound to the drag handle instead: a
            # whole-row drag source would capture the pointer first (ancestors
            # before descendants) and hijack the inner toolbox/clock item drags.
            if item in ("tools", "clock"):
                self._bar_reorder.attach(row, idx, drag=False)
                self._bar_reorder.attach_drag_source_to(handle, row, idx)
            else:
                self._bar_reorder.attach(row, idx)
            group.add(row)
            if side == "left":
                self._left_rows.append(row)
            else:
                self._right_rows.append(row)

        self._rebuild_toolbox()
        self._rebuild_clock()

        if focus_idx >= 0:
            all_rows = self._left_rows + self._right_rows
            if focus_idx < len(all_rows):
                all_rows[focus_idx].grab_focus()

    def _move_bar(self, src: int, dst: int) -> bool:
        n = len(self._bar_order)
        if dst == src or not (0 <= src < n and 0 <= dst < n):
            return False
        item = self._bar_order.pop(src)
        self._bar_order.insert(dst, item)
        # Adopt the side of the neighbouring item, so dragging across the
        # left/right boundary moves the item to the other group.
        i = dst
        if i > 0:
            self._bar_side[item] = self._bar_side.get(self._bar_order[i - 1], "left")
        else:
            self._bar_side[item] = self._bar_side.get(self._bar_order[i + 1], "left")
        self._notify_dirty()
        self._rebuild_bar(dst)
        return True

    def _on_remove_bar(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._bar_order):
            return
        item = self._bar_order[idx]
        side = self._bar_side.get(item, "left")
        side_count = sum(1 for it in self._bar_order if self._bar_side.get(it) == side)
        if side_count <= BAR_MIN_ITEMS:
            self._window.show_toast("Keep at least 1 item on each side", timeout=2)
            return
        del self._bar_order[idx]
        self._bar_side.pop(item, None)
        self._notify_dirty()
        self._rebuild_bar()

    def _on_add_bar(self, side: str) -> None:
        present = set(self._bar_order)
        if side == "left":
            available = [it for it in BAR_LEFT_ITEMS if it not in present]
        else:
            available = [it for it in BAR_RIGHT_ITEMS if it not in present]
        if not available:
            self._window.show_toast("All items for this side are already present", timeout=2)
            return

        catalog = BAR_LEFT_ITEMS if side == "left" else BAR_RIGHT_ITEMS
        labels = [catalog[it][0] for it in available]

        group = Adw.PreferencesGroup()
        combo = Adw.ComboRow(title="Bar item")
        combo.set_model(Gtk.StringList.new(labels))
        combo.set_selected(0)
        group.add(combo)

        dialog = Adw.AlertDialog(heading="Add Bar Item", extra_child=group)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("add", "Add")
        dialog.set_default_response("add")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "add":
                return
            idx = combo.get_selected()
            if 0 <= idx < len(labels):
                item = available[idx]
                self._bar_order.append(item)
                self._bar_side[item] = side
                self._notify_dirty()
                self._rebuild_bar()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    # ── Toolbox ──

    def _rebuild_toolbox(self, focus_idx: int = -1) -> None:
        if self._toolbox_group is None:
            return
        expander = self._toolbox_group
        for row in self._toolbox_rows:
            expander.remove(row)
        self._toolbox_rows = []

        for idx, tid in enumerate(self._tools_order):
            if tid == "separator":
                title, sub, icon_name = "Separator", "Visual divider", "view-fullscreen-symbolic"
                unavailable = False
            else:
                title, sub, icon_name, pkg = TOOLBOX_ITEMS.get(tid, (tid, "", "view-list-symbolic", None))
                unavailable = pkg is not None and not _which(pkg)
                if unavailable:
                    sub = f"Requires {pkg} (not installed)"

            row = Adw.ActionRow(title=_markup(title), subtitle=_markup(sub))
            row.set_subtitle_lines(2)

            icon = Gtk.Image.new_from_icon_name(icon_name)
            icon.set_pixel_size(24)
            icon.add_css_class("dim-label")
            row.add_prefix(icon)

            if unavailable:
                row.set_opacity(0.55)
                row.add_css_class("toolbox-unavailable")

            handle = Gtk.Image.new_from_icon_name("drag-handle-symbolic")
            handle.set_opacity(0.5)
            handle.set_valign(Gtk.Align.CENTER)
            row.add_suffix(handle)

            remove_btn = Gtk.Button(icon_name="user-trash-symbolic")
            remove_btn.set_valign(Gtk.Align.CENTER)
            remove_btn.add_css_class("flat")
            remove_btn.set_tooltip_text("Remove from toolbox")
            remove_btn.set_sensitive(len(self._tools_order) > TOOLBOX_MIN_ITEMS)
            remove_btn.connect("clicked", lambda _b, i=idx: self._on_remove_toolbox(i))
            row.add_suffix(remove_btn)

            self._toolbox_reorder.attach(row, idx)
            expander.add_row(row)
            self._toolbox_rows.append(row)

        if focus_idx >= 0 and focus_idx < len(self._toolbox_rows):
            self._toolbox_rows[focus_idx].grab_focus()

    def _move_toolbox(self, src: int, dst: int) -> bool:
        n = len(self._tools_order)
        if dst == src or not (0 <= src < n and 0 <= dst < n):
            return False
        item = self._tools_order.pop(src)
        self._tools_order.insert(dst, item)
        self._notify_dirty()
        self._rebuild_toolbox(dst)
        return True

    def _on_add_toolbox(self, _btn=None) -> None:
        available = [tid for tid in list(TOOLBOX_ITEMS) + ["separator"] if tid not in self._tools_order]
        if not available:
            self._window.show_toast("All toolbox items are already present", timeout=2)
            return

        labels = []
        for tid in available:
            if tid == "separator":
                labels.append("Separator")
            else:
                labels.append(TOOLBOX_ITEMS[tid][0])

        group = Adw.PreferencesGroup()
        combo = Adw.ComboRow(title="Toolbox item")
        combo.set_model(Gtk.StringList.new(labels))
        combo.set_selected(0)
        group.add(combo)

        dialog = Adw.AlertDialog(heading="Add Toolbox Item", extra_child=group)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("add", "Add")
        dialog.set_default_response("add")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "add":
                return
            idx = combo.get_selected()
            if 0 <= idx < len(labels):
                tid = available[idx]
                self._tools_order.append(tid)
                self._notify_dirty()
                self._rebuild_toolbox()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    def _on_remove_toolbox(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._tools_order):
            return
        if len(self._tools_order) <= TOOLBOX_MIN_ITEMS:
            self._window.show_toast(f"Keep at least {TOOLBOX_MIN_ITEMS} items", timeout=2)
            return
        del self._tools_order[idx]
        self._notify_dirty()
        self._rebuild_toolbox()

    # ── Clock ──

    def _rebuild_clock(self, focus_idx: int = -1) -> None:
        if self._clock_group is None:
            return
        expander = self._clock_group
        for row in self._clock_rows:
            expander.remove(row)
        self._clock_rows = []

        for idx, cid in enumerate(self._clock_order):
            title, sub, icon_name = CLOCK_ITEMS.get(cid, (cid, "", "clock-symbolic"))

            row = Adw.ActionRow(title=_markup(title), subtitle=_markup(sub))
            row.set_subtitle_lines(2)

            icon = Gtk.Image.new_from_icon_name(icon_name)
            icon.set_pixel_size(24)
            icon.add_css_class("dim-label")
            row.add_prefix(icon)

            handle = Gtk.Image.new_from_icon_name("drag-handle-symbolic")
            handle.set_opacity(0.5)
            handle.set_valign(Gtk.Align.CENTER)
            row.add_suffix(handle)

            remove_btn = Gtk.Button(icon_name="user-trash-symbolic")
            remove_btn.set_valign(Gtk.Align.CENTER)
            remove_btn.add_css_class("flat")
            remove_btn.set_tooltip_text("Remove from clock popup")
            remove_btn.set_sensitive(len(self._clock_order) > CLOCK_MIN_ITEMS)
            remove_btn.connect("clicked", lambda _b, i=idx: self._on_remove_clock(i))
            row.add_suffix(remove_btn)

            self._clock_reorder.attach(row, idx)
            expander.add_row(row)
            self._clock_rows.append(row)

        if focus_idx >= 0 and focus_idx < len(self._clock_rows):
            self._clock_rows[focus_idx].grab_focus()

    def _move_clock(self, src: int, dst: int) -> bool:
        n = len(self._clock_order)
        if dst == src or not (0 <= src < n and 0 <= dst < n):
            return False
        item = self._clock_order.pop(src)
        self._clock_order.insert(dst, item)
        self._notify_dirty()
        self._rebuild_clock(dst)
        return True

    def _on_add_clock(self, _btn=None) -> None:
        available = [cid for cid in CLOCK_ITEMS if cid not in self._clock_order]
        if not available:
            self._window.show_toast("All clock sections are already present", timeout=2)
            return

        labels = [CLOCK_ITEMS[cid][0] for cid in available]

        group = Adw.PreferencesGroup()
        combo = Adw.ComboRow(title="Clock section")
        combo.set_model(Gtk.StringList.new(labels))
        combo.set_selected(0)
        group.add(combo)

        dialog = Adw.AlertDialog(heading="Add Clock Section", extra_child=group)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("add", "Add")
        dialog.set_default_response("add")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "add":
                return
            idx = combo.get_selected()
            if 0 <= idx < len(labels):
                cid = available[idx]
                self._clock_order.append(cid)
                self._notify_dirty()
                self._rebuild_clock()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    def _on_remove_clock(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._clock_order):
            return
        if len(self._clock_order) <= CLOCK_MIN_ITEMS:
            self._window.show_toast(f"Keep at least {CLOCK_MIN_ITEMS} section", timeout=2)
            return
        del self._clock_order[idx]
        self._notify_dirty()
        self._rebuild_clock()

    # ── Row builders ──

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, BAR_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=BAR_DEFAULTS[key],
            baseline=self._saved.get(key, BAR_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(row, "notify::active", key, mrow)
        return mrow

    def _add_combo(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        options: list[tuple[str, str]],
        *,
        subtitle: str = "",
    ) -> ManagedRow:
        ids = [opt[0] for opt in options]
        labels = [opt[1] for opt in options]
        current = self._data.get(key, BAR_DEFAULTS[key])
        try:
            selected = ids.index(current)
        except ValueError:
            selected = 0
        row = make_combo_row(label, model=Gtk.StringList.new(labels), selected=selected,
                             subtitle=subtitle)
        group.add(row)

        def get_value():
            idx = row.get_selected()
            return ids[idx] if 0 <= idx < len(ids) else ids[0]

        def set_silent(value):
            try:
                row.set_selected(ids.index(value))
            except ValueError:
                row.set_selected(0)

        mrow = ManagedRow(
            row,
            default=BAR_DEFAULTS[key],
            baseline=self._saved.get(key, BAR_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(row, "notify::selected", key, mrow)
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
            value=int(self._data.get(key, BAR_DEFAULTS[key])),
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
            default=BAR_DEFAULTS[key],
            baseline=self._saved.get(key, BAR_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(spin, "value-changed", key, mrow)
        return mrow

    def _add_entry(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        *,
        placeholder: str = "",
        subtitle: str = "",
    ) -> ManagedRow:
        row = Adw.ActionRow(title=label, subtitle=subtitle)
        entry = Gtk.Entry(text=str(self._data.get(key, BAR_DEFAULTS[key])))
        if placeholder:
            entry.set_placeholder_text(placeholder)
        entry.set_width_chars(20)
        entry.set_valign(Gtk.Align.CENTER)
        row.add_suffix(entry)
        row.set_activatable_widget(entry)
        group.add(row)

        def get_value():
            return entry.get_text()

        def set_silent(value):
            entry.set_text(str(value))

        mrow = ManagedRow(
            row,
            default=BAR_DEFAULTS[key],
            baseline=self._saved.get(key, BAR_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(entry, "changed", key, mrow)
        return mrow

    # ── Change plumbing ──

    def _wire_change(self, widget: Gtk.Widget, signal: str, key: str, mrow: ManagedRow) -> None:
        def _changed(*_args):
            # ManagedRow already handles baseline comparison; sync our dict
            # so the shell write reflects exactly what the user sees.
            self._data[key] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        widget.connect(signal, _changed)

    def _on_change(self, key: str, value) -> None:
        self._data[key] = value
        self._notify_dirty()

    def _bar_split(self) -> tuple[list[str], list[str]]:
        left = [it for it in self._bar_order if self._bar_side.get(it) == "left"]
        right = [it for it in self._bar_order if self._bar_side.get(it) != "left"]
        return left, right

    def _write_live(self) -> None:
        current = load_bar()
        current.update({key: self._data.get(key, BAR_DEFAULTS[key]) for key in self._rows})
        current["toolboxOrder"] = list(self._tools_order)
        current["clockOrder"] = list(self._clock_order)
        left, right = self._bar_split()
        current["barLeftOrder"] = left
        current["barRightOrder"] = right
        save_bar(current)

    def _notify_dirty(self) -> None:
        self._write_live()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    # ── Lifecycle ──

    def is_dirty(self) -> bool:
        return (any(self._data.get(key) != self._saved.get(key) for key in self._rows)
                or self._tools_order != self._saved_tools_order
                or self._clock_order != self._saved_clock_order
                or self._bar_order != self._saved_bar_order
                or self._bar_side != self._saved_bar_side)

    def mark_saved(self) -> None:
        current = load_bar()
        current.update({key: self._data.get(key, BAR_DEFAULTS[key]) for key in self._rows})
        current["toolboxOrder"] = list(self._tools_order)
        current["clockOrder"] = list(self._clock_order)
        left, right = self._bar_split()
        current["barLeftOrder"] = left
        current["barRightOrder"] = right
        save_bar(current)
        self._saved = dict(current)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._saved.get(key, BAR_DEFAULTS[key]))
        self._saved_tools_order = list(self._tools_order)
        self._saved_clock_order = list(self._clock_order)
        self._saved_bar_order = list(self._bar_order)
        self._saved_bar_side = dict(self._bar_side)

    def discard(self) -> None:
        self._data = dict(self._saved)
        for mrow in self._rows.values():
            mrow.discard()
        self._tools_order = list(self._saved_tools_order)
        self._rebuild_toolbox()
        self._clock_order = list(self._saved_clock_order)
        self._rebuild_clock()
        self._bar_order = list(self._saved_bar_order)
        self._bar_side = dict(self._saved_bar_side)
        self._rebuild_bar()
        self._write_live()

    def reload_from_disk(self) -> None:
        """Re-read bar.json (e.g. after applying a preset) and sync widgets."""
        self._data = load_bar()
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            value = self._data.get(key, BAR_DEFAULTS[key])
            mrow.apply_value(value)
            mrow.set_baseline(value)
        self._tools_order = list(self._data.get("toolboxOrder") or list(TOOLBOX_ITEMS))
        self._saved_tools_order = list(self._tools_order)
        self._rebuild_toolbox()
        self._clock_order = list(self._data.get("clockOrder") or list(CLOCK_DEFAULT_ORDER))
        self._saved_clock_order = list(self._clock_order)
        self._rebuild_clock()
        self._bar_order = list(
            self._data.get("barLeftOrder") or list(BAR_LEFT_DEFAULT_ORDER)
        ) + list(self._data.get("barRightOrder") or list(BAR_RIGHT_DEFAULT_ORDER))
        self._bar_side = {}
        for it in (self._data.get("barLeftOrder") or list(BAR_LEFT_DEFAULT_ORDER)):
            self._bar_side[it] = "left"
        for it in (self._data.get("barRightOrder") or list(BAR_RIGHT_DEFAULT_ORDER)):
            self._bar_side[it] = "right"
        self._saved_bar_order = list(self._bar_order)
        self._saved_bar_side = dict(self._bar_side)
        self._rebuild_bar()

    # ── Pending changes ──

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                label = {
                    "position": "Position",
                    "launcherIcon": "Launcher Icon",
                    "pillStyle": "Pill Style",
                    "batteryStyle": "Battery Style",
                }.get(key, "Bar setting")
                changed.append(label)
        if self._tools_order != self._saved_tools_order:
            changed.append("Toolbox")
        if self._clock_order != self._saved_clock_order:
            changed.append("Time, Weather & Calendar")
        if (self._bar_order != self._saved_bar_order
                or self._bar_side != self._saved_bar_side):
            changed.append("Left/Right bar")
        if changed:
            yield PendingChange(
                category="Shell Bar",
                title="Bar",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_bar",
                icon=BAR_ICON,
                kind="modified",
                revert=self.discard,
            )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_bar:bar", "label": "Bar",
             "description": "Position, launcher icon, clock format",
             "_group_id": "shell_bar", "_group_label": "Bar", "_section_label": "Bar"},
            {"key": "shell_bar:left", "label": "Left Bar",
             "description": "Reorder items on the left side of the bar",
             "_group_id": "shell_bar", "_group_label": "Bar", "_section_label": "Left Bar"},
            {"key": "shell_bar:right", "label": "Right Bar",
             "description": "Reorder items on the right side of the bar",
             "_group_id": "shell_bar", "_group_label": "Bar", "_section_label": "Right Bar"},
            {"key": "shell_bar:autohide", "label": "Bar Auto-hide",
             "description": "Pin, hover-to-reveal, fullscreen behaviour",
             "_group_id": "shell_bar", "_group_label": "Bar", "_section_label": "Auto-hide"},
            {"key": "shell_bar:toolbox", "label": "Toolbox",
             "description": "Order and availability of the shell toolbox tools",
             "_group_id": "shell_bar", "_group_label": "Bar", "_section_label": "Toolbox"},
        ]


__all__ = ["ShellBarPage"]
