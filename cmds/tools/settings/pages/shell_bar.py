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
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import BAR_DEFAULTS, load_bar, save_bar
from settings.ui import clear_children, make_page_layout
from settings.ui.icons import BAR_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

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
            ("showLayoutChanger", "Show Layout Changer", "Display the dwindle/master/scrolling layout selector in the bar"),
            ("showPresetsButton", "Show Presets Button", "Display the presets manager button in the bar"),
            ("showWifiPopup", "Show Wifi Button", "Show a Wi-Fi panel button in the bar"),
            ("showBluetoothPopup", "Show Bluetooth Button", "Show a Bluetooth panel button in the bar"),
            ("showQuickSharePopup", "Show Quick Share Button", "Show a Quick Share panel button in the bar"),
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
        row.set_child(entry)
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

    def _write_live(self) -> None:
        current = load_bar()
        current.update({key: self._data.get(key, BAR_DEFAULTS[key]) for key in self._rows})
        save_bar(current)

    def _notify_dirty(self) -> None:
        self._write_live()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    # ── Lifecycle ──

    def is_dirty(self) -> bool:
        return any(self._data.get(key) != self._saved.get(key) for key in self._rows)

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        current = load_bar()
        current.update({key: self._data.get(key, BAR_DEFAULTS[key]) for key in self._rows})
        save_bar(current)
        self._saved = dict(current)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._saved.get(key, BAR_DEFAULTS[key]))

    def discard(self) -> None:
        self._data = dict(self._saved)
        for mrow in self._rows.values():
            mrow.discard()
        self._write_live()

    def reload_from_disk(self) -> None:
        """Re-read bar.json (e.g. after applying a preset) and sync widgets."""
        self._data = load_bar()
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            value = self._data.get(key, BAR_DEFAULTS[key])
            mrow.apply_value(value)
            mrow.set_baseline(value)

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
                    "showLayoutChanger": "Layout Changer",
                    "showWifiPopup": "Show Wifi Button",
                    "showBluetoothPopup": "Show Bluetooth Button",
                    "showQuickSharePopup": "Show Quick Share Button",
                }.get(key, "Bar setting")
                changed.append(label)
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
            {"key": "shell_bar:autohide", "label": "Bar Auto-hide",
             "description": "Pin, hover-to-reveal, fullscreen behaviour",
             "_group_id": "shell_bar", "_group_label": "Bar", "_section_label": "Auto-hide"},
        ]


__all__ = ["ShellBarPage"]
