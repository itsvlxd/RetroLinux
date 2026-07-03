"""Dialog for adding or editing a single retro startup command."""

from collections.abc import Callable

from gi.repository import Adw, Gtk

from settings.core.desktop_apps import DesktopApp
from settings.ui.app_picker import AppPickerDialog
from settings.ui.dialog import SingletonDialogMixin


class RetroStartupEditDialog(SingletonDialogMixin, Adw.Dialog):
    """Dialog for adding or editing a single retro startup command."""

    def __init__(
        self,
        *,
        command: str = "",
        on_apply: Callable[[str], None] | None = None,
    ):
        super().__init__()
        self._on_apply_callback = on_apply

        self.set_title("Add Startup Command" if not command else "Edit Startup Command")
        self.set_content_width(520)
        self.set_content_height(200)

        toolbar = Adw.ToolbarView()

        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: self.close())
        header.pack_start(cancel_btn)

        self._apply_btn = Gtk.Button(label="Apply")
        self._apply_btn.add_css_class("suggested-action")
        self._apply_btn.connect("clicked", self._on_apply)
        self._apply_btn.set_sensitive(bool(command))
        header.pack_end(self._apply_btn)
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)

        cmd_group = Adw.PreferencesGroup(title="Command")
        cmd_group.set_description(
            "Type a shell command to run during the Retro startup sequence."
        )
        self._cmd_entry = Adw.EntryRow(title="Command line")
        self._cmd_entry.set_text(command)
        self._cmd_entry.connect("changed", self._on_changed)
        self._cmd_entry.connect("entry-activated", lambda _e: self._on_apply())

        pick_btn = Gtk.Button.new_from_icon_name("system-search-symbolic")
        pick_btn.set_valign(Gtk.Align.CENTER)
        pick_btn.add_css_class("flat")
        pick_btn.set_tooltip_text("Pick from installed apps")
        pick_btn.connect("clicked", lambda _b: self._on_pick_app())
        self._cmd_entry.add_suffix(pick_btn)

        cmd_group.add(self._cmd_entry)
        content.append(cmd_group)

        toolbar.set_content(content)
        self.set_child(toolbar)

        self._cmd_entry.grab_focus()
        self._refresh_apply_sensitive()

    def _on_pick_app(self) -> None:
        def on_pick(app: DesktopApp) -> None:
            self._cmd_entry.set_text(app.command)
            self._cmd_entry.grab_focus()

        AppPickerDialog.present_singleton(self, on_pick=on_pick)

    def _on_changed(self, *_args: object) -> None:
        self._refresh_apply_sensitive()

    def _refresh_apply_sensitive(self) -> None:
        self._apply_btn.set_sensitive(bool(self._cmd_entry.get_text().strip()))

    def _on_apply(self, *_args: object) -> None:
        command = self._cmd_entry.get_text().strip()
        if not command:
            return
        if self._on_apply_callback is not None:
            self._on_apply_callback(command)
        self.close()


__all__ = ["RetroStartupEditDialog"]
