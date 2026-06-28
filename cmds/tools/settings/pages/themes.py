"""Theme selection page — browse and apply color schemes."""

import json
import os
import re
import subprocess
from pathlib import Path

from gi.repository import Adw, Gtk, GLib, Gdk, Pango

from lib.python import get_module_default, get_var, set_var
from settings.ui import make_page_layout
from settings.ui.row_actions import RowActions

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

    MODE_MODES = ["dark", "light"]
    MODE_DISPLAY = ["Dark", "Light"]

    def __init__(self, window):
        self._window = window
        self._themes: list[dict] = []
        self._active_scheme: str | None = None
        self._content_box: Gtk.Box | None = None
        self._flow_box: Gtk.FlowBox | None = None
        self._search_entry: Gtk.SearchEntry | None = None
        self._dirty = False
        self._notify_dirty = lambda: None
        self._pending_mode: str | None = None
        self._mode_row: Adw.ComboRow | None = None
        self._mode_actions: RowActions | None = None

    def build(self, header: Adw.HeaderBar | None = None) -> Gtk.Widget:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        pref_group = Adw.PreferencesGroup()
        current_mode = get_var("RETRO_THEME_MODE", "dark")
        mode_idx = self.MODE_MODES.index(current_mode) if current_mode in self.MODE_MODES else 0
        mode_model = Gtk.StringList.new(self.MODE_DISPLAY)
        mode_row = Adw.ComboRow(title="Theme Mode")
        mode_row.set_subtitle("Choose between dark and light theme variants")
        mode_row.set_model(mode_model)
        mode_row.set_selected(mode_idx)
        mode_row.connect("notify::selected", self._on_mode_changed)
        self._mode_actions = RowActions(
            mode_row,
            on_discard=lambda: self._discard_mode(),
            on_reset=lambda: self._reset_mode(),
        )
        mode_row.add_suffix(self._mode_actions.box)
        self._mode_actions.reorder_first()
        pref_group.add(mode_row)
        self._mode_row = mode_row
        content_box.append(pref_group)

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
        self._refresh_managed()

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

    def _on_mode_changed(self, row, _pspec):
        idx = row.get_selected()
        if idx < 0 or idx >= len(self.MODE_MODES):
            return
        name = self.MODE_MODES[idx]
        if name == get_var("RETRO_THEME_MODE", "dark"):
            return
        self._pending_mode = name
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _set_widget_value(self, mode: str):
        if self._mode_row is not None and mode in self.MODE_MODES:
            self._mode_row.set_selected(self.MODE_MODES.index(mode))

    def _discard_mode(self):
        live = get_var("RETRO_THEME_MODE", "dark")
        self._set_widget_value(live)
        self._pending_mode = None
        self._check_dirty()
        self._refresh_managed()

    def _reset_mode(self):
        default = get_module_default("RETRO_THEME_MODE")
        self._set_widget_value(default)
        self._pending_mode = default
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _check_dirty(self):
        any_dirty = self._pending_mode is not None
        if any_dirty != self._dirty:
            self._dirty = any_dirty
            if not any_dirty:
                self._notify_dirty()

    def _refresh_managed(self):
        if self._mode_row is None or self._mode_actions is None:
            return
        live = get_var("RETRO_THEME_MODE", "dark")
        default = get_module_default("RETRO_THEME_MODE")
        if not default:
            default = live
        effective = self._pending_mode if self._pending_mode is not None else live
        is_managed = effective != default
        is_dirty = self._pending_mode is not None
        is_saved = live != default
        self._mode_actions.update(is_managed=is_managed, is_dirty=is_dirty, is_saved=is_saved)

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self):
        self._dirty = False
        self._pending_mode = None
        self._refresh_managed()

    def flush_pending(self):
        mode = self._pending_mode
        if mode is not None:
            proc = subprocess.Popen(
                ["retro", "theme", "mode", mode],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            GLib.child_watch_add(
                proc.pid,
                lambda _pid, _status, _m=mode: self._window.show_toast(f"Theme mode set to {_m.title()}"),
            )
        self.mark_saved()

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
