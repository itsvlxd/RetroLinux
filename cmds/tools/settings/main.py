"""Retro Settings application entry point."""

import signal
import sys
import time as _time

def _dbg(msg: str) -> None:
    if "--debug" in sys.argv or "-d" in sys.argv:
        print(f"[SETTINGS-DBG] {msg}", file=sys.stderr, flush=True)

_dbg(f"Starting ({_time.monotonic():.3f})")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402
_dbg(f"GTK loaded ({_time.monotonic():.3f})")

from settings.constants import APPLICATION_ID, settings_pkg_dir  # noqa: E402
_dbg(f"constants loaded ({_time.monotonic():.3f})")
from settings.window import RetroSettingsWindow  # noqa: E402
_dbg(f"window module loaded ({_time.monotonic():.3f})")


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
        _dbg(f"Debug mode enabled, argv={sys.argv}")

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

    _dbg(f"Entering GTK main loop ({_time.monotonic():.3f})")
    return app.run(sys.argv)


if __name__ == "__main__":
    main()
