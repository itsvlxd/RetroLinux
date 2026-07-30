"""Retro Settings application entry point."""

import signal
import sys

from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from settings.constants import APPLICATION_ID, settings_pkg_dir
from settings.window import RetroSettingsWindow


class RetroSettingsApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id=APPLICATION_ID,
            flags=Gio.ApplicationFlags.DEFAULT_FLAGS,
        )

    def do_startup(self):
        Adw.Application.do_startup(self)
        icon_dir = str(settings_pkg_dir() / "data" / "icons")
        display = Gdk.Display.get_default()
        if display is not None:
            theme = Gtk.IconTheme.get_for_display(display)
            paths = theme.get_search_path() or []
            theme.set_search_path([icon_dir, *paths])

    def do_activate(self):
        win = self.props.active_window
        if not isinstance(win, RetroSettingsWindow):
            target = getattr(self, "_target_page", None)
            win = RetroSettingsWindow(application=self, target_page=target)
        win.present()


def main():
    debug = "--debug" in sys.argv
    if debug:
        sys.argv.remove("--debug")

    target_page = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else None
    if target_page:
        sys.argv.pop(1)

    app = RetroSettingsApp()
    app._target_page = target_page
    app._debug = debug

    def _on_signal(*_args) -> bool:
        app.quit()
        return GLib.SOURCE_REMOVE

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, _on_signal)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, _on_signal)

    return app.run(sys.argv)


if __name__ == "__main__":
    main()
