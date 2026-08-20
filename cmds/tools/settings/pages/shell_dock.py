"""Shell Dock page — configure the shell dock (``dock.json``).

Mirrors the Dock section of the in-shell ``ShellPanel.qml``. Values are
written to ``~/.config/retro/shell/dock.json``; the shell's ``FileView``
watches that file with ``watchChanges`` and reloads on external writes, so
changes apply live without a shell restart.

Rows that are not relevant when the theme is ``integrated`` are hidden
automatically, matching the QML ``visible`` bindings.
"""

from collections.abc import Iterable, Sequence
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import DOCK_DEFAULTS, load_dock, save_dock
from settings.ui import clear_children, make_page_layout
from settings.ui.icons import DOCK_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_INTEGRATED_HIDDEN = (
    "height", "spacing", "margin",
    "hoverToReveal", "hoverRegionHeight", "pinnedOnStartup",
    "showPinButton", "availableOnFullscreen", "keepHidden",
    "showRunningIndicators", "showOverviewButton",
)

_POSITION_OPTIONS = [
    ("top", "Top"),
    ("bottom", "Bottom"),
    ("left", "Left"),
    ("right", "Right"),
]

_THEME_OPTIONS = [
    ("default", "Default"),
    ("floating", "Floating"),
    ("integrated", "Integrated"),
]

_SCALE_OPTIONS = [
    (0.7, "70%"),
    (0.8, "80%"),
    (0.9, "90%"),
    (1.0, "100%"),
    (1.1, "110%"),
    (1.2, "120%"),
    (1.3, "130%"),
]


class ShellDockPage:
    """Shell dock configuration — writes ``dock.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_dock()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        group = Adw.PreferencesGroup(
            title="Dock",
            description="Enable, position, and style the shell dock.",
        )
        self._add_switch(group, "enabled", "Enabled",
                         subtitle="Show the dock on screen")
        self._add_combo(group, "position", "Position", _POSITION_OPTIONS,
                        subtitle="Which screen edge the dock attaches to")
        self._add_combo(group, "theme", "Theme", _THEME_OPTIONS,
                        subtitle="Default, floating or integrated style")
        self._add_spin(group, "height", "Height", lower=32, upper=128, suffix="px",
                       subtitle="Total height of the dock")
        self._add_spin(group, "iconSize", "Icon Size", lower=24, upper=96, suffix="px",
                       subtitle="Size of application icons in the dock")
        self._add_combo(group, "scale", "Scale", _SCALE_OPTIONS,
                        subtitle="Scales icons, spacing and dock size in place")
        self._add_spin(group, "spacing", "Spacing", lower=0, upper=32, suffix="px",
                       subtitle="Gap between dock items")
        self._add_spin(group, "margin", "Margin", lower=0, upper=32, suffix="px",
                       subtitle="Space between the dock and the screen edge")
        self._add_switch(group, "hoverToReveal", "Hover to Reveal",
                         subtitle="Show the dock when the mouse reaches the edge")
        self._add_spin(group, "hoverRegionHeight", "Hover Region", lower=0, upper=32, suffix="px",
                       subtitle="Height of the edge region that reveals the dock")
        self._add_switch(group, "pinnedOnStartup", "Pinned on Startup",
                         subtitle="Keep the dock visible when the session starts")
        self._add_switch(group, "showPinButton", "Show Pin Button",
                         subtitle="Show a button to pin the dock")
        self._add_switch(group, "availableOnFullscreen", "Available on Fullscreen",
                         subtitle="Keep the dock visible over fullscreen apps")
        self._add_switch(group, "keepHidden", "Keep Hidden",
                         subtitle="Always keep the dock hidden")
        self._add_switch(group, "showRunningIndicators", "Show Running Indicators",
                         subtitle="Show dots under running applications")
        self._add_switch(group, "showOverviewButton", "Show Overview Button",
                         subtitle="Show a button to open the workspace overview")
        content_box.append(group)

        self._refresh_integrated_visibility()
        return toolbar

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, DOCK_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=DOCK_DEFAULTS[key],
            baseline=self._saved.get(key, DOCK_DEFAULTS[key]),
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
        options: Sequence[tuple[object, str]],
        *,
        subtitle: str = "",
    ) -> ManagedRow:
        ids = [opt[0] for opt in options]
        labels = [opt[1] for opt in options]
        current = self._data.get(key, DOCK_DEFAULTS[key])
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
            default=DOCK_DEFAULTS[key],
            baseline=self._saved.get(key, DOCK_DEFAULTS[key]),
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
            value=int(self._data.get(key, DOCK_DEFAULTS[key])),
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
            default=DOCK_DEFAULTS[key],
            baseline=self._saved.get(key, DOCK_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(spin, "value-changed", key, mrow)
        return mrow

    def _wire_change(self, widget: Gtk.Widget, signal: str, key: str, mrow: ManagedRow) -> None:
        def _changed(*_args):
            self._data[key] = mrow.value
            mrow.refresh()
            if key == "theme":
                self._refresh_integrated_visibility()
            self._notify_dirty()

        widget.connect(signal, _changed)

    def _on_change(self, key: str, value) -> None:
        self._data[key] = value
        if key == "theme":
            self._refresh_integrated_visibility()
        self._notify_dirty()

    def _refresh_integrated_visibility(self) -> None:
        is_integrated = self._data.get("theme", DOCK_DEFAULTS["theme"]) == "integrated"
        for key in _INTEGRATED_HIDDEN:
            row = self._rows.get(key)
            if row is not None:
                row.row.set_visible(not is_integrated)

    def _write_live(self) -> None:
        save_dock(self._data)

    def _notify_dirty(self) -> None:
        self._write_live()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        save_dock(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, DOCK_DEFAULTS[key]))

    def discard(self) -> None:
        self._data = dict(self._saved)
        for mrow in self._rows.values():
            mrow.discard()
        self._refresh_integrated_visibility()
        self._write_live()

    def reload_from_disk(self) -> None:
        """Re-read dock.json (e.g. after applying a preset) and sync widgets."""
        self._data = load_dock()
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            value = self._data.get(key, DOCK_DEFAULTS[key])
            mrow.apply_value(value)
            mrow.set_baseline(value)
        self._refresh_integrated_visibility()

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                label = {
                    "enabled": "Enabled",
                    "position": "Position",
                    "theme": "Theme",
                    "height": "Height",
                    "iconSize": "Icon Size",
                    "scale": "Scale",
                    "spacing": "Spacing",
                    "margin": "Margin",
                }.get(key, "Dock setting")
                changed.append(label)
        if changed:
            yield PendingChange(
                category="Shell Dock",
                title="Dock",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_dock",
                icon=DOCK_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_dock:dock", "label": "Dock",
             "description": "Enable, position, style and behaviour of the shell dock",
             "_group_id": "shell_dock", "_group_label": "Dock", "_section_label": "Dock"},
        ]


__all__ = ["ShellDockPage"]
