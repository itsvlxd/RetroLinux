"""Shell Lock page — configure the lockscreen (``lockscreen.json``).

Values are written to ``~/.config/retro/shell/lockscreen.json``; the shell's
``FileView`` watches that file with ``watchChanges`` and reloads on external
writes, so changes apply live without a shell restart.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import LOCK_DEFAULTS, load_lockscreen, save_lockscreen
from settings.ui import make_page_layout
from settings.ui.color_combo import COLOR_NAMES, _draw_swatch_hex, color_map
from settings.ui.icons import LOCK_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_ALL_POSITIONS = [
    ("top-left", "Top Left"),
    ("top", "Top Center"),
    ("top-right", "Top Right"),
    ("left", "Left Center"),
    ("right", "Right Center"),
    ("bottom-left", "Bottom Left"),
    ("bottom", "Bottom Center"),
    ("bottom-right", "Bottom Right"),
    ("hidden", "Hidden"),
]

_CLOCK_STYLES = [
    ("split", "Split (HH MM offset)"),
    ("inline", "Inline (HH:MM)"),
    ("stacked", "Stacked (HH / MM)"),
    ("minimal", "Minimal (HH:MM + date)"),
]


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


class ShellLockPage:
    """Shell lockscreen configuration — writes ``lockscreen.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None
        self._data = load_lockscreen()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)

        clock_group = Adw.PreferencesGroup(
            title="Clock",
            description="Font size and colors for the lockscreen clock.",
        )
        self._add_spin(clock_group, "clockFontSize", "Font Size", lower=80, upper=400, suffix="px",
                       subtitle="Size of the clock digits in pixels")
        self._add_combo(clock_group, "clockStyle", "Style", _CLOCK_STYLES,
                        subtitle="Layout style for the clock display")
        self._add_combo(clock_group, "clockPosition", "Position", _ALL_POSITIONS,
                        subtitle="Where to place the clock on the lock screen")
        self._add_color_combo(clock_group, "clockColor", "Hours Color",
                              subtitle="Color used for the hours digits")
        self._add_color_combo(clock_group, "clockMinutesColor", "Minutes Color",
                              subtitle="Color used for the minutes digits")
        self._add_spin(clock_group, "clockDateFontSize", "Date Font Size", lower=8, upper=48, suffix="px",
                       subtitle="Size of the date text in minimal style")
        self._add_color_combo(clock_group, "clockDateColor", "Date Color",
                              subtitle="Color used for the date text in minimal style")
        content_box.append(clock_group)

        password_group = Adw.PreferencesGroup(
            title="Password Panel",
            description="Where to place the login form on the lock screen.",
        )
        self._add_combo(password_group, "passwordPosition", "Position", _ALL_POSITIONS,
                        subtitle="Position of the login form")
        content_box.append(password_group)

        widgets_group = Adw.PreferencesGroup(
            title="Widgets",
            description="Choose where each widget appears. Set to Hidden to disable.",
        )
        self._add_combo(widgets_group, "musicPosition", "Music Player", _ALL_POSITIONS,
                        subtitle="Corner for the currently playing track")
        self._add_combo(widgets_group, "weatherPosition", "Weather", _ALL_POSITIONS,
                        subtitle="Corner for the weather and forecast")
        self._add_combo(widgets_group, "powerPosition", "Power Menu", _ALL_POSITIONS,
                        subtitle="Corner for the power buttons")
        content_box.append(widgets_group)

        return toolbar

    def _add_combo(self, group: Adw.PreferencesGroup, key: str, label: str,
                   options: list[tuple[str, str]], *, subtitle: str = "") -> ManagedRow:
        ids = [o[0] for o in options]
        labels = [o[1] for o in options]
        current = self._data.get(key, LOCK_DEFAULTS[key])
        try:
            selected = ids.index(current)
        except ValueError:
            selected = 0
        row = make_combo_row(label, model=Gtk.StringList.new(labels), selected=selected, subtitle=subtitle)
        group.add(row)

        def get_value():
            return ids[row.get_selected()] if 0 <= row.get_selected() < len(ids) else ids[0]
        def set_silent(value):
            try: row.set_selected(ids.index(value))
            except ValueError: row.set_selected(0)

        mrow = ManagedRow(row, default=LOCK_DEFAULTS[key],
                          baseline=self._saved.get(key, LOCK_DEFAULTS[key]),
                          get_value=get_value, set_value_silent=set_silent,
                          on_value_set=lambda v, k=key: self._on_change(k, v))
        self._rows[key] = mrow
        row.connect("notify::selected", lambda *a, k=key, m=mrow: (setattr(self, '_data', {**self._data, k: m.value}), m.refresh(), self._notify_dirty()))
        return mrow

    def _add_spin(self, group: Adw.PreferencesGroup, key: str, label: str,
                  *, lower: int, upper: int, suffix: str, subtitle: str = "") -> ManagedRow:
        row, spin = make_spin_int_row(label, value=int(self._data.get(key, LOCK_DEFAULTS[key])),
                                      lower=lower, upper=upper, step=10, page_step=50, subtitle=subtitle)
        group.add(row)
        if suffix:
            l = Gtk.Label(label=suffix); l.add_css_class("dim-label"); l.set_valign(Gtk.Align.CENTER); row.add_suffix(l)

        def get_value(): return int(spin.get_value())
        def set_silent(value): spin.set_value(int(value))

        mrow = ManagedRow(row, default=LOCK_DEFAULTS[key],
                          baseline=self._saved.get(key, LOCK_DEFAULTS[key]),
                          get_value=get_value, set_value_silent=set_silent,
                          on_value_set=lambda v, k=key: self._on_change(k, v))
        self._rows[key] = mrow
        spin.connect("value-changed", lambda *a, k=key, m=mrow: (setattr(self, '_data', {**self._data, k: m.value}), m.refresh(), self._notify_dirty()))
        return mrow

    def _add_color_combo(self, group: Adw.PreferencesGroup, key: str, label: str,
                         *, subtitle: str = "") -> ManagedRow:
        current = str(self._data.get(key, LOCK_DEFAULTS[key]))
        row, ids = _make_named_color_combo_row(label, current, subtitle=subtitle)
        group.add(row)

        def get_value(): return ids[row.get_selected()] if 0 <= row.get_selected() < len(ids) else ids[0]
        def set_silent(value):
            try: row.set_selected(ids.index(str(value)))
            except ValueError: row.set_selected(0)

        mrow = ManagedRow(row, default=LOCK_DEFAULTS[key],
                          baseline=self._saved.get(key, LOCK_DEFAULTS[key]),
                          get_value=get_value, set_value_silent=set_silent,
                          on_value_set=lambda v, k=key: self._on_change(k, v))
        self._rows[key] = mrow
        row.connect("notify::selected", lambda *a, k=key, m=mrow: (setattr(self, '_data', {**self._data, k: m.value}), m.refresh(), self._notify_dirty()))
        return mrow

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
        save_lockscreen(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, LOCK_DEFAULTS[key]))

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
                changed.append({"clockFontSize": "Clock Size", "clockColor": "Clock Color",
                                "clockMinutesColor": "Minutes Color", "clockDateFontSize": "Date Size",
                                "clockDateColor": "Date Color", "clockStyle": "Clock Style",
                                "clockPosition": "Clock Position", "passwordPosition": "Password",
                                "musicPosition": "Music", "weatherPosition": "Weather",
                                "powerPosition": "Power"}.get(key, key))
        yield PendingChange(category="Shell Lock", title="Lockscreen",
                            subtitle=", ".join(changed[:3]), navigate_to="shell_lock",
                            icon=LOCK_ICON, kind="modified", revert=self.discard)

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_lock:lock", "label": "Lockscreen",
             "description": "Lockscreen: clock size and colors, password, music, weather and power positions",
             "_group_id": "shell_lock", "_group_label": "Lockscreen", "_section_label": "Lockscreen"},
        ]


__all__ = ["ShellLockPage"]
