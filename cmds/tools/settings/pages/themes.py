"""Theme selection page — browse and apply color schemes."""

import json
import os
import re
import subprocess
from pathlib import Path

from gi.repository import Adw, Gtk, GLib, Gdk, Pango

from lib.python import get_var, set_var
from settings.ui import make_page_layout

THEMES_DIR = Path(os.environ.get("RETRO_DIR", "")) / "themes"
THEME_CORE = Path(os.environ.get("RETRO_DIR", "")) / "scripts" / "theme_core.sh"


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
    if not THEMES_DIR.is_dir():
        return themes
    paths = sorted(THEMES_DIR.glob("*.json"))
    for path in paths:
        slug = path.stem
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
        })
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

    def build(self, header: Adw.HeaderBar | None = None) -> Gtk.Widget:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        if header:
            current_mode = get_var("RETRO_THEME_MODE", "dark")
            icon = "weather-clear-night-symbolic" if current_mode == "dark" else "weather-clear-symbolic"
            tip = "Switch to Light Mode" if current_mode == "dark" else "Switch to Dark Mode"
            mode_btn = Gtk.Button(icon_name=icon)
            mode_btn.set_tooltip_text(tip)
            mode_btn.add_css_class("flat")
            mode_btn.connect("clicked", self._on_mode_toggle)
            header.pack_start(mode_btn)

        self._search_entry = Gtk.SearchEntry()
        self._search_entry.set_placeholder_text("Search themes\u2026")
        self._search_entry.set_margin_top(12)
        self._search_entry.connect("search-changed", self._on_search)
        content_box.append(self._search_entry)

        flow = self._make_flowbox()
        content_box.append(flow)
        self._flow_box = flow

        self._active_scheme = get_var("RETRO_THEME_SCHEME", "wallpaper")
        self._themes = _load_themes()
        self._rebuild()

        return toolbar

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
        click_gesture.connect("pressed", lambda *_: self._on_theme_clicked(theme["slug"], theme["name"]))
        card.add_controller(click_gesture)

        return card

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
