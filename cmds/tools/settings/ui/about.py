"""About dialog — standard GNOME ``Adw.AboutDialog``."""

from gi.repository import Adw, Gtk

from settings.constants import APPLICATION_ID

APPLICATION_NAME = "Retro Settings"
DEVELOPER_NAME = "RetroLinux"
COPYRIGHT = "© 2026 RetroLinux"
COMMENTS = "A native GTK4/libadwaita settings app for Hyprland"
DEVELOPERS = ["RetroLinux https://github.com/anomalyco/retrolinux"]


def build_about_dialog(running_hyprland_version: str | None = None) -> Adw.AboutDialog:
    version = "0.1.0"

    debug_info = (
        f"Retro Settings {version}\n"
        f"Hyprland (running): {running_hyprland_version or 'not detected'}\n"
    )

    return Adw.AboutDialog(
        application_name=APPLICATION_NAME,
        application_icon=APPLICATION_ID,
        version=version,
        developer_name=DEVELOPER_NAME,
        developers=DEVELOPERS,
        copyright=COPYRIGHT,
        license_type=Gtk.License.GPL_3_0,
        comments=COMMENTS,
        debug_info=debug_info,
    )
