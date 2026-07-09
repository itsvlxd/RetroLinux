"""Retro Settings application entry point."""

import signal
import sys
from pathlib import Path

from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from settings.constants import APPLICATION_ID
from settings.window import RetroSettingsWindow


class RetroSettingsApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id=APPLICATION_ID,
            flags=Gio.ApplicationFlags.DEFAULT_FLAGS,
        )

    def do_startup(self):
        Adw.Application.do_startup(self)
        icon_dir = str(Path(__file__).resolve().parent / "data" / "icons")
        display = Gdk.Display.get_default()
        if display is not None:
            theme = Gtk.IconTheme.get_for_display(display)
            paths = theme.get_search_path() or []
            theme.set_search_path([icon_dir, *paths])

    def do_activate(self):
        win = self.props.active_window
        if not isinstance(win, RetroSettingsWindow):
            win = RetroSettingsWindow(application=self)
        win.present()


def main():
    debug = "--debug" in sys.argv
    if debug:
        sys.argv.remove("--debug")

    app = RetroSettingsApp()

    def _on_signal(*_args) -> bool:
        app.quit()
        return GLib.SOURCE_REMOVE

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, _on_signal)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, _on_signal)

    return app.run(sys.argv)


if __name__ == "__main__":
    main()
