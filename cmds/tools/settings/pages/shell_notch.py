"""Shell Notch page — configure the Retro Shell notch (``notch.json``).

Mirrors the Notch section of the in-shell ``ShellPanel.qml``. Values are
written to ``~/.config/retro/shell/notch.json``; the shell's ``FileView``
watches that file with ``watchChanges`` and reloads on external writes, so
changes apply live without a shell restart.
"""

import os
import subprocess
import threading
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import NOTCH_DEFAULTS, load_notch, save_notch
from settings.ui import clear_children, make_page_layout
from settings.ui.icons import NOTCH_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_POSITION_OPTIONS = [
    ("top", "Top"),
    ("bottom", "Bottom"),
]

_THEME_OPTIONS = [
    ("default", "Default"),
    ("island", "Island"),
]

_NO_MEDIA_DISPLAY_OPTIONS = [
    ("userHost", "User@Host"),
    ("compositor", "Compositor"),
    ("custom", "Custom"),
]


class ShellNotchPage:
    """Shell notch configuration — writes ``notch.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_notch()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        notch_group = Adw.PreferencesGroup(
            title="Notch",
            description="Position, style, and hover behaviour of the top notch.",
        )
        self._build_notch_group(notch_group)
        content_box.append(notch_group)

        display_group = Adw.PreferencesGroup(
            title="No Media Display",
            description="What to show in the notch when no media is playing.",
        )
        self._build_display_group(display_group)
        content_box.append(display_group)

        quickshare_group = Adw.PreferencesGroup(
            title="Quick Share",
            description="Show the Quick Share button in the dashboard and run the receiver.",
        )
        self._build_quickshare_group(quickshare_group)
        content_box.append(quickshare_group)

        self._refresh_custom_text_visible()
        return toolbar

    def _build_notch_group(self, group: Adw.PreferencesGroup) -> None:
        self._add_combo(group, "position", "Position", _POSITION_OPTIONS,
                        subtitle="Which screen edge the notch attaches to")
        self._add_combo(group, "theme", "Theme", _THEME_OPTIONS,
                        subtitle="Default pill or island notch style")
        self._add_spin(group, "hoverRegionHeight", "Hover Region Height",
                       lower=0, upper=32, suffix="px",
                       subtitle="Height of the edge region that reveals the notch")
        self._add_switch(group, "keepHidden", "Keep Hidden",
                         subtitle="Always keep the notch hidden")
        self._add_switch(group, "disableHoverExpansion", "Disable Hover Expansion",
                         subtitle="Prevent the notch from expanding on hover")

    def _build_display_group(self, group: Adw.PreferencesGroup) -> None:
        mrow = self._add_combo(group, "noMediaDisplay", "No Media Display",
                               _NO_MEDIA_DISPLAY_OPTIONS,
                               subtitle="What to show when no media is playing")
        self._no_media_mrow = mrow

        self._add_entry(group, "customText", "Custom Text",
                        placeholder="Enter text…",
                        subtitle="Text to display when custom is selected")

    def _build_quickshare_group(self, group: Adw.PreferencesGroup) -> None:
        self._add_switch(group, "quickshareEnabled", "Quick Share",
                         subtitle="Show in dashboard and receive files when on")

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, NOTCH_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=NOTCH_DEFAULTS[key],
            baseline=self._saved.get(key, NOTCH_DEFAULTS[key]),
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
        current = self._data.get(key, NOTCH_DEFAULTS[key])
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
            default=NOTCH_DEFAULTS[key],
            baseline=self._saved.get(key, NOTCH_DEFAULTS[key]),
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
            value=int(self._data.get(key, NOTCH_DEFAULTS[key])),
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
            default=NOTCH_DEFAULTS[key],
            baseline=self._saved.get(key, NOTCH_DEFAULTS[key]),
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
        entry = Gtk.Entry(text=str(self._data.get(key, NOTCH_DEFAULTS[key])))
        if placeholder:
            entry.set_placeholder_text(placeholder)
        row.set_child(entry)
        row.set_activatable_widget(entry)
        group.add(row)

        def get_value():
            return entry.get_text()

        def set_silent(value):
            entry.set_text(str(value))

        mrow = ManagedRow(
            row,
            default=NOTCH_DEFAULTS[key],
            baseline=self._saved.get(key, NOTCH_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(entry, "changed", key, mrow)
        return mrow

    def _wire_change(self, widget: Gtk.Widget, signal: str, key: str, mrow: ManagedRow) -> None:
        def _changed(*_args):
            self._data[key] = mrow.value
            mrow.refresh()
            if key == "noMediaDisplay":
                self._refresh_custom_text_visible()
            self._notify_dirty()

        widget.connect(signal, _changed)

    def _on_change(self, key: str, value) -> None:
        self._data[key] = value
        if key == "noMediaDisplay":
            self._refresh_custom_text_visible()
        self._notify_dirty()

    def _refresh_custom_text_visible(self) -> None:
        row = self._rows.get("customText")
        if row is None:
            return
        visible = self._data.get("noMediaDisplay", NOTCH_DEFAULTS["noMediaDisplay"]) == "custom"
        row.row.set_visible(visible)

    def _notify_dirty(self) -> None:
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        old_qs = bool(self._saved.get("quickshareEnabled", NOTCH_DEFAULTS["quickshareEnabled"]))
        save_notch(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, NOTCH_DEFAULTS[key]))
        new_qs = bool(self._data.get("quickshareEnabled", NOTCH_DEFAULTS["quickshareEnabled"]))
        if new_qs != old_qs:
            self._apply_quickshare(new_qs)

    @staticmethod
    def _apply_quickshare(enabled: bool) -> None:
        core = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "quickshare_core.sh")

        def run():
            subprocess.run(
                ["bash", core, "--start" if enabled else "--stop"],
                capture_output=True, text=True, timeout=30,
                stdin=subprocess.DEVNULL,
            )

        threading.Thread(target=run, daemon=True).start()

    def discard(self) -> None:
        self._data = dict(self._saved)
        for mrow in self._rows.values():
            mrow.discard()
        self._refresh_custom_text_visible()

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                label = {
                    "position": "Position",
                    "theme": "Theme",
                    "noMediaDisplay": "No Media Display",
                    "quickshareEnabled": "Quick Share",
                }.get(key, "Notch setting")
                changed.append(label)
        if changed:
            yield PendingChange(
                category="Shell Notch",
                title="Notch",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_notch",
                icon=NOTCH_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_notch:notch", "label": "Notch",
             "description": "Position, style, hover behaviour of the shell notch",
             "_group_id": "shell_notch", "_group_label": "Notch", "_section_label": "Notch"},
            {"key": "shell_notch:quickshare", "label": "Quick Share",
             "description": "Show Quick Share in the dashboard and receive files",
             "_group_id": "shell_notch", "_group_label": "Notch", "_section_label": "Quick Share"},
        ]


__all__ = ["ShellNotchPage"]
