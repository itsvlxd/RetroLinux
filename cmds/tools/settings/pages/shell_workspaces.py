"""Shell Workspaces page — configure workspace indicators (``workspaces.json``).

Mirrors the Workspaces section of the in-shell ``ShellPanel.qml``. Values
are written to ``~/.config/retro/shell/workspaces.json``; the shell's
``FileView`` watches that file with ``watchChanges`` and reloads on external
writes, so changes apply live without a shell restart.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import WORKSPACES_DEFAULTS, load_workspaces, save_workspaces
from settings.ui import clear_children, make_page_layout
from settings.ui.icons import WORKSPACES_ICON
from settings.ui.managed_row import ManagedRow, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_SWITCH_KEYS = (
    ("showAppIcons", "Show App Icons"),
    ("alwaysShowNumbers", "Always Show Numbers"),
    ("showNumbers", "Show Numbers"),
    ("dynamic", "Dynamic"),
)


class ShellWorkspacesPage:
    """Shell workspace indicator configuration — writes ``workspaces.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_workspaces()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        group = Adw.PreferencesGroup(
            title="Workspaces",
            description="Appearance and behaviour of workspace indicators in the shell.",
        )
        self._add_spin(group, "shown", "Shown",
                       lower=1, upper=20, suffix="",
                       subtitle="Number of workspace indicators to display")
        for key, label in _SWITCH_KEYS:
            sub = {
                "showAppIcons": "Show running application icons on workspace indicators",
                "alwaysShowNumbers": "Always display workspace numbers, even on single workspace",
                "showNumbers": "Show workspace numbers alongside the indicators",
                "dynamic": "Automatically adjust the number of workspace indicators based on actual workspaces",
            }.get(key, "")
            self._add_switch(group, key, label, subtitle=sub)
        content_box.append(group)

        return toolbar

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, WORKSPACES_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=WORKSPACES_DEFAULTS[key],
            baseline=self._saved.get(key, WORKSPACES_DEFAULTS[key]),
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
            value=int(self._data.get(key, WORKSPACES_DEFAULTS[key])),
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
            default=WORKSPACES_DEFAULTS[key],
            baseline=self._saved.get(key, WORKSPACES_DEFAULTS[key]),
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
            self._notify_dirty()

        widget.connect(signal, _changed)

    def _on_change(self, key: str, value) -> None:
        self._data[key] = value
        self._notify_dirty()

    def _write_live(self) -> None:
        save_workspaces(self._data)

    def _notify_dirty(self) -> None:
        self._write_live()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        save_workspaces(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, WORKSPACES_DEFAULTS[key]))

    def discard(self) -> None:
        self._data = dict(self._saved)
        for mrow in self._rows.values():
            mrow.discard()
        self._write_live()

    def reload_from_disk(self) -> None:
        """Re-read workspaces.json (e.g. after applying a preset) and sync widgets."""
        self._data = load_workspaces()
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            value = self._data.get(key, WORKSPACES_DEFAULTS[key])
            mrow.apply_value(value)
            mrow.set_baseline(value)

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                label = {
                    "shown": "Shown",
                }.get(key, "Workspaces setting")
                changed.append(label)
        if changed:
            yield PendingChange(
                category="Shell Workspaces",
                title="Workspaces",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_workspaces",
                icon=WORKSPACES_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_workspaces:workspaces", "label": "Shell Workspaces",
             "description": "Number, appearance and behaviour of workspace indicators",
             "_group_id": "shell_workspaces", "_group_label": "Workspaces (Shell)", "_section_label": "Workspaces"},
        ]


__all__ = ["ShellWorkspacesPage"]
