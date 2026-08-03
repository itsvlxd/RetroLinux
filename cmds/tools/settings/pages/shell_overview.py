"""Shell Overview page — configure workspace overview (``overview.json``).

Mirrors the Overview section of the in-shell ``ShellPanel.qml``. Values are
written to ``~/.config/retro/shell/overview.json``; the shell's ``FileView``
watches that file with ``watchChanges`` and reloads on external writes, so
changes apply live without a shell restart.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import OVERVIEW_DEFAULTS, load_overview, save_overview
from settings.ui import clear_children, make_page_layout
from settings.ui.icons import OVERVIEW_ICON
from settings.ui.managed_row import ManagedRow, make_spin_float_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow


class ShellOverviewPage:
    """Shell overview configuration — writes ``overview.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_overview()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        group = Adw.PreferencesGroup(
            title="Overview",
            description="Grid layout and scaling of the workspace overview.",
        )
        self._add_spin(group, "rows", "Rows",
                       lower=1, upper=5, suffix="",
                       subtitle="Number of workspace rows in the overview grid")
        self._add_spin(group, "columns", "Columns",
                       lower=1, upper=10, suffix="",
                       subtitle="Number of workspace columns in the overview grid")
        self._add_float_spin(group, "scale", "Scale",
                             lower=0.0, upper=0.20, step=0.01, digits=2,
                             subtitle="Size of workspace thumbnails in the overview")
        self._add_spin(group, "workspaceSpacing", "Workspace Spacing",
                       lower=0, upper=20, suffix="px",
                       subtitle="Gap between workspace thumbnails")
        content_box.append(group)

        return toolbar

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
            value=int(self._data.get(key, OVERVIEW_DEFAULTS[key])),
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
            default=OVERVIEW_DEFAULTS[key],
            baseline=self._saved.get(key, OVERVIEW_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(spin, "value-changed", key, mrow)
        return mrow

    def _add_float_spin(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        *,
        lower: float,
        upper: float,
        step: float,
        digits: int,
        subtitle: str = "",
    ) -> ManagedRow:
        row, spin = make_spin_float_row(
            label,
            value=float(self._data.get(key, OVERVIEW_DEFAULTS[key])),
            lower=lower,
            upper=upper,
            step=step,
            digits=digits,
            subtitle=subtitle,
        )
        group.add(row)

        def get_value():
            return round(spin.get_value(), digits)

        def set_silent(value):
            spin.set_value(float(value))

        mrow = ManagedRow(
            row,
            default=OVERVIEW_DEFAULTS[key],
            baseline=self._saved.get(key, OVERVIEW_DEFAULTS[key]),
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

    def _notify_dirty(self) -> None:
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        save_overview(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, OVERVIEW_DEFAULTS[key]))

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
                    "rows": "Rows",
                    "columns": "Columns",
                    "scale": "Scale",
                    "workspaceSpacing": "Spacing",
                }.get(key, "Overview setting")
                changed.append(label)
        if changed:
            yield PendingChange(
                category="Shell Overview",
                title="Overview",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_overview",
                icon=OVERVIEW_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_overview:overview", "label": "Overview",
             "description": "Rows, columns, scale and spacing of the workspace overview grid",
             "_group_id": "shell_overview", "_group_label": "Overview", "_section_label": "Overview"},
        ]


__all__ = ["ShellOverviewPage"]
