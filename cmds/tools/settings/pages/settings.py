"""Application settings page — config path, auto-save, and update-timer prefs."""

import shutil
from collections.abc import Iterable
from pathlib import Path

from gi.repository import Adw, Gio, GLib, Gtk

from settings.core import config
from settings.core.pending import PendingChange
from settings.ui import confirm, make_page_layout
from settings.ui.row_actions import RowActions

# (var, title, subtitle, lower, upper, step)
_UPDATE_ROWS: list[tuple[str, str, str, int, int, int]] = [
    ("RETRO_PKG_UPDATE_MIN", "Package check interval",
     "How often the daemon checks for package updates (in minutes).", 1, 10080, 5),
    ("RETRO_UPDATE_CHECK_MIN", "Retro update check interval",
     "How often the daemon checks for Retro Linux git updates (in minutes).", 1, 10080, 1),
    ("RETRO_PKG_UPDATE_THRESH", "Update notification threshold",
     "Minimum number of available updates before a notification is shown.", 1, 1000, 10),
]


class SettingsPage:
    """Settings page for application preferences."""

    def __init__(self, window):
        self._window = window
        self._dirty = False
        self._on_dirty_changed = None
        self._spins: dict[str, Gtk.SpinButton] = {}
        self._actions: dict[str, RowActions] = {}
        self._orig: dict[str, str] = {}
        self._setting_value = False

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)

        # ── Config section ──
        config_group = Adw.PreferencesGroup(
            title="Configuration",
            description="Manage where Retro Settings reads and writes Hyprland settings.",
        )

        default_str = str(config.default_managed_path())
        self._config_path_row = Adw.EntryRow(title="Config file path")
        self._config_path_row.set_text(self._window.config_path)
        self._config_path_row.set_show_apply_button(True)
        self._config_path_row.set_input_hints(Gtk.InputHints.NO_SPELLCHECK)
        self._config_path_row.set_tooltip_text(f"Default: {default_str}")
        # Track the handler id so ``_reset_path_text`` can block it while
        # programmatically resetting the entry — toggling
        # ``set_show_apply_button`` to suppress the apply signal would
        # work but is the boolean-flag anti-pattern.
        self._apply_handler_id = self._config_path_row.connect("apply", self._on_config_path_apply)

        browse_btn = Gtk.Button(icon_name="document-open-symbolic")
        browse_btn.set_valign(Gtk.Align.CENTER)
        browse_btn.set_tooltip_text("Browse\u2026")
        browse_btn.connect("clicked", self._on_browse_config)
        self._config_path_row.add_suffix(browse_btn)

        config_group.add(self._config_path_row)
        content_box.append(config_group)

        # ── Behavior section ──
        behavior_group = Adw.PreferencesGroup(
            title="Behavior",
        )

        self._auto_save_row = Adw.SwitchRow(
            title="Auto-save",
            subtitle="Automatically save changes after each modification.",
        )
        self._auto_save_row.set_active(self._window.auto_save)
        self._auto_save_row.connect("notify::active", self._on_auto_save_toggled)

        behavior_group.add(self._auto_save_row)
        content_box.append(behavior_group)

        # ── Updates section ──
        updates_group = Adw.PreferencesGroup(
            title="Updates",
            description="Controls the update-check intervals and notification threshold. "
            "Changes apply on the next daemon cycle.",
        )
        self._orig = {}
        for var, title, subtitle, lower, upper, step in _UPDATE_ROWS:
            from lib.python.variable import get_var, get_module_default
            value = get_var(var, get_module_default(var, ""))
            self._orig[var] = value

            row = Adw.ActionRow(title=title, subtitle=subtitle)
            adj = Gtk.Adjustment(
                value=float(value) if value and value.isdigit() else float(get_module_default(var, "120")),
                lower=lower, upper=upper, step_increment=step, page_increment=step * 5,
            )
            spin = Gtk.SpinButton(adjustment=adj, digits=0)
            spin.set_valign(Gtk.Align.CENTER)
            spin.connect("notify::value", self._on_spin_changed, var)
            row.add_suffix(spin)
            self._spins[var] = spin

            actions = RowActions(
                row,
                on_discard=lambda v=var: self._discard_var(v),
                on_reset=lambda v=var: self._reset_var(v),
            )
            row.add_suffix(actions.box)
            actions.reorder_first()
            self._actions[var] = actions

            updates_group.add(row)

        content_box.append(updates_group)

        return toolbar

    def sync_auto_save(self, value: bool):
        """Update the switch to reflect an external auto-save change."""
        if self._auto_save_row.get_active() != value:
            self._auto_save_row.set_active(value)

    def _reset_path_text(self, text: str):
        """Reset the entry text without re-arming the apply signal."""
        self._config_path_row.handler_block(self._apply_handler_id)
        try:
            self._config_path_row.set_text(text)
        finally:
            self._config_path_row.handler_unblock(self._apply_handler_id)

    # ── Callbacks ──

    def _apply_new_path(self, new_text: str, *, overwrite_confirmed: bool = False):
        """Validate and apply a new config file path."""
        new_path = Path(new_text).expanduser()
        old_path = config.managed_path()

        if new_path.resolve() == old_path.resolve():
            return

        if new_path.exists() and not overwrite_confirmed:

            def _on_confirm():
                self._do_migrate(old_path, new_path)
                self._reset_path_text(self._window.config_path)

            confirm(
                self._window,
                heading="Overwrite existing file?",
                body=f"{new_path.name} already exists at this location. "
                "It will be replaced with the current config.",
                label="Overwrite",
                on_confirm=_on_confirm,
            )
        else:
            self._do_migrate(old_path, new_path)

    def _do_migrate(self, old_path: Path, new_path: Path):
        """Move config and update internal state."""
        try:
            new_path.parent.mkdir(parents=True, exist_ok=True)
            if old_path.exists():
                shutil.move(old_path, new_path)
        except OSError as e:
            self._window.show_toast(f"Cannot move config — {e.strerror}", timeout=5, copy=True)
            return

        self._window.config_path = str(new_path)

    def _on_config_path_apply(self, row):
        text = row.get_text().strip()
        if not text:
            text = str(config.default_managed_path())
        if text != self._window.config_path:
            self._apply_new_path(text)
        self._reset_path_text(self._window.config_path)

    def _on_browse_config(self, _btn):
        dialog = Gtk.FileDialog()
        dialog.set_title("Select config file")

        current = Path(self._window.config_path)
        if current.parent.exists():
            dialog.set_initial_folder(Gio.File.new_for_path(str(current.parent)))
        if current.name:
            dialog.set_initial_name(current.name)

        dialog.save(self._window, None, self._on_file_chosen)

    def _on_file_chosen(self, dialog, result):
        try:
            gfile = dialog.save_finish(result)
        except GLib.Error:
            # User cancelled the dialog or chooser failed — nothing to apply.
            return
        if gfile:
            self._apply_new_path(gfile.get_path(), overwrite_confirmed=True)
            self._reset_path_text(self._window.config_path)

    def _on_auto_save_toggled(self, row, _pspec):
        self._window.set_auto_save(row.get_active())

    # ── Update var handlers ──

    def _on_spin_changed(self, spin: Gtk.SpinButton, _pspec, var: str) -> None:
        if self._setting_value:
            return
        self._check_dirty()

    def _discard_var(self, var: str) -> None:
        self._set_spin(var, self._orig.get(var, ""))
        self._check_dirty()
        self._refresh_managed()

    def _reset_var(self, var: str) -> None:
        from lib.python.variable import get_module_default
        default = get_module_default(var, "")
        self._set_spin(var, default or "")
        self._check_dirty()
        self._refresh_managed()

    def _set_spin(self, var: str, val: str) -> None:
        spin = self._spins.get(var)
        if spin is None:
            return
        self._setting_value = True
        try:
            spin.set_value(float(val) if val and val.isdigit() else 0.0)
        finally:
            self._setting_value = False

    def _refresh_managed(self) -> None:
        for var, actions in self._actions.items():
            live = self._current(var)
            default = self._module_default(var)
            actions.update(
                is_managed=live != default,
                is_dirty=live != self._orig.get(var, ""),
                is_saved=live != default,
            )

    def _current(self, var: str) -> str:
        spin = self._spins.get(var)
        return str(int(spin.get_value())) if spin is not None else ""

    @staticmethod
    def _module_default(var: str) -> str:
        from lib.python.variable import get_module_default
        return get_module_default(var, "")

    def _check_dirty(self) -> None:
        was = self._dirty
        self._dirty = any(self._current(v) != self._orig.get(v, "") for v in self._spins)
        if was != self._dirty and self._on_dirty_changed:
            self._on_dirty_changed()

    # ── Lifecycle ──

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        if not self._dirty:
            return
        from lib.python.variable import set_var
        for var in self._spins:
            set_var(var, self._current(var))
        self._orig = {v: self._current(v) for v in self._spins}
        self._dirty = False
        self._refresh_managed()
        if self._on_dirty_changed:
            self._on_dirty_changed()

    def discard(self) -> None:
        for var in self._spins:
            self._set_spin(var, self._orig.get(var, ""))
        self._dirty = False
        self._refresh_managed()
        if self._on_dirty_changed:
            self._on_dirty_changed()

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._dirty:
            changed = [v for v in self._spins if self._current(v) != self._orig.get(v, "")]
            yield PendingChange(
                category="Settings",
                title="Update Preferences",
                subtitle=", ".join(changed),
                navigate_to="settings",
                icon="preferences-system-symbolic",
                kind="modified",
                revert=self.discard,
            )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "settings:config", "label": "Config file path",
             "description": "Set the Hyprland config file location",
             "_group_id": "settings", "_group_label": "Settings", "_section_label": "Configuration"},
            {"key": "settings:auto_save", "label": "Auto-save",
             "description": "Automatically save changes after each modification",
             "_group_id": "settings", "_group_label": "Settings", "_section_label": "Behavior"},
            {"key": "settings:updates", "label": "Update Preferences",
             "description": "Package/Retro check intervals and notification threshold",
             "_group_id": "settings", "_group_label": "Settings", "_section_label": "Updates"},
        ]


__all__ = ["SettingsPage"]
