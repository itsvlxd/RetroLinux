"""Theme selection page — browse and apply color schemes."""

import getpass
import json
import os
import re
import shutil
import subprocess
import threading
from pathlib import Path

from gi.repository import Adw, Gtk, GLib, Gdk, Pango, GObject

from lib.python.variable import get_var, get_module_default, set_var
from settings.ui import make_page_layout
from settings.ui.row_actions import RowActions

THEMES_DIR = Path(os.environ.get("RETRO_DIR", "")) / "themes"
THEME_CORE = Path(os.environ.get("RETRO_DIR", "")) / "scripts" / "theme_core.sh"
RETRO_CONFIG = Path(os.environ.get("RETRO_CONFIG", Path.home() / ".config/retro"))
USER_THEMES_DIR = RETRO_CONFIG / "themes"
OVERRIDE_DIR = USER_THEMES_DIR / "overrides"

COLOR_MAP_KEYS = [
    "primary", "on_primary", "primary_container",
    "secondary", "on_secondary", "secondary_container",
    "tertiary", "on_tertiary", "tertiary_container",
    "error", "on_error", "error_container",
    "surface", "on_surface", "surface_variant",
    "on_surface_variant", "background", "on_background",
    "outline", "outline_variant", "shadow",
    "red", "green", "yellow", "blue", "magenta", "cyan", "white", "black",
    "bright_red", "bright_green", "bright_yellow", "bright_blue",
    "bright_magenta", "bright_cyan", "bright_white", "bright_black",
]

MATUGEN_SCHEMES = [
    "scheme-tonal-spot", "scheme-vibrant", "scheme-monochrome",
    "scheme-content", "scheme-expressive", "scheme-fidelity",
    "scheme-neutral", "scheme-fruit-salad", "scheme-rainbow",
]

SCHEME_DISPLAY_NAMES = [
    "Tonal Spot", "Vibrant", "Monochrome",
    "Content", "Expressive", "Fidelity",
    "Neutral", "Fruit Salad", "Rainbow",
]

def _scheme_to_display(raw: str) -> str:
    try:
        idx = MATUGEN_SCHEMES.index(raw)
        return SCHEME_DISPLAY_NAMES[idx]
    except ValueError:
        return raw

def _lighten_color(hex_str: str, amount: float = 0.15) -> str:
    h = hex_str.lstrip("#")
    r = int(h[0:2], 16)
    g = int(h[2:4], 16)
    b = int(h[4:6], 16)
    r = min(255, int(r + (255 - r) * amount))
    g = min(255, int(g + (255 - g) * amount))
    b = min(255, int(b + (255 - b) * amount))
    return f"#{r:02x}{g:02x}{b:02x}"

def _display_to_scheme(display: str) -> str:
    try:
        idx = SCHEME_DISPLAY_NAMES.index(display)
        return MATUGEN_SCHEMES[idx]
    except ValueError:
        return display


def _extract_palette_colors(palette_rel: str) -> dict[str, str]:
    """Extract 8 ANSI colors from a palette PNG via ImageMagick.

    Matches the ``_list_displays`` fallback in ``theme_core.sh``:
    samples the palette to 8x1 pixels and maps them to ANSI keys.
    """
    palette_file = THEMES_DIR / palette_rel
    if not palette_file.is_file():
        return {}
    try:
        result = subprocess.run(
            ["convert", str(palette_file), "-sample", "8x1!", "-depth", "8", "txt:-"],
            capture_output=True, text=True, timeout=10,
        )
        hexes = re.findall(r"#[0-9A-Fa-f]{6}", result.stdout)
        # bash mapping: sampled[0]=red, [1]=green, [2]=yellow, [3]=blue,
        #               [4]=magenta, [5]=cyan, [6]=white, [7]=black
        if len(hexes) < 1:
            return {}
        color_map = {}
        order = ["red", "green", "yellow", "blue", "magenta", "cyan", "white", "black"]
        for i, key in enumerate(order):
            if i < len(hexes):
                color_map[key] = hexes[i].lstrip("#")
        return color_map
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return {}


def _load_themes() -> list[dict]:
    themes = []
    scan_dirs = [d for d in [THEMES_DIR, USER_THEMES_DIR] if d.is_dir()]
    seen_slugs: set[str] = set()
    for scan_dir in scan_dirs:
        for path in sorted(scan_dir.glob("*.json")):
            slug = path.stem
            if slug in seen_slugs:
                continue
            try:
                data = json.loads(path.read_text())
            except (json.JSONDecodeError, OSError):
                continue
            color_map = data.get("color_map", {})
            if not color_map:
                palette = data.get("palette", "")
                if palette:
                    color_map = _extract_palette_colors(palette)
            themes.append({
                "slug": slug,
                "name": data.get("name", slug),
                "author": data.get("author", ""),
                "description": data.get("description", ""),
                "link": data.get("link", ""),
                "color_map": color_map,
                "is_custom": scan_dir == USER_THEMES_DIR,
            })
            seen_slugs.add(slug)
    return themes


ANSI_KEYS = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]

RETRO_CONFIG = Path(os.environ.get("RETRO_CONFIG", Path.home() / ".config/retro"))

MATUGEN_ANSI_MAP: dict[str, str] = {
    "black": "surface",
    "red": "error",
    "green": "tertiary",
    "yellow": "primary_container",
    "blue": "primary",
    "magenta": "secondary",
    "cyan": "tertiary_container",
    "white": "on_surface",
}


def _get_matugen_colors() -> dict[str, str]:
    lua_path = RETRO_CONFIG / "themes" / "hyprland-colors.lua"
    if not lua_path.is_file():
        return {}
    try:
        text = lua_path.read_text()
    except OSError:
        return {}
    colors: dict[str, str] = {}
    for m in re.finditer(r'^\s*(\w+)\s*=\s*"0xff([0-9a-fA-F]{6})"', text, re.MULTILINE):
        colors[m.group(1)] = m.group(2)
    if not colors:
        return {}
    result: dict[str, str] = {}
    for ansi_key, material_key in MATUGEN_ANSI_MAP.items():
        hex_val = colors.get(material_key, "")
        if hex_val:
            result[ansi_key] = hex_val
    return result


def _parse_hex(hex_str: str) -> tuple[float, float, float]:
    try:
        h = hex_str.lstrip("#")
        return int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0
    except (ValueError, IndexError):
        return 0.0, 0.0, 0.0


def _make_swatch(color_hex: str) -> Gtk.DrawingArea:
    if color_hex:
        r, g, b = _parse_hex(color_hex)
    else:
        r, g, b = 0.18, 0.18, 0.18
    area = Gtk.DrawingArea()
    area.set_size_request(26, 22)
    area.set_valign(Gtk.Align.CENTER)

    def _draw(_area, cr, width, height):
        cr.set_source_rgb(r, g, b)
        cr.rectangle(0, 0, width, height)
        cr.fill()

    area.set_draw_func(_draw)
    area.add_css_class("theme-swatch")
    return area


def _make_swatches_row(color_map: dict) -> Gtk.Box:
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
    row.set_halign(Gtk.Align.START)
    row.set_margin_bottom(6)
    for key in ANSI_KEYS:
        hex_c = color_map.get(key, "")
        swatch = _make_swatch(hex_c)
        row.append(swatch)
    return row


class ThemesPage:

    def __init__(self, window):
        self._window = window
        self._themes: list[dict] = []
        self._active_scheme: str | None = None
        self._content_box: Gtk.Box | None = None
        self._flow_box: Gtk.FlowBox | None = None
        self._search_entry: Gtk.SearchEntry | None = None
        self._scheme_actions: RowActions | None = None
        self._index_actions: RowActions | None = None
        self._setting_value = False
        self._pending_scheme: str | None = None
        self._pending_index: str | None = None
        self._dirty = False
        self._notify_dirty = lambda: None

    def build(self, header: Adw.HeaderBar | None = None) -> Gtk.Widget:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        if header:
            create_btn = Gtk.Button(icon_name="list-add-symbolic")
            create_btn.set_tooltip_text("Create custom theme")
            create_btn.add_css_class("flat")
            create_btn.connect("clicked", lambda *_: self._open_theme_creator())
            header.pack_start(create_btn)

            current_mode = get_var("RETRO_THEME_MODE", "dark")
            icon = "weather-clear-night-symbolic" if current_mode == "dark" else "weather-clear-symbolic"
            tip = "Switch to Light Mode" if current_mode == "dark" else "Switch to Dark Mode"
            mode_btn = Gtk.Button(icon_name=icon)
            mode_btn.set_tooltip_text(tip)
            mode_btn.add_css_class("flat")
            mode_btn.connect("clicked", self._on_mode_toggle)
            header.pack_start(mode_btn)

        theme_config_group = Adw.PreferencesGroup(title="Theme Configuration")
        content_box.append(theme_config_group)

        self._scheme_row = Adw.ComboRow(title="Scheme Type")
        self._scheme_row.set_subtitle("Controls how colors are generated from the image — tonal spot is well-balanced, vibrant boosts saturation, monochrome uses a single hue.")
        self._scheme_row.set_model(Gtk.StringList.new(SCHEME_DISPLAY_NAMES))
        current_scheme = get_var("THEME_SCHEME", "scheme-tonal-spot")
        current_display = _scheme_to_display(current_scheme)
        if current_display in SCHEME_DISPLAY_NAMES:
            self._scheme_row.set_selected(SCHEME_DISPLAY_NAMES.index(current_display))
        else:
            self._scheme_row.set_selected(0)
        self._scheme_row.connect("notify::selected", self._on_scheme_changed)
        self._scheme_actions = RowActions(
            self._scheme_row,
            on_discard=lambda: self._discard_var("THEME_SCHEME"),
            on_reset=lambda: self._reset_var("THEME_SCHEME"),
        )
        self._scheme_row.add_suffix(self._scheme_actions.box)
        self._scheme_actions.reorder_first()
        theme_config_group.add(self._scheme_row)

        index_row = Adw.ActionRow(title="Source Color Index")
        index_row.set_subtitle("Picks which color from the source image is used to seed the palette — 0 is the most dominant color, higher values sample less prominent tones.")
        self._index_spin = Gtk.SpinButton(adjustment=Gtk.Adjustment(
            lower=0, upper=4, step_increment=1
        ))
        self._index_spin.set_value(int(get_var("THEME_SOURCE_INDEX", "0")))
        self._index_spin.set_valign(Gtk.Align.CENTER)
        self._index_spin.connect("notify::value", self._on_index_changed)
        index_row.add_suffix(self._index_spin)
        self._index_actions = RowActions(
            index_row,
            on_discard=lambda: self._discard_var("THEME_SOURCE_INDEX"),
            on_reset=lambda: self._reset_var("THEME_SOURCE_INDEX"),
        )
        index_row.add_suffix(self._index_actions.box)
        self._index_actions.reorder_first()
        theme_config_group.add(index_row)

        self._search_entry = Gtk.SearchEntry()
        self._search_entry.set_placeholder_text("Search themes\u2026")
        self._search_entry.set_margin_top(12)
        self._search_entry.connect("search-changed", self._on_search)
        content_box.append(self._search_entry)

        flow = self._make_flowbox()
        content_box.append(flow)
        self._flow_box = flow

        spinner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        spinner_box.set_valign(Gtk.Align.CENTER)
        spinner_box.set_halign(Gtk.Align.CENTER)
        spinner_box.set_margin_top(48)
        spinner = Gtk.Spinner()
        spinner.set_size_request(32, 32)
        spinner.start()
        spinner_box.append(spinner)
        lbl = Gtk.Label(label="Loading themes\u2026")
        lbl.add_css_class("dim-label")
        spinner_box.append(lbl)
        self._spinner_box = spinner_box
        content_box.append(spinner_box)

        self._active_scheme = get_var("RETRO_THEME_SCHEME", "wallpaper")
        self._load_themes_async()

        return toolbar

    def _load_themes_async(self) -> None:
        def worker():
            themes = _load_themes()
            GLib.idle_add(self._on_themes_loaded, themes)
        threading.Thread(target=worker, daemon=True).start()

    def _on_themes_loaded(self, themes: list[dict]) -> None:
        self._themes = themes
        if self._spinner_box is not None and self._content_box is not None:
            self._content_box.remove(self._spinner_box)
            self._spinner_box = None
        self._rebuild()
        self._refresh_managed()

    def _make_flowbox(self) -> Gtk.FlowBox:
        flow = Gtk.FlowBox()
        flow.set_max_children_per_line(4)
        flow.set_min_children_per_line(2)
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_column_spacing(10)
        flow.set_row_spacing(10)
        flow.set_margin_top(12)
        flow.set_vexpand(True)
        return flow

    def _rebuild(self):
        content_box = self._content_box
        if content_box is None:
            return

        search = (self._search_entry.get_text() if self._search_entry else "").strip().lower()
        new_flow = self._make_flowbox()

        self._themes.sort(key=lambda t: (0 if t["slug"] == self._active_scheme else 1, t["name"].lower()))

        for theme in self._themes:
            if search and search not in theme["name"].lower():
                continue
            if theme["slug"] == self._active_scheme and self._active_scheme != "wallpaper":
                card = self._make_card(theme)
                new_flow.append(card)

        wallpaper_card = self._make_wallpaper_card()
        new_flow.append(wallpaper_card)

        for theme in self._themes:
            if search and search not in theme["name"].lower():
                continue
            if theme["slug"] != self._active_scheme:
                card = self._make_card(theme)
                new_flow.append(card)

        if self._flow_box is not None:
            content_box.remove(self._flow_box)
        self._flow_box = new_flow
        content_box.append(self._flow_box)

    def _make_wallpaper_card(self) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.add_css_class("card")
        card.add_css_class("theme-card")
        if self._active_scheme == "wallpaper":
            card.add_css_class("theme-card-active")
        card.set_margin_top(6)
        card.set_margin_bottom(6)

        active_color_map = {}
        if self._active_scheme != "wallpaper":
            for theme in self._themes:
                if theme["slug"] == self._active_scheme:
                    active_color_map = theme.get("color_map", {})
                    break
        else:
            active_color_map = _get_matugen_colors()
        swatches = _make_swatches_row(active_color_map)
        swatches.set_margin_start(12)
        swatches.set_margin_end(12)
        swatches.set_margin_top(12)
        card.append(swatches)

        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header_box.set_margin_top(6)
        header_box.set_margin_start(12)
        header_box.set_margin_end(12)
        header_box.set_margin_bottom(6)

        icon = Gtk.Image.new_from_icon_name("camera-symbolic")
        icon.set_pixel_size(20)
        icon.set_valign(Gtk.Align.START)
        header_box.append(icon)

        name_label = Gtk.Label()
        name_label.set_markup("<b>Sync from Wallpaper</b>")
        name_label.set_halign(Gtk.Align.START)
        name_label.set_valign(Gtk.Align.CENTER)
        name_label.set_ellipsize(Pango.EllipsizeMode.END)
        header_box.append(name_label)

        active_badge = Gtk.Label(label="Active")
        active_badge.add_css_class("badge")
        active_badge.add_css_class("active-badge")
        active_badge.set_halign(Gtk.Align.END)
        active_badge.set_valign(Gtk.Align.CENTER)
        active_badge.set_margin_start(8)
        if self._active_scheme != "wallpaper":
            active_badge.set_visible(False)
        header_box.append(active_badge)

        card.append(header_box)

        author_label = Gtk.Label(label="Matugen")
        author_label.set_halign(Gtk.Align.START)
        author_label.set_margin_start(12)
        author_label.set_margin_end(12)
        author_label.add_css_class("caption")
        author_label.set_xalign(0.0)
        card.append(author_label)

        subtitle = Gtk.Label(label="Automatically generate a color scheme from your current wallpaper using Matugen — colors adapt to whatever wallpaper you set")
        subtitle.set_halign(Gtk.Align.START)
        subtitle.set_margin_start(12)
        subtitle.set_margin_end(12)
        subtitle.set_margin_bottom(14)
        subtitle.add_css_class("caption")
        subtitle.set_wrap(True)
        subtitle.set_xalign(0.0)
        card.append(subtitle)

        click_gesture = Gtk.GestureClick()
        click_gesture.connect("pressed", lambda *_: self._on_theme_clicked("wallpaper", "Sync from Wallpaper"))
        card.add_controller(click_gesture)

        return card

    def _make_card(self, theme: dict) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        card.set_halign(Gtk.Align.CENTER)
        card.add_css_class("card")
        card.add_css_class("theme-card")
        is_active = theme["slug"] == self._active_scheme
        if is_active:
            card.add_css_class("theme-card-active")

        color_map = theme.get("color_map", {})
        swatches = _make_swatches_row(color_map)
        swatches.set_margin_start(12)
        swatches.set_margin_end(12)
        swatches.set_margin_top(12)
        card.append(swatches)

        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        name_box.set_margin_start(12)
        name_box.set_margin_end(12)

        name_label = Gtk.Label()
        name_label.set_markup(f"<b>{GLib.markup_escape_text(theme['name'])}</b>")
        name_label.set_halign(Gtk.Align.START)
        name_label.set_hexpand(True)
        name_label.set_ellipsize(Pango.EllipsizeMode.END)
        name_box.append(name_label)

        settings_btn = Gtk.Button(icon_name="emblem-system-symbolic")
        settings_btn.add_css_class("flat")
        settings_btn.set_valign(Gtk.Align.CENTER)
        settings_btn.set_tooltip_text("Customize colors")
        settings_btn.connect("clicked", lambda *_: self._open_override_dialog(theme))
        name_box.append(settings_btn)

        if is_active:
            active_badge = Gtk.Label(label="Active")
            active_badge.add_css_class("badge")
            active_badge.add_css_class("active-badge")
            active_badge.set_halign(Gtk.Align.END)
            active_badge.set_valign(Gtk.Align.CENTER)
            name_box.append(active_badge)

        card.append(name_box)

        if theme["author"]:
            url = theme.get("link", "")
            author_label = Gtk.Label()
            if url:
                escaped_author = GLib.markup_escape_text(theme["author"])
                escaped_url = GLib.markup_escape_text(url)
                author_label.set_markup(f'<a href="{escaped_url}">{escaped_author}</a>')
                author_label.connect("activate-link", lambda _l, uri: (Gtk.show_uri(None, uri, Gdk.CURRENT_TIME), True)[1])
            else:
                author_label.set_label(theme["author"])
            author_label.set_halign(Gtk.Align.START)
            author_label.set_margin_start(12)
            author_label.set_margin_end(12)
            author_label.add_css_class("caption")
            author_label.set_xalign(0.0)
            card.append(author_label)

        if theme["description"]:
            desc_label = Gtk.Label(label=theme["description"])
            desc_label.set_halign(Gtk.Align.START)
            desc_label.set_margin_start(12)
            desc_label.set_margin_end(12)
            desc_label.set_margin_bottom(14)
            desc_label.add_css_class("caption")
            desc_label.set_wrap(True)
            desc_label.set_xalign(0.0)
            card.append(desc_label)

        click_gesture = Gtk.GestureClick()

        def _card_pressed(gest, _n, x, y, _slug=theme["slug"], _name=theme["name"]):
            if self._click_is_on_button(card, x, y, settings_btn):
                return
            self._on_theme_clicked(_slug, _name)

        click_gesture.connect("pressed", _card_pressed)
        card.add_controller(click_gesture)

        return card

    @staticmethod
    def _click_is_on_button(container, x: float, y: float, button: Gtk.Widget) -> bool:
        try:
            child = container.pick(x, y, Gtk.PickFlags.DEFAULT)
        except Exception:
            return False
        while child is not None:
            if child is button:
                return True
            child = child.get_parent()
        return False

    def _on_theme_clicked(self, slug: str, name: str) -> None:
        if not THEME_CORE.is_file():
            self._window.show_toast(f"Failed to apply {name}")
            return
        set_var("RETRO_THEME_SCHEME", slug)
        self._active_scheme = slug
        self._rebuild()
        proc = subprocess.Popen(
            ["bash", str(THEME_CORE), "--theme", slug],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        GLib.child_watch_add(
            proc.pid,
            lambda _pid, _status, _s=slug, _n=name: self._window.show_toast(f"Applied {_n}"),
        )

    def _on_search(self, _entry: Gtk.SearchEntry) -> None:
        self._rebuild()

    def _on_scheme_changed(self, row: Adw.ComboRow, _pspec) -> None:
        if self._setting_value:
            return
        display = SCHEME_DISPLAY_NAMES[row.get_selected()]
        self._pending_scheme = _display_to_scheme(display)
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _on_index_changed(self, spin: Gtk.SpinButton, _pspec) -> None:
        if self._setting_value:
            return
        self._pending_index = str(int(spin.get_value()))
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _refresh_managed(self) -> None:
        for row_actions, var, default in (
            (self._scheme_actions, "THEME_SCHEME", "scheme-tonal-spot"),
            (self._index_actions, "THEME_SOURCE_INDEX", "0"),
        ):
            if row_actions is None:
                continue
            live = get_var(var, "")
            pending = self._pending_for(var)
            effective = pending if pending is not None else live
            is_managed = effective != default
            is_dirty_val = self._has_pending(var)
            is_saved = live != default
            row_actions.update(is_managed=is_managed, is_dirty=is_dirty_val, is_saved=is_saved)

    def _pending_for(self, var_name: str) -> str | None:
        if var_name == "THEME_SCHEME":
            return self._pending_scheme
        if var_name == "THEME_SOURCE_INDEX":
            return self._pending_index
        return None

    def _get_pending(self, var_name: str) -> str | None:
        if var_name == "THEME_SCHEME":
            return self._pending_scheme
        if var_name == "THEME_SOURCE_INDEX":
            return self._pending_index
        return None

    def _set_pending(self, var_name: str, value: str) -> None:
        if var_name == "THEME_SCHEME":
            self._pending_scheme = value
        elif var_name == "THEME_SOURCE_INDEX":
            self._pending_index = value

    def _clear_pending(self, var_name: str) -> None:
        if var_name == "THEME_SCHEME":
            self._pending_scheme = None
        elif var_name == "THEME_SOURCE_INDEX":
            self._pending_index = None

    def _has_pending(self, var_name: str) -> bool:
        if var_name == "THEME_SCHEME":
            return self._pending_scheme is not None
        if var_name == "THEME_SOURCE_INDEX":
            return self._pending_index is not None
        return False

    def _check_dirty(self) -> None:
        any_dirty = self._has_pending("THEME_SCHEME") or self._has_pending("THEME_SOURCE_INDEX")
        if any_dirty != self._dirty:
            self._dirty = any_dirty
            self._notify_dirty()

    def _discard_var(self, var_name: str) -> None:
        live = get_var(var_name, get_module_default(var_name))
        self._set_widget_value(var_name, live)
        self._clear_pending(var_name)
        self._check_dirty()
        self._refresh_managed()

    def _reset_var(self, var_name: str) -> None:
        default = get_module_default(var_name)
        self._set_widget_value(var_name, default)
        self._set_pending(var_name, default)
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _set_widget_value(self, var_name: str, value: str) -> None:
        self._setting_value = True
        if var_name == "THEME_SCHEME":
            display = _scheme_to_display(value)
            if display in SCHEME_DISPLAY_NAMES:
                self._scheme_row.set_selected(SCHEME_DISPLAY_NAMES.index(display))
        elif var_name == "THEME_SOURCE_INDEX":
            if value.isdigit():
                self._index_spin.set_value(float(value))
        self._setting_value = False

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        self._dirty = False
        self._pending_scheme = None
        self._pending_index = None
        self._refresh_managed()

    def flush_pending(self) -> None:
        if self._pending_scheme is not None:
            from lib.python.variable import set_var as set_py_var
            set_py_var("THEME_SCHEME", self._pending_scheme)
            subprocess.Popen(
                ["retro", "theme", "apply-colors"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        if self._pending_index is not None:
            from lib.python.variable import set_var as set_py_var
            set_py_var("THEME_SOURCE_INDEX", self._pending_index)
            subprocess.Popen(
                ["retro", "theme", "apply-colors"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        self.mark_saved()

    def _on_mode_toggle(self, btn: Gtk.Button) -> None:
        current = get_var("RETRO_THEME_MODE", "dark")
        new_mode = "light" if current == "dark" else "dark"
        btn.set_sensitive(False)
        proc = subprocess.Popen(
            ["retro", "theme", "mode", new_mode],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        GLib.child_watch_add(proc.pid, lambda _pid, _status, _btn=btn, _m=new_mode: (
            _btn.set_sensitive(True),
            _btn.set_icon_name("weather-clear-night-symbolic" if _m == "dark" else "weather-clear-symbolic"),
            _btn.set_tooltip_text("Switch to Light Mode" if _m == "dark" else "Switch to Dark Mode"),
            self._window.show_toast(f"Theme mode set to {_m.title()}"),
        ))

    def _open_override_dialog(self, theme: dict) -> None:
        dialog = OverrideDialog(self._window, theme)
        dialog.present()

    def _open_theme_creator(self) -> None:
        dialog = ThemeCreatorDialog(self._window)
        dialog.present()
        dialog.connect("theme-created", lambda _dl, slug: (
            set_var("RETRO_THEME_SCHEME", slug),
            self._rebuild(),
        ))

    def get_search_entries(self) -> list[dict]:
        entries: list[dict] = []
        entries.append({
            "key": "themes:page",
            "label": "Themes",
            "description": "Browse and apply color schemes",
            "_group_id": "themes",
            "_group_label": "Themes",
            "_section_label": "",
        })
        for theme in self._themes:
            entries.append({
                "key": f"themes:{theme['slug']}",
                "label": theme["name"],
                "description": theme["description"] or theme["author"],
                "_group_id": "themes",
                "_group_label": "Themes",
                "_section_label": "",
            })
        return entries


class OverrideDialog(Adw.Window):
    """Dialog for customizing individual color values in a theme."""

    def __init__(self, parent: Adw.ApplicationWindow, theme: dict):
        super().__init__(
            transient_for=parent,
            modal=True,
            title=f"Customize {theme['name']}",
            default_width=500,
            default_height=600,
        )
        self._theme = theme
        self._overrides: dict[str, str] = {}
        self._defaults: dict[str, str] = theme.get("color_map", {})

        self._overrides = self._load_overrides(theme["slug"])

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        header = Adw.HeaderBar()
        content.append(header)

        save_btn = Gtk.Button(label="Save")
        save_btn.add_css_class("suggested-action")
        save_btn.connect("clicked", self._on_save)
        header.pack_end(save_btn)

        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda *_: self.close())
        header.pack_end(cancel_btn)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content.append(scrolled)

        list_box = Gtk.ListBox()
        list_box.add_css_class("boxed-list")
        scrolled.set_child(list_box)

        # Track color buttons
        self._color_btns: dict[str, Gtk.ColorButton] = {}

        for key in COLOR_MAP_KEYS:
            default_hex = self._defaults.get(key, "")
            current_hex = self._overrides.get(key, default_hex)
            display_hex = current_hex or "#888888"

            row = Adw.ActionRow()
            row.set_title(key.replace("_", " ").title())
            row.set_subtitle(f"Default: {default_hex or 'not set'}")

            btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

            color_btn = Gtk.ColorButton()
            rgba = Gdk.RGBA()
            rgba.parse(display_hex)
            color_btn.set_rgba(rgba)
            color_btn.set_tooltip_text(current_hex or "not set")
            color_btn.set_valign(Gtk.Align.CENTER)
            color_btn.connect("notify::rgba", self._on_color_changed, key)
            btn_box.append(color_btn)
            self._color_btns[key] = color_btn

            reset_btn = Gtk.Button(icon_name="edit-undo-symbolic")
            reset_btn.add_css_class("flat")
            reset_btn.set_valign(Gtk.Align.CENTER)
            reset_btn.set_tooltip_text("Reset to default")
            reset_btn.connect("clicked", self._on_reset, key, default_hex)
            btn_box.append(reset_btn)

            if key in self._overrides:
                badge = Gtk.Label(label="Custom")
                badge.add_css_class("badge")
                badge.set_valign(Gtk.Align.CENTER)
                btn_box.append(badge)

            row.add_suffix(btn_box)
            list_box.append(row)

        self.set_content(content)

    def _load_overrides(self, slug: str) -> dict[str, str]:
        try:
            proc = subprocess.run(
                ["bash", str(THEME_CORE), "--override-get", slug],
                capture_output=True, text=True, timeout=10,
            )
        except (subprocess.TimeoutExpired, OSError):
            return {}
        overrides: dict[str, str] = {}
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                key, _, val = line.partition("|")
                key = key.strip()
                if key:
                    overrides[key] = val.strip()
        return overrides

    def _on_color_changed(self, btn: Gtk.ColorButton, _pspec, key: str) -> None:
        rgba = btn.get_rgba()
        hex_str = f"#{int(rgba.red * 255):02x}{int(rgba.green * 255):02x}{int(rgba.blue * 255):02x}"
        btn.set_tooltip_text(hex_str)
        default_hex = self._defaults.get(key, "")
        if default_hex and hex_str.lower() == default_hex.lower():
            self._overrides.pop(key, None)
        else:
            self._overrides[key] = hex_str

    def _on_reset(self, _btn, key: str, default_hex: str) -> None:
        self._overrides.pop(key, None)
        color_btn = self._color_btns[key]
        rgba = Gdk.RGBA()
        rgba.parse(default_hex or "#888888")
        color_btn.set_rgba(rgba)
        color_btn.set_tooltip_text(default_hex or "not set")

    def _on_save(self, _btn) -> None:
        slug = self._theme["slug"]
        subprocess.run(
            ["bash", str(THEME_CORE), "--override-clear", slug],
            capture_output=True, timeout=10,
        )
        for key, val in self._overrides.items():
            subprocess.run(
                ["bash", str(THEME_CORE), "--override-set", slug, key, val],
                capture_output=True, timeout=10,
            )
        # Re-apply theme colors with overrides
        proc = subprocess.Popen(
            ["bash", str(THEME_CORE), "--theme", slug],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        GLib.child_watch_add(proc.pid, lambda _p, _s: (
            self.get_transient_for().show_toast(f"Colors updated for {self._theme['name']}"),
            self.close(),
        ))


class ThemeCreatorDialog(Adw.Window):
    """Dialog for creating custom themes."""

    __gsignals__ = {
        "theme-created": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
    }

    def __init__(self, parent: Adw.ApplicationWindow):
        super().__init__(
            transient_for=parent,
            modal=True,
            title="Create Custom Theme",
            default_width=550,
            default_height=700,
        )

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        header = Adw.HeaderBar()
        content.append(header)

        save_btn = Gtk.Button(label="Save Theme")
        save_btn.add_css_class("suggested-action")
        save_btn.connect("clicked", self._on_save)
        header.pack_end(save_btn)

        import_btn = Gtk.Button(label="Import from Image")
        import_btn.add_css_class("flat")
        import_btn.connect("clicked", self._on_import)
        header.pack_start(import_btn)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content.append(scrolled)

        clamp = Adw.Clamp()
        scrolled.set_child(clamp)

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        main_box.set_margin_top(12)
        main_box.set_margin_bottom(12)
        main_box.set_margin_start(12)
        main_box.set_margin_end(12)
        clamp.set_child(main_box)

        # Theme info fields
        info_group = Adw.PreferencesGroup(title="Theme Info")
        main_box.append(info_group)

        self._name_entry = Adw.EntryRow(title="Name")
        self._name_entry.connect("changed", lambda *_: None)
        info_group.add(self._name_entry)

        self._author_entry = Adw.EntryRow(title="Author")
        self._author_entry.set_text(getpass.getuser())
        info_group.add(self._author_entry)

        self._desc_entry = Adw.EntryRow(title="Description")
        info_group.add(self._desc_entry)

        # Color fields group
        colors_group = Adw.PreferencesGroup(title="Colors")
        main_box.append(colors_group)

        self._color_rows: dict[str, Adw.ActionRow] = {}
        self._color_btns: dict[str, Gtk.ColorButton] = {}

        for key in COLOR_MAP_KEYS:
            default_for_key = {
                "primary": "#b24bf3", "on_primary": "#ffffff",
                "primary_container": "#12102e", "secondary": "#6b70ff",
                "tertiary": "#ffcc33", "error": "#ff2a6d",
                "surface": "#070514", "on_surface": "#e5e9f0",
                "background": "#070514", "on_background": "#e5e9f0",
                "outline": "#323c58", "red": "#ff2a6d",
                "green": "#05ffa1", "yellow": "#ffcc33",
                "blue": "#6b70ff", "magenta": "#b24bf3",
                "cyan": "#00d9ff", "white": "#d1d1e0",
                "black": "#030208",
            }
            default = default_for_key.get(key, "#000000")

            row = Adw.ActionRow()
            row.set_title(key.replace("_", " ").title())
            colors_group.add(row)

            color_btn = Gtk.ColorButton()
            rgba = Gdk.RGBA()
            rgba.parse(default)
            color_btn.set_rgba(rgba)
            color_btn.set_valign(Gtk.Align.CENTER)
            row.add_suffix(color_btn)

            self._color_btns[key] = color_btn
            self._color_rows[key] = row

        self.set_content(content)

    def _on_save(self, _btn) -> None:
        name = self._name_entry.get_text().strip()
        if not name:
            self.get_transient_for().show_toast("Theme name is required")
            return

        author = self._author_entry.get_text().strip() or getpass.getuser()
        description = self._desc_entry.get_text().strip() or f"Custom theme by {author}"

        color_map = {}
        for key, btn in self._color_btns.items():
            rgba = btn.get_rgba()
            hex_str = f"#{int(rgba.red * 255):02x}{int(rgba.green * 255):02x}{int(rgba.blue * 255):02x}"
            color_map[key] = hex_str

        json_payload = json.dumps({
            "name": name,
            "author": author,
            "description": description,
            "color_map": color_map,
        }, indent=4)

        proc = subprocess.Popen(
            ["bash", str(THEME_CORE), "--custom-theme-create", json_payload],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
        stdout, _ = proc.communicate()
        if proc.returncode == 0 and stdout.startswith("success|"):
            slug = stdout.strip().split("|", 1)[1]
            self.emit("theme-created", slug)
            self.close()
        else:
            error = stdout.strip() if stdout else "Unknown error"
            self.get_transient_for().show_toast(f"Failed to create theme: {error}")

    def _on_import(self, _btn) -> None:
        if not shutil.which("matugen"):
            self.get_transient_for().show_toast("matugen is not installed")
            return
        file_chooser = Gtk.FileChooserNative(
            title="Select image for color extraction",
            transient_for=self,
            action=Gtk.FileChooserAction.OPEN,
        )
        filt = Gtk.FileFilter()
        filt.set_name("Images")
        filt.add_mime_type("image/png")
        filt.add_mime_type("image/jpeg")
        filt.add_mime_type("image/webp")
        file_chooser.add_filter(filt)
        file_chooser.connect("response", self._on_import_response)
        file_chooser.show()

    def _on_import_response(self, dialog, response):
        if response != Gtk.ResponseType.ACCEPT:
            return
        path = dialog.get_file().get_path()
        if not path:
            return
        mode = get_var("RETRO_THEME_MODE", "dark")
        scheme = get_var("THEME_SCHEME", "scheme-tonal-spot")
        index = int(get_var("THEME_SOURCE_INDEX", "0"))
        self.get_transient_for().show_toast("Extracting colors from image...")
        print(f"[DEBUG] matugen import: path={path} mode={mode} scheme={scheme} index={index}", file=__import__('sys').stderr)
        proc = subprocess.run(
            ["matugen", "image", path, "--dry-run", "--json", "hex",
             "--source-color-index", str(index), "-t", scheme],
            capture_output=True, text=True, timeout=15,
        )
        if proc.returncode != 0:
            error_msg = proc.stderr.strip()[:200] if proc.stderr.strip() else "unknown error"
            print(f"[DEBUG] matugen failed (rc={proc.returncode}): {error_msg}", file=__import__('sys').stderr)
            print(f"[DEBUG] matugen stderr: {proc.stderr[:500]}", file=__import__('sys').stderr)
            self.get_transient_for().show_toast(f"matugen failed: {error_msg}")
            return
        print(f"[DEBUG] matugen stdout (first 500 chars): {proc.stdout[:500]}", file=__import__('sys').stderr)
        try:
            data = json.loads(proc.stdout)
        except json.JSONDecodeError as e:
            print(f"[DEBUG] JSON parse error: {e}", file=__import__('sys').stderr)
            self.get_transient_for().show_toast("Failed to parse matugen output")
            return
        colors_data = data.get("colors", {})
        print(f"[DEBUG] colors_data keys: {list(colors_data.keys())[:15]}...", file=__import__('sys').stderr)
        MATUGEN_MAP = {
            "primary": "primary", "on_primary": "on_primary",
            "primary_container": "primary_container",
            "secondary": "secondary", "tertiary": "tertiary",
            "error": "error", "surface": "surface",
            "on_surface": "on_surface", "background": "background",
            "on_background": "on_background", "outline": "outline",
            "surface_variant": "surface_variant",
            "red": "error", "green": "tertiary",
            "yellow": "primary_container", "blue": "primary",
            "magenta": "secondary", "cyan": "tertiary_container",
            "white": "on_surface", "black": "surface",
        }
        imported_hexes: dict[str, str] = {}
        filled = 0
        for key, material_key in MATUGEN_MAP.items():
            color_entry = colors_data.get(material_key, {})
            mode_entry = color_entry.get(mode, {})
            hex_val = mode_entry.get("color", "")
            print(f"[DEBUG]   {key} -> colors.{material_key}.{mode}.color = {hex_val!r}", file=__import__('sys').stderr)
            if hex_val and key in self._color_btns:
                imported_hexes[key] = hex_val
                rgba = Gdk.RGBA()
                rgba.parse(hex_val)
                self._color_btns[key].set_rgba(rgba)
                filled += 1
        BRIGHT_MAP = {
            "bright_red": "red", "bright_green": "green", "bright_yellow": "yellow",
            "bright_blue": "blue", "bright_magenta": "magenta", "bright_cyan": "cyan",
            "bright_white": "white", "bright_black": "black",
        }
        for bright_key, base_key in BRIGHT_MAP.items():
            base_hex = imported_hexes.get(base_key)
            if base_hex and bright_key in self._color_btns:
                lightened = _lighten_color(base_hex, 0.15)
                rgba = Gdk.RGBA()
                rgba.parse(lightened)
                self._color_btns[bright_key].set_rgba(rgba)
                filled += 1

        print(f"[DEBUG] filled {filled} color values", file=__import__('sys').stderr)
        self.get_transient_for().show_toast(f"Colors imported from image ({filled} values filled)")
