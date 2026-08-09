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

from gi.repository import Adw, Gdk, Gtk

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
    PENDING_ICON,
    POWER_ICON,
    PRESETS_ICON,
    SETTINGS_ICON,
    SHELL_THEME_ICON,
    SIDEBAR_ICON,
    SLEEP_ICON,
    THEMES_ICON,
    TIMESHIFT_ICON,
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
    ("apps", "Applications", "Default applications", APPS_ICON),
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
    ("shell_misc", "Miscellaneous (Shell)", "Other shell options", MISC_ICON),
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
    ("network", "Network", "Wi-Fi and connections", NETWORK_ICON),
    ("bluetooth", "Bluetooth", "Bluetooth devices", BLUETOOTH_ICON),
    ("audio", "Audio", "Sound devices and volume", AUDIO_ICON),
    ("battery", "Battery", "Battery status and care", BATTERY_ICON),
    ("power", "Power", "Power profiles", POWER_ICON),
    ("hypridle", "Sleep", "Idle and sleep behaviour", SLEEP_ICON),
    ("disks", "Disks", "Disk health and storage", DISKS_ICON),
    ("grub", "Bootloader", "Boot entries and kernel options", GRUB_ICON),
    ("driver", "Drivers", "Hardware drivers", DRIVER_ICON),
    ("daemon", "Daemon", "Retro background services", DAEMON_ICON),
    ("backups", "Backups", "Timeshift system snapshots", TIMESHIFT_ICON),
    # Advanced
    ("keyring", "Keyring", "Passwords and secrets", KEYRING_ICON),
    ("logs", "Logs", "System and app logs", LOGS_ICON),
    ("xwayland", "XWayland", "XWayland compatibility", "application-x-executable-symbolic"),
    ("ecosystem", "Ecosystem", "Ecosystem integration", "sprout-symbolic"),
    ("misc", "Miscellaneous", "Extra options", "applications-system-symbolic"),
    # Pinned
    ("pending", "Pending Changes", "Review unsaved changes", PENDING_ICON),
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
        card.add_css_class("card")
        card.set_margin_bottom(4)
        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        inner.set_margin_top(16)
        inner.set_margin_bottom(16)
        inner.set_margin_start(16)
        inner.set_margin_end(16)
        card.append(inner)

        avatar = Adw.Avatar()
        avatar.set_size(84)
        avatar.set_show_initials(True)
        inner.append(avatar)

        user = getpass.getuser()
        avatar.set_text(user)
        self._try_set_avatar_image(avatar)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text.set_valign(Gtk.Align.CENTER)
        text.set_hexpand(True)

        name_lbl = Gtk.Label(label=user)
        name_lbl.add_css_class("title-1")
        name_lbl.set_halign(Gtk.Align.START)
        text.append(name_lbl)

        host_lbl = Gtk.Label(label=socket.gethostname())
        host_lbl.add_css_class("dim-label")
        host_lbl.set_halign(Gtk.Align.START)
        text.append(host_lbl)

        inner.append(text)
        return card

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
