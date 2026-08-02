"""Shell Sidebar page — configure the Retro Shell assistant sidebar (``ai.json``).

Mirrors the Sidebar section of the in-shell ``ShellPanel.qml``. Values are
written to ``~/.config/retro/shell/ai.json``; the shell's ``FileView``
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
from settings.core.shell_config import AI_DEFAULTS, load_ai, save_ai
from settings.ui import make_page_layout
from settings.ui.icons import SIDEBAR_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_POSITION_OPTIONS = [
    ("left", "Left"),
    ("right", "Right"),
]


class ShellSidebarPage:
    """Shell assistant sidebar configuration — writes ``ai.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_ai()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        sidebar_group = Adw.PreferencesGroup(
            title="Sidebar",
            description="Position, size, and startup behaviour of the assistant sidebar.",
        )
        self._build_sidebar_group(sidebar_group)
        content_box.append(sidebar_group)

        return toolbar

    # ── Groups ──

    def _build_sidebar_group(self, group: Adw.PreferencesGroup) -> None:
        self._add_combo(group, "sidebarPosition", "Position", _POSITION_OPTIONS,
                        subtitle="Which screen edge the sidebar is attached to")
        self._add_spin(group, "sidebarWidth", "Width",
                       lower=300, upper=800, suffix="px",
                       subtitle="Width of the sidebar in pixels")
        self._add_switch(group, "sidebarPinnedOnStartup", "Pinned on Startup",
                         subtitle="Keep the sidebar open when the session starts")

    # ── Row builders ──

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, AI_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=AI_DEFAULTS[key],
            baseline=self._saved.get(key, AI_DEFAULTS[key]),
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
        current = self._data.get(key, AI_DEFAULTS[key])
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
            default=AI_DEFAULTS[key],
            baseline=self._saved.get(key, AI_DEFAULTS[key]),
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
            value=int(self._data.get(key, AI_DEFAULTS[key])),
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
            default=AI_DEFAULTS[key],
            baseline=self._saved.get(key, AI_DEFAULTS[key]),
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
        save_ai(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, AI_DEFAULTS[key]))

    def discard(self) -> None:
        self._data = dict(self._saved)
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
                    "sidebarPosition": "Position",
                    "sidebarWidth": "Width",
                    "sidebarPinnedOnStartup": "Pinned on Startup",
                }.get(key, "Sidebar setting")
                changed.append(label)
        if changed:
            yield PendingChange(
                category="Shell Sidebar",
                title="Sidebar",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_sidebar",
                icon=SIDEBAR_ICON,
                kind="modified",
                revert=self.discard,
            )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_sidebar:sidebar", "label": "Sidebar",
             "description": "Position, width, and startup pinning of the assistant sidebar",
             "_group_id": "shell_sidebar", "_group_label": "Sidebar", "_section_label": "Sidebar"},
        ]


__all__ = ["ShellSidebarPage"]
