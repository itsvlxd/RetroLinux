"""Shell Notifications page — configure notification sounds.

Values are written to ``~/.config/retro/shell/notifications.json``; the shell's
``FileView`` watches that file with ``watchChanges`` and reloads on external
writes, so changes apply live without a shell restart.
"""

import os
import subprocess
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import NOTIFICATIONS_DEFAULTS, load_notifications, save_notifications
from settings.ui import make_page_layout
from settings.ui.icons import NOTIFICATION_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_SND_DIR = "/opt/retrolinux/modules/retroshell/files/assets/sound"

_SOUND_OPTIONS = [
    ("retro-default.mp3", "Retro Default"),
    ("gentle-chime.wav", "Gentle Chime"),
    ("correct-answer.wav", "Correct Answer"),
    ("double-beep.wav", "Double Beep"),
    ("dry-pop.wav", "Dry Pop"),
    ("long-pop.wav", "Long Pop"),
    ("message-pop.mp3", "Message Pop"),
    ("dragon-chime.mp3", "Dragon Chime"),
    ("bright-chime.mp3", "Bright Chime"),
    ("new-chime.mp3", "New Chime"),
]


class ShellNotificationsPage:
    """Shell notification settings — writes ``notifications.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None
        self._data = load_notifications()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)

        sounds_group = Adw.PreferencesGroup(
            title="Sounds",
            description="Sound, volume, and enable/disable.",
        )
        self._add_switch(sounds_group, "soundEnabled", "Enable Sounds",
                         subtitle="Play sounds when notifications arrive")
        sound_mrow = self._add_combo(sounds_group, "soundFile", "Notification Sound", _SOUND_OPTIONS,
                                     subtitle="Which sound plays on notification")
        preview_btn = Gtk.Button(icon_name="media-playback-start-symbolic")
        preview_btn.set_valign(Gtk.Align.CENTER)
        preview_btn.add_css_class("flat")
        preview_btn.set_tooltip_text("Preview sound")
        preview_btn.connect("clicked", self._on_preview)
        sound_mrow.row.add_suffix(preview_btn)
        self._add_spin(sounds_group, "soundVolume", "Volume", lower=0, upper=100, suffix="%",
                       subtitle="Notification sound volume percentage")
        content_box.append(sounds_group)

        return toolbar

    # ── Row builders ──

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    *, subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, NOTIFICATIONS_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()
        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(row, default=NOTIFICATIONS_DEFAULTS[key],
                          baseline=self._saved.get(key, NOTIFICATIONS_DEFAULTS[key]),
                          get_value=get_value, set_value_silent=set_silent,
                          on_value_set=lambda v, k=key: self._on_change(k, v))
        self._rows[key] = mrow
        row.connect("notify::active", lambda *a, k=key, m=mrow: (setattr(self, '_data', {**self._data, k: m.value}), m.refresh(), self._notify_dirty()))
        return mrow

    def _add_combo(self, group: Adw.PreferencesGroup, key: str, label: str,
                   options: list[tuple[str, str]], *, subtitle: str = "") -> ManagedRow:
        ids = [o[0] for o in options]
        labels = [o[1] for o in options]
        current = self._data.get(key, NOTIFICATIONS_DEFAULTS[key])
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

        mrow = ManagedRow(row, default=NOTIFICATIONS_DEFAULTS[key],
                          baseline=self._saved.get(key, NOTIFICATIONS_DEFAULTS[key]),
                          get_value=get_value, set_value_silent=set_silent,
                          on_value_set=lambda v, k=key: self._on_change(k, v))
        self._rows[key] = mrow
        row.connect("notify::selected", lambda *a, k=key, m=mrow: (setattr(self, '_data', {**self._data, k: m.value}), m.refresh(), self._notify_dirty()))
        return mrow

    def _add_spin(self, group: Adw.PreferencesGroup, key: str, label: str,
                  *, lower: int, upper: int, suffix: str, subtitle: str = "") -> ManagedRow:
        row, spin = make_spin_int_row(label, value=int(self._data.get(key, NOTIFICATIONS_DEFAULTS[key])),
                                      lower=lower, upper=upper, step=5, page_step=10, subtitle=subtitle)
        group.add(row)
        if suffix:
            l = Gtk.Label(label=suffix); l.add_css_class("dim-label"); l.set_valign(Gtk.Align.CENTER); row.add_suffix(l)

        def get_value(): return int(spin.get_value())
        def set_silent(value): spin.set_value(int(value))

        mrow = ManagedRow(row, default=NOTIFICATIONS_DEFAULTS[key],
                          baseline=self._saved.get(key, NOTIFICATIONS_DEFAULTS[key]),
                          get_value=get_value, set_value_silent=set_silent,
                          on_value_set=lambda v, k=key: self._on_change(k, v))
        self._rows[key] = mrow
        spin.connect("value-changed", lambda *a, k=key, m=mrow: (setattr(self, '_data', {**self._data, k: m.value}), m.refresh(), self._notify_dirty()))
        return mrow

    # ── Preview ──

    def _on_preview(self, _btn) -> None:
        sound_file = self._data.get("soundFile", NOTIFICATIONS_DEFAULTS["soundFile"])
        volume = int(self._data.get("soundVolume", NOTIFICATIONS_DEFAULTS["soundVolume"]))
        path = os.path.join(_SND_DIR, sound_file)
        if not os.path.exists(path):
            return
        pa_vol = int(volume * 65536 / 100)
        try:
            subprocess.run(["paplay", "--volume", str(pa_vol), path], capture_output=True, timeout=5)
        except Exception:
            try:
                subprocess.run(["mpg123", "-q", "--gain", str(volume), path], capture_output=True, timeout=5)
            except Exception:
                pass

    # ── Change plumbing ──

    def _on_change(self, key: str, value) -> None:
        self._data[key] = value
        self._notify_dirty()

    def _write_live(self) -> None:
        save_notifications(self._data)

    def _notify_dirty(self) -> None:
        self._write_live()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    # ── Lifecycle ──

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        save_notifications(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, NOTIFICATIONS_DEFAULTS[key]))

    def discard(self) -> None:
        self._data = dict(self._saved)
        for mrow in self._rows.values():
            mrow.discard()
        self._write_live()

    def reload_from_disk(self) -> None:
        self._data = load_notifications()
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            value = self._data.get(key, NOTIFICATIONS_DEFAULTS[key])
            mrow.apply_value(value)
            mrow.set_baseline(value)

    # ── Pending changes ──

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                changed.append({"soundEnabled": "Enable", "soundFile": "Sound",
                                "soundVolume": "Volume"}.get(key, key))
        yield PendingChange(category="Notifications", title="Notifications",
                            subtitle=", ".join(changed[:3]), navigate_to="shell_notifications",
                            icon=NOTIFICATION_ICON, kind="modified", revert=self.discard)

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_notifications:sounds", "label": "Notifications",
             "description": "Sound, volume, and enable/disable",
             "_group_id": "shell_notifications", "_group_label": "Notifications",
             "_section_label": "Notifications"},
        ]


__all__ = ["ShellNotificationsPage"]
