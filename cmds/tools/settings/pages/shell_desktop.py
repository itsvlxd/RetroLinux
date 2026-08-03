"""Shell Desktop page — configure desktop icon grid (``desktop.json``).

Mirrors the Desktop section of the in-shell ``ShellPanel.qml``. Values are
written to ``~/.config/retro/shell/desktop.json``; the shell's ``FileView``
watches that file with ``watchChanges`` and reloads on external writes, so
changes apply live without a shell restart.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import DESKTOP_DEFAULTS, load_desktop, save_desktop
from settings.ui import clear_children, make_page_layout
from settings.ui.color_combo import COLOR_NAMES, color_map, _draw_swatch_hex
from settings.ui.icons import DESKTOP_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow


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

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        group = Adw.PreferencesGroup(
            title="Desktop",
            description="Desktop icon grid appearance and behaviour.",
        )
        self._add_switch(group, "enabled", "Enabled",
                         subtitle="Show desktop icons on the wallpaper")
        self._add_spin(group, "iconSize", "Icon Size", lower=24, upper=96, suffix="px",
                       subtitle="Size of desktop icons")
        self._add_spin(group, "spacingVertical", "Vertical Spacing", lower=0, upper=48, suffix="px",
                       subtitle="Vertical gap between desktop icon rows")
        self._add_color_combo(group, "textColor", "Text Color",
                              subtitle="Theme color for desktop icon labels")
        content_box.append(group)

        return toolbar

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, DESKTOP_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=DESKTOP_DEFAULTS[key],
            baseline=self._saved.get(key, DESKTOP_DEFAULTS[key]),
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
            value=int(self._data.get(key, DESKTOP_DEFAULTS[key])),
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
            default=DESKTOP_DEFAULTS[key],
            baseline=self._saved.get(key, DESKTOP_DEFAULTS[key]),
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
        current = str(self._data.get(key, DESKTOP_DEFAULTS[key]))
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
            default=DESKTOP_DEFAULTS[key],
            baseline=self._saved.get(key, DESKTOP_DEFAULTS[key]),
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

    def _notify_dirty(self) -> None:
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        save_desktop(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, DESKTOP_DEFAULTS[key]))

    def discard(self) -> None:
        self._data = dict(self._saved)
        for mrow in self._rows.values():
            mrow.discard()

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                label = {
                    "enabled": "Enabled",
                    "iconSize": "Icon Size",
                    "spacingVertical": "Spacing",
                    "textColor": "Text Color",
                }.get(key, "Desktop setting")
                changed.append(label)
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
        ]


__all__ = ["ShellDesktopPage"]
