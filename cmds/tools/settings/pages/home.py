"""Home page — Windows-style landing page.

Shows a user card (avatar, username, hostname) and a grid of tiles for
every settings page. Clicking a tile navigates to that page (or, for
``backups``, launches Timeshift). ``PAGE_REGISTRY`` is the single list
of pages with title/description/icon — the home grid and the search
index both consume it so a new page shows up in both places.
"""

import getpass
import os
import socket
import subprocess
import threading

from gi.repository import Adw, Gdk, GLib, Gtk

from settings.ui import make_page_layout
from settings.ui.icons import (
    ABOUT_ICON,
    APPS_ICON,
    AUDIO_ICON,
    AUTOSTART_ICON,
    BAR_ICON,
    BATTERY_ICON,
    BINDS_ICON,
    BLUETOOTH_ICON,
    DAEMON_ICON,
    DESKTOP_ICON,
    DISKS_ICON,
    DOCK_ICON,
    DRIVER_ICON,
    ENV_VARS_ICON,
    FONTS_ICON,
    FRAME_ICON,
    GRUB_ICON,
    KEYRING_ICON,
    LAYER_RULES_ICON,
    LAYOUTS_ICON,
    LOCK_ICON,
    LOGS_ICON,
    MISC_ICON,
    MONITORS_ICON,
    NETWORK_ICON,
    NOTCH_ICON,
    OVERVIEW_ICON,
    POWER_ICON,
    PRESETS_ICON,
    SETTINGS_ICON,
    SHELL_THEME_ICON,
    SIDEBAR_ICON,
    THEMES_ICON,
    TIMESHIFT_ICON,
    USERS_ICON,
    WALLPAPERS_ICON,
    WINDOW_RULES_ICON,
    WORKSPACES_ICON,
)

# (slug, title, description, icon-name) — one entry per settings page,
# ordered to mirror the sidebar. Schema-group icons come from
# ``data/schema/options.json``; the rest mirror ``ui/icons.py``.
PAGE_REGISTRY: list[tuple[str, str, str, str]] = [
    # Style
    ("appearance", "Appearance", "Gaps, rounding, blur and general look", "sliders-horizontal-arrow-symbolic"),
    ("decoration", "Decoration", "Shadows and window decorations", "appearance-symbolic"),
    ("animations", "Animations", "Motion and transition curves", "bounce-symbolic"),
    ("cursor", "Cursor", "Pointer size and behaviour", "hyprmod-cursor-symbolic"),
    ("fonts", "Fonts", "Interface and document fonts", FONTS_ICON),
    ("themes", "Themes", "GTK and application themes", THEMES_ICON),
    ("shell_theme", "Shell", "Shell styling and look", SHELL_THEME_ICON),
    ("apps", "Applications", "Customize app look", APPS_ICON),
    # Shell
    ("shell_bar", "Bar", "Top bar layout and modules", BAR_ICON),
    ("shell_notch", "Notch", "Notch look and behaviour", NOTCH_ICON),
    ("shell_sidebar", "Sidebar", "Shell sidebar panel", SIDEBAR_ICON),
    ("shell_frame", "Frame", "Window frame styling", FRAME_ICON),
    ("shell_workspaces", "Workspaces (Shell)", "Workspace bar modules", WORKSPACES_ICON),
    ("shell_overview", "Overview", "Overview screen", OVERVIEW_ICON),
    ("shell_dock", "Dock", "Dock applications", DOCK_ICON),
    ("shell_desktop", "Desktop", "Desktop widgets", DESKTOP_ICON),
    ("shell_lock", "Lockscreen", "Lock screen styling", LOCK_ICON),
    ("shell_presets", "Presets", "Shell presets", PRESETS_ICON),
    # Input
    ("binds", "Keybinds", "Keyboard shortcuts and bindings", BINDS_ICON),
    ("input", "Devices", "Keyboard, mouse and touchpad", "input-keyboard-symbolic"),
    ("gestures", "Gestures", "Workspace swipe gestures", "gesture-swipe-left-symbolic"),
    # Display
    ("monitors", "Monitors", "Displays and resolution", MONITORS_ICON),
    ("wallpapers", "Wallpapers", "Desktop wallpapers", WALLPAPERS_ICON),
    ("workspaces", "Workspaces", "Workspace layout and behaviour", WORKSPACES_ICON),
    # Window Management
    ("layouts", "Layouts", "Tiling layouts and behaviour", LAYOUTS_ICON),
    ("window_rules", "Window Rules", "Rules for windows", WINDOW_RULES_ICON),
    ("layer_rules", "Layer Rules", "Rules for overlay layers", LAYER_RULES_ICON),
    # Startup
    ("autostart", "Autostart", "Apps that launch on login", AUTOSTART_ICON),
    ("env_vars", "Env Variables", "Environment variables", ENV_VARS_ICON),
    # System
    ("users", "Users", "Create and manage system users", USERS_ICON),
    ("network", "Network", "Wi-Fi and connections", NETWORK_ICON),
    ("bluetooth", "Bluetooth", "Bluetooth devices", BLUETOOTH_ICON),
    ("audio", "Audio", "Sound devices and volume", AUDIO_ICON),
    ("battery", "Battery", "Battery status and care", BATTERY_ICON),
    ("power", "Power", "Power profiles, idle and sleep", POWER_ICON),
    ("disks", "Disks", "Disk health and storage", DISKS_ICON),
    ("grub", "Bootloader", "Boot entries and kernel options", GRUB_ICON),
    ("driver", "Drivers", "Hardware drivers", DRIVER_ICON),
    ("daemon", "Daemon", "Retro background services", DAEMON_ICON),
    ("xdg", "Default Apps", "Default apps, MIME types and directories", APPS_ICON),
    ("backups", "Backups", "Timeshift system snapshots", TIMESHIFT_ICON),
    # Advanced
    ("keyring", "Keyring", "Passwords and secrets", KEYRING_ICON),
    ("logs", "Logs", "System and app logs", LOGS_ICON),
    ("xwayland", "XWayland", "XWayland compatibility", "application-x-executable-symbolic"),
    ("ecosystem", "Ecosystem", "Ecosystem integration", "sprout-symbolic"),
    ("misc", "Miscellaneous", "Misc options, startup and OCR", "applications-system-symbolic"),
    # Pinned
    ("about", "About", "System info, updates and links", ABOUT_ICON),
    ("settings", "Settings", "App preferences and config path", SETTINGS_ICON),
]

_TILES_PER_ROW = 4


class HomePage:
    """Read-only landing page: user card + navigation tile grid."""

    def __init__(self, window):
        self._window = window

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(
            header=header, spacing=20
        )
        content_box.append(self._build_user_card())
        content_box.append(self._build_grid())
        return toolbar

    # ── User card ──

    def _build_user_card(self) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        card.add_css_class("hero-card")
        card.set_margin_bottom(4)
        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=20)
        inner.set_margin_top(18)
        inner.set_margin_bottom(18)
        inner.set_margin_start(18)
        inner.set_margin_end(18)
        card.append(inner)

        self._user = getpass.getuser()

        avatar = Adw.Avatar()
        avatar.set_size(84)
        avatar.set_show_initials(True)
        avatar.set_text(self._user)
        self._try_set_avatar_image(avatar)
        self._avatar = avatar

        avatar_btn = Gtk.Button()
        avatar_btn.add_css_class("flat")
        avatar_btn.add_css_class("circular")
        avatar_btn.set_valign(Gtk.Align.CENTER)
        avatar_btn.set_child(avatar)
        avatar_btn.set_tooltip_text("Change profile picture")
        avatar_btn.connect("clicked", lambda _b: self._on_change_picture())
        self._avatar_btn = avatar_btn

        overlay = Gtk.Overlay()
        overlay.set_child(avatar_btn)

        camera = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        camera.set_halign(Gtk.Align.CENTER)
        camera.set_valign(Gtk.Align.CENTER)
        camera.add_css_class("avatar-hover-icon")
        cam_img = Gtk.Image.new_from_icon_name("camera-photo-symbolic")
        cam_img.set_pixel_size(28)
        camera.append(cam_img)
        camera.set_visible(False)
        overlay.add_overlay(camera)
        self._avatar_camera = camera

        motion = Gtk.EventControllerMotion.new()
        motion.connect("enter", lambda *_a: self._avatar_camera.set_visible(True))
        motion.connect("leave", lambda *_a: self._avatar_camera.set_visible(False))
        overlay.add_controller(motion)

        avatar_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        avatar_box.set_valign(Gtk.Align.CENTER)
        avatar_box.append(overlay)
        inner.append(avatar_box)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        text.set_valign(Gtk.Align.CENTER)
        text.set_hexpand(True)

        hostname = socket.gethostname()
        accent_hex = "#ee1a1a1a"
        ok, rgba = avatar_btn.get_style_context().lookup_color("accent_color")
        if ok:
            accent_hex = "#{:02x}{:02x}{:02x}".format(
                round(rgba.red * 255), round(rgba.green * 255), round(rgba.blue * 255)
            )
        user_host = Gtk.Label()
        user_host.set_markup(
            f'<span size="28000" weight="bold">{self._user}</span>'
            f'<span size="28000" weight="bold" foreground="{accent_hex}">@{hostname}</span>'
        )
        user_host.set_halign(Gtk.Align.START)
        user_host.set_xalign(0)
        user_host.set_wrap(True)
        text.append(user_host)

        device = self._device_name()
        device_lbl = Gtk.Label(label=device)
        device_lbl.add_css_class("dim-label")
        device_lbl.add_css_class("heading")
        device_lbl.set_halign(Gtk.Align.START)
        device_lbl.set_xalign(0)
        device_lbl.set_wrap(True)
        device_lbl.set_lines(2)
        text.append(device_lbl)

        inner.append(text)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        info.set_valign(Gtk.Align.CENTER)
        info.set_halign(Gtk.Align.END)

        version_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        version_box.set_halign(Gtk.Align.CENTER)

        version = Gtk.Label(label=self._os_version())
        version.add_css_class("pill")
        version.add_css_class("success")
        version.set_halign(Gtk.Align.CENTER)
        version_box.append(version)

        uptime = Gtk.Label(label=f"up {self._uptime()}")
        uptime.add_css_class("dim-label")
        uptime.add_css_class("caption")
        uptime.set_halign(Gtk.Align.CENTER)
        version_box.append(uptime)

        info.append(version_box)

        update_btn = Gtk.Button(label="Check Updates")
        update_btn.add_css_class("suggested-action")
        update_btn.set_halign(Gtk.Align.CENTER)
        update_btn.connect("clicked", lambda _b: self._window.navigate("about"))
        info.append(update_btn)

        inner.append(info)
        return card

    @staticmethod
    def _device_name() -> str:
        def read(path: str) -> str:
            try:
                with open(path) as f:
                    return f.read().strip()
            except OSError:
                return ""

        vendor = read("/sys/class/dmi/id/sys_vendor")
        product = read("/sys/class/dmi/id/product_name")
        if product:
            return f"{vendor} {product}".strip() if vendor and vendor not in product else product
        return socket.gethostname()

    @staticmethod
    def _os_version() -> str:
        from settings.core.system_info import _os_version, display_version
        version = display_version(_os_version())
        return version[:1].upper() + version[1:] if version else version

    @staticmethod
    def _uptime() -> str:
        try:
            with open("/proc/uptime") as f:
                seconds = float(f.read().split()[0])
        except (OSError, ValueError, IndexError):
            return ""
        minutes = int(seconds // 60)
        hours, minutes = divmod(minutes, 60)
        days, hours = divmod(hours, 24)
        parts = []
        if days:
            parts.append(f"{days}d")
        if hours:
            parts.append(f"{hours}h")
        if minutes:
            parts.append(f"{minutes}m")
        return " ".join(parts) or "just started"

    def _on_change_picture(self) -> None:
        dialog = Gtk.FileDialog.new()
        dialog.set_title("Choose a profile picture")

        def on_chosen(_dlg, result):
            try:
                gfile = dialog.open_finish(result)
            except GLib.Error:
                return
            if not gfile:
                return
            path = gfile.get_path()
            if not path or not os.path.isfile(path):
                return
            self._set_face(path)

        dialog.open(self._window, None, on_chosen)

    def _set_face(self, path: str) -> None:
        core = os.path.join(
            os.environ.get("RETRO_DIR", "/opt/retrolinux"),
            "scripts", "users_core.sh",
        )
        args = ["bash", core, "--set-face", self._user, path]

        def worker():
            subprocess.run(args, capture_output=True, text=True, timeout=30,
                           stdin=subprocess.DEVNULL)
            GLib.idle_add(self._refresh_avatar)

        threading.Thread(target=worker, daemon=True).start()

    def _refresh_avatar(self) -> None:
        self._try_set_avatar_image(self._avatar)

    @staticmethod
    def _try_set_avatar_image(avatar: Adw.Avatar) -> None:
        """Use ~/.face.icon when present; otherwise fall back to initials."""
        face = os.path.expanduser("~/.face.icon")
        if not os.path.exists(face):
            return
        try:
            texture = Gdk.Texture.new_from_filename(face)
            avatar.set_custom_image(texture)
        except Exception:
            pass

    # ── Page grid ──

    def _build_grid(self) -> Gtk.Widget:
        # A Grid (not FlowBox) so the row count is exact: with homogeneous
        # FlowBox sizing, tiles grew to the widest title's minimum width and
        # only 2 fit per line. Grid columns are homogeneous and fixed at
        # ``_TILES_PER_ROW``, so the tiles always lay out in clean rows.
        grid = Gtk.Grid()
        grid.set_column_homogeneous(True)
        grid.set_row_spacing(10)
        grid.set_column_spacing(10)
        for i, (slug, title, description, icon) in enumerate(PAGE_REGISTRY):
            tile = self._make_tile(slug, title, description, icon)
            tile.set_hexpand(True)
            grid.attach(tile, i % _TILES_PER_ROW, i // _TILES_PER_ROW, 1, 1)
        return grid

    def _make_tile(self, slug: str, title: str, description: str, icon: str) -> Gtk.Widget:
        button = Gtk.Button()
        button.add_css_class("flat")
        button.add_css_class("home-tile")
        button.set_halign(Gtk.Align.FILL)
        button.set_valign(Gtk.Align.FILL)
        button.set_tooltip_text(description)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.set_halign(Gtk.Align.FILL)
        box.set_hexpand(True)
        box.set_margin_top(2)
        box.set_margin_bottom(2)
        box.set_margin_start(2)
        box.set_margin_end(2)

        img = Gtk.Image.new_from_icon_name(icon)
        img.set_pixel_size(34)
        img.set_halign(Gtk.Align.START)
        img.set_valign(Gtk.Align.CENTER)
        box.append(img)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_valign(Gtk.Align.CENTER)
        text.set_hexpand(True)

        title_lbl = Gtk.Label(label=title)
        title_lbl.set_halign(Gtk.Align.START)
        # 4-column tiles are ~170px wide, so long titles must wrap to a
        # second line rather than clip (Grid rows size to their tallest
        # child, keeping the row height consistent).
        title_lbl.set_wrap(True)
        title_lbl.set_lines(2)
        title_lbl.add_css_class("heading")
        text.append(title_lbl)

        desc_lbl = Gtk.Label(label=description)
        desc_lbl.set_halign(Gtk.Align.START)
        desc_lbl.set_wrap(True)
        desc_lbl.set_lines(2)
        desc_lbl.add_css_class("dim-label")
        desc_lbl.add_css_class("caption")
        text.append(desc_lbl)

        box.append(text)
        button.set_child(box)
        button.connect("clicked", lambda _b, s=slug: self._window.navigate(s))
        return button

    # ── Lifecycle (read-only) ──

    def is_dirty(self) -> bool:
        return False

    def mark_saved(self) -> None:
        pass

    def discard(self) -> None:
        pass

    def iter_pending_changes(self):
        return ()

__all__ = ["HomePage", "PAGE_REGISTRY"]
