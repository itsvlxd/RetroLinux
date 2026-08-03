"""Shell Frame page — configure the Retro Shell screen frame (``bar.json``).

Mirrors the Frame section of the in-shell ``ShellPanel.qml``. Values are
written to ``~/.config/retro/shell/bar.json``; the shell's ``FileView``
watches that file with ``watchChanges`` and reloads on external writes, so
changes apply live without a shell restart.

Writes are gated by the settings window's save/discard lifecycle: edits
are staged in memory (``_data`` vs the ``_saved`` snapshot) and only
persisted on Save, exactly like the other standalone pages.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import BAR_DEFAULTS, load_bar, save_bar
from settings.ui import make_page_layout
from settings.ui.icons import FRAME_ICON
from settings.ui.managed_row import ManagedRow, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow


class ShellFramePage:
    """Shell screen frame configuration — writes ``bar.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_bar()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}
        self._frame_rows: list[tuple[str, ManagedRow]] = []

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        frame_group = Adw.PreferencesGroup(
            title="Frame",
            description="Frame around the screens and whether it contains the bar.",
        )
        self._build_frame_group(frame_group)
        content_box.append(frame_group)

        return toolbar

    # ── Groups ──

    def _build_frame_group(self, group: Adw.PreferencesGroup) -> None:
        self._add_switch(group, "frameEnabled", "Enabled",
                         subtitle="Draw a frame around the bar")
        self._add_spin(group, "frameThickness", "Thickness",
                       lower=0, upper=40, suffix="px",
                       subtitle="Frame thickness in pixels")
        self._add_switch(group, "containBar", "Contain Bar",
                         subtitle="Clip the bar to its frame bounds")
        for key, label, sub in (
            ("keepBarShadow", "Keep Bar Shadow", "Keep the bar's shadow when contained"),
            ("keepBarBorder", "Keep Bar Border", "Keep the bar's border when contained"),
        ):
            mrow = self._add_switch(group, key, label, subtitle=sub)
            self._frame_rows.append((key, mrow))
        self._refresh_frame_visibility()

    def _refresh_frame_visibility(self) -> None:
        """Keep Bar Shadow / Border only apply when the bar is contained."""
        contained = bool(self._data.get("containBar", False))
        for _key, mrow in self._frame_rows:
            mrow.row.set_visible(contained)

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
        if key == "containBar":
            self._refresh_frame_visibility()
        self._notify_dirty()

    def _notify_dirty(self) -> None:
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    # ── Lifecycle ──

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        save_bar(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, BAR_DEFAULTS[key]))

    def discard(self) -> None:
        self._data = dict(self._saved)
        self._refresh_frame_visibility()
        for mrow in self._rows.values():
            mrow.discard()

    # ── Pending changes ──

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                label = {
                    "frameEnabled": "Enabled",
                    "frameThickness": "Thickness",
                    "containBar": "Contain Bar",
                    "keepBarShadow": "Keep Bar Shadow",
                    "keepBarBorder": "Keep Bar Border",
                }.get(key, "Frame setting")
                changed.append(label)
        if changed:
            yield PendingChange(
                category="Shell Frame",
                title="Frame",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_frame",
                icon=FRAME_ICON,
                kind="modified",
                revert=self.discard,
            )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_frame:frame", "label": "Frame",
             "description": "Frame enabled, thickness, contain-bar chrome",
             "_group_id": "shell_frame", "_group_label": "Frame", "_section_label": "Frame"},
        ]


__all__ = ["ShellFramePage"]