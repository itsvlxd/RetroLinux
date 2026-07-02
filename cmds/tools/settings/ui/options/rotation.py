"""Rotation lock toggle row — a SwitchRow that calls the display CLI directly."""

import subprocess

from gi.repository import Adw

from lib.python.variable import get_var, set_var
from settings.ui.options.base import OptionRow


class RotationLockRow(OptionRow):
    """Adw.SwitchRow that toggles auto-rotation via ``retro display rotation``.

    This option has no corresponding Hyprland config key, so the standard IPC
    apply path is bypassed entirely. State is read from ``get_var ROTATION_LOCK``
    and changes are applied by shelling out to ``retro display rotation lock|unlock``.
    """

    def __init__(self, option, value, on_change, on_reset, on_discard=None):
        row = Adw.SwitchRow(
            title=option.get("label", option["key"]),
            subtitle=option.get("description", ""),
        )
        super().__init__(row, option, on_change, on_reset, on_discard)

        self._actions.update(is_managed=False, is_dirty=False, is_saved=False)

        self._change_handler_id = row.connect("notify::active", self._on_toggle)

        locked = get_var("ROTATION_LOCK", "").strip().lower() == "true"
        row.handler_block(self._change_handler_id)
        row.set_active(locked)
        row.handler_unblock(self._change_handler_id)

    def _on_toggle(self, row, _pspec):
        locked = row.get_active()
        try:
            subprocess.run(
                ["retro", "display", "rotation", "lock" if locked else "unlock"],
                capture_output=True, text=True, check=True, timeout=10,
            )
            set_var("ROTATION_LOCK", "true" if locked else "false")
        except Exception:
            self.flash_error()
            self._set_widget_value(not locked)

    def _set_widget_value(self, value):
        self.row.set_active(bool(value))
