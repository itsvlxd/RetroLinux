"""About dialog — standard GNOME ``Adw.AboutDialog``."""

from gi.repository import Adw, Gtk

from settings.constants import APPLICATION_ID
from settings.core.system_info import (
    _kernel_arch,
    _kernel_build_date,
    _os_branch,
    _os_version,
    _release_line,
    display_version,
    get_preloaded_info,
)
from settings.core.system_info import _run as _run_cmd

APPLICATION_NAME = "Retro Settings"
DEVELOPER_NAME = "RetroLinux"
COPYRIGHT = "© 2026 RetroLinux"
COMMENTS = (
    "The global settings app for Retro Linux — one place for the whole system, "
    "from style to hardware.\n\n"
    "Style — appearance, decorations, animations, cursors, fonts, themes, and "
    "how applications are presented.\n"
    "Shell — the Retro bar, notch, sidebar, window frame, workspaces, overview, "
    "dock, desktop, lockscreen, and presets.\n"
    "Input — keybinds, mouse and touchpad devices, and gestures.\n"
    "Display — monitors, wallpapers, and workspace behaviour.\n"
    "Windows — tiling layouts, window rules, and layer rules.\n"
    "Startup — autostart applications and environment variables.\n"
    "System — network, Bluetooth, audio, battery, power, sleep, disks, the "
    "bootloader, drivers, and the Retro daemon.\n"
    "Advanced — keyring, logs, XWayland, ecosystem integrations, and more.\n\n"
    "Changes apply live to your desktop configuration, with search, undo, and a "
    "pending-changes review before anything is saved."
)
DEVELOPERS = ["RetroLinux https://github.com/anomalyco/retrolinux"]


def _retro_linux_version() -> str:
    """Retro Linux version (git tag/branch), e.g. ``nightly (develop)``."""
    version = display_version(_os_version())
    branch = _os_branch()
    return f"{version} ({branch})" if branch else version


def _build_debug_info(running_hyprland_version: str | None) -> str:
    """Full system detail for the debug section, using the preloaded specs
    when available and falling back to a lightweight subset otherwise."""
    version = _retro_linux_version()
    kernel = _run_cmd(["uname", "-r"])
    kernel_parts = [kernel or "—", _kernel_arch() or "—"]
    if _kernel_build_date():
        kernel_parts.append(f"built {_kernel_build_date()}")
    lines = [
        f"Retro Linux {version} — {_release_line()}",
        f"Kernel: {' · '.join(kernel_parts)}",
        f"Hyprland (running): {running_hyprland_version or 'not detected'}",
    ]

    info = get_preloaded_info()
    if info is not None:
        lines.append(f"Processor: {info.cpu_label}")
        lines.append(f"Memory: {info.mem_label}")
        lines.append(f"Storage: {info.storage_label}")
        lines.append(f"Uptime: {info.uptime}")

    return "\n".join(lines)


def build_about_dialog(running_hyprland_version: str | None = None) -> Adw.AboutDialog:
    version = _retro_linux_version()

    return Adw.AboutDialog(
        application_name=APPLICATION_NAME,
        application_icon=APPLICATION_ID,
        version=version,
        developer_name=DEVELOPER_NAME,
        developers=DEVELOPERS,
        copyright=COPYRIGHT,
        license_type=Gtk.License.GPL_3_0,
        comments=COMMENTS,
        debug_info=_build_debug_info(running_hyprland_version),
    )
