"""Named-color picker row for the shell's ``sr*`` color palette.

The shell resolves colors (shadow color, item color, border color, …) by
name against a user-managed palette at
``~/.config/retro/themes/shell-colors.json`` (falling back to the hex
values hardcoded in ``modules/theme/Colors.qml``). The row offers the
available names with a live swatch preview resolved from the same source,
plus a leading "Custom…" entry that lets the user pick a raw color (stored
as ``#rrggbb`` / ``rgb(...)`` — the shell's ``resolveColor`` passes those
through unchanged). When "Custom…" is selected, a native color-picker
button appears alongside the dropdown so the custom color can always be
edited directly.

The resolution map is a module-level cache refreshed on first use — the
palette file is user-managed but stable for a session, matching the shell's
behavior of reloading ``colors.json`` on change.
"""

from collections.abc import Callable
import json
from pathlib import Path

from gi.repository import Adw, Gdk, Gtk

from settings.ui.managed_row import make_combo_row

# Sentinel id and label for the "Custom…" entry that precedes the named
# palette. When selected, the value stored in the config is a raw hex string
# (``#rrggbb`` / ``rgb(...)``) instead of a palette name — the shell's
# ``resolveColor`` passes those through unchanged.
CUSTOM_ID = "__custom__"
CUSTOM_LABEL = "Custom…"


def is_custom_value(value) -> bool:
    """True when *value* is a raw hex/``rgb()`` color (not a palette name)."""
    stripped = str(value).strip() if value is not None else ""
    return stripped.startswith("#") or stripped.startswith("rgb")


# Mirrors ``Colors.availableColorNames`` (excludes internal/source colors).
COLOR_NAMES = [
    "background", "surface", "surfaceBright", "surfaceContainer",
    "surfaceContainerHigh", "surfaceContainerHighest", "surfaceContainerLow",
    "surfaceContainerLowest", "surfaceDim", "surfaceTint", "surfaceVariant",
    "primary", "primaryContainer", "primaryFixed", "primaryFixedDim",
    "secondary", "secondaryContainer", "secondaryFixed", "secondaryFixedDim",
    "tertiary", "tertiaryContainer", "tertiaryFixed", "tertiaryFixedDim",
    "error", "errorContainer",
    "overBackground", "overSurface", "overSurfaceVariant",
    "overPrimary", "overPrimaryContainer", "overPrimaryFixed",
    "overPrimaryFixedVariant",
    "overSecondary", "overSecondaryContainer", "overSecondaryFixed",
    "overSecondaryFixedVariant",
    "overTertiary", "overTertiaryContainer", "overTertiaryFixed",
    "overTertiaryFixedVariant",
    "overError", "overErrorContainer",
    "outline", "outlineVariant",
    "inversePrimary", "inverseSurface", "inverseOnSurface",
    "shadow", "scrim",
    "blue", "blueContainer", "overBlue", "overBlueContainer", "lightBlue",
    "cyan", "cyanContainer", "overCyan", "overCyanContainer", "lightCyan",
    "green", "greenContainer", "overGreen", "overGreenContainer", "lightGreen",
    "magenta", "magentaContainer", "overMagenta", "overMagentaContainer",
    "lightMagenta",
    "red", "redContainer", "overRed", "overRedContainer", "lightRed",
    "yellow", "yellowContainer", "overYellow", "overYellowContainer",
    "lightYellow",
    "white", "whiteContainer", "overWhite", "overWhiteContainer",
]

# Fallback hexes mirroring ``Colors.qml``'s JsonAdapter defaults (used when
# ``shell-colors.json`` is missing or lacks a name).
_FALLBACK_HEXES = {
    "background": "#1a1111",
    "blue": "#cebdfe", "blueContainer": "#4c3e76",
    "cyan": "#84d5c4", "cyanContainer": "#005045",
    "error": "#ffb4ab", "errorContainer": "#93000a",
    "green": "#b7d085", "greenContainer": "#3a4d10",
    "inverseOnSurface": "#382e2d", "inversePrimary": "#904a46",
    "inverseSurface": "#f1dedd",
    "lightBlue": "#cebdfe", "lightCyan": "#84d5c4", "lightGreen": "#b7d085",
    "lightMagenta": "#fcb0d5", "lightRed": "#ffb4ab", "lightYellow": "#dec56e",
    "magenta": "#fcb0d5", "magentaContainer": "#6c3353",
    "overBackground": "#f1dedd",
    "overBlue": "#35275e", "overBlueContainer": "#e8ddff",
    "overCyan": "#00382f", "overCyanContainer": "#9ff2e0",
    "overError": "#690005", "overErrorContainer": "#ffdad6",
    "overGreen": "#253600", "overGreenContainer": "#d3ec9e",
    "overMagenta": "#521d3c", "overMagentaContainer": "#ffd8e8",
    "overPrimary": "#571d1c", "overPrimaryContainer": "#ffdad7",
    "overPrimaryFixed": "#3b0809", "overPrimaryFixedVariant": "#733331",
    "overRed": "#561e19", "overRedContainer": "#ffdad6",
    "overSecondary": "#442928", "overSecondaryContainer": "#ffdad7",
    "overSecondaryFixed": "#2c1514", "overSecondaryFixedVariant": "#5d3f3d",
    "overSurface": "#f1dedd", "overSurfaceVariant": "#d8c2c0",
    "overTertiary": "#402d04", "overTertiaryContainer": "#ffdea7",
    "overTertiaryFixed": "#271900", "overTertiaryFixedVariant": "#594319",
    "overWhite": "#00363d", "overWhiteContainer": "#9eeffd",
    "overYellow": "#3b2f00", "overYellowContainer": "#fce186",
    "outline": "#a08c8b", "outlineVariant": "#534342",
    "primary": "#ffb3ae", "primaryContainer": "#733331",
    "primaryFixed": "#ffdad7", "primaryFixedDim": "#ffb3ae",
    "red": "#ffb4ab", "redContainer": "#73332e",
    "scrim": "#000000",
    "secondary": "#e7bdb9", "secondaryContainer": "#5d3f3d",
    "secondaryFixed": "#ffdad7", "secondaryFixedDim": "#e7bdb9",
    "shadow": "#000000",
    "surface": "#1a1111", "surfaceBright": "#423736",
    "surfaceContainer": "#271d1d", "surfaceContainerHigh": "#322827",
    "surfaceContainerHighest": "#3d3231", "surfaceContainerLow": "#231919",
    "surfaceContainerLowest": "#140c0c", "surfaceDim": "#1a1111",
    "surfaceTint": "#ffb3ae", "surfaceVariant": "#534342",
    "tertiary": "#e2c28c", "tertiaryContainer": "#594319",
    "tertiaryFixed": "#ffdea7", "tertiaryFixedDim": "#e2c28c",
    "white": "#82d3e0", "whiteContainer": "#004f58",
    "yellow": "#dec56e", "yellowContainer": "#554500",
}

_CACHE: dict | None = None


def _resolve_hex(name: str, palette: dict | None) -> str:
    if palette and name in palette:
        return str(palette[name])
    return _FALLBACK_HEXES.get(name, "#888888")


def color_map() -> dict[str, str]:
    """Return ``{name: "#rrggbb"}`` for every available color name.

    Prefers ``~/.config/retro/themes/shell-colors.json``, falling back to
    the hexes from ``Colors.qml``. ``surface``/``surfaceBright`` are tints
    the shell computes at runtime, so the palette file or fallback hex is
    used as an approximation.
    """
    global _CACHE
    if _CACHE is not None:
        return _CACHE
    palette: dict = {}
    path = Path.home() / ".config" / "retro" / "themes" / "shell-colors.json"
    try:
        data = json.loads(path.read_text())
        if isinstance(data, dict):
            palette = data
    except (json.JSONDecodeError, OSError):
        palette = {}
    _CACHE = {name: _resolve_hex(name, palette) for name in COLOR_NAMES}
    return _CACHE


def _draw_swatch(cr, width, height, rgba):
    radius = min(width, height) / 2.0 - 1.0
    cr.new_sub_path()
    cr.arc(width / 2.0, height / 2.0, radius, 0.0, 2.0 * 3.141592653589793)
    cr.close_path()
    cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha)
    cr.fill()
    cr.set_source_rgba(0.5, 0.5, 0.5, 0.4)
    cr.set_line_width(1.0)
    cr.stroke()


def _draw_swatch_hex(cr, width, height, hex_color: str) -> None:
    _draw_swatch(cr, width, height, _parse_rgba(hex_color))


def _parse_rgba(hex_color: str) -> Gdk.RGBA:
    rgba = Gdk.RGBA()
    if not rgba.parse(hex_color):
        rgba.parse("#888888")
    return rgba


def _rgba_to_hex(rgba: Gdk.RGBA) -> str:
    """Format a ``Gdk.RGBA`` as ``#rrggbb`` (alpha dropped; opacity is separate)."""
    r = max(0, min(255, round(rgba.red * 255)))
    g = max(0, min(255, round(rgba.green * 255)))
    b = max(0, min(255, round(rgba.blue * 255)))
    return f"#{r:02x}{g:02x}{b:02x}"


def _make_color_item_factory(state: dict) -> Gtk.SignalListItemFactory:
    """Factory drawing each dropdown option as a circle swatch + name.

    The "Custom…" option's swatch renders ``state["custom"]`` (the live custom
    hex) so the page can update it after a color-dialog accept by calling
    :func:`set_custom_color`. Every created swatch is recorded in
    ``state["swatches"]`` so it can be redrawn.
    """
    factory = Gtk.SignalListItemFactory()

    def _setup(_factory, item):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_start(4)
        swatch = Gtk.DrawingArea()
        swatch.set_size_request(18, 18)
        swatch.set_valign(Gtk.Align.CENTER)
        swatch.set_draw_func(
            lambda w, cr, ww, hh: _draw_item_swatch(w, cr, ww, hh, state))
        label = Gtk.Label(xalign=0.0, hexpand=True)
        box.append(swatch)
        box.append(label)
        item.set_child(box)
        item._rl_swatch = swatch
        item._rl_label = label
        state["swatches"].append(swatch)

    def _bind(_factory, item):
        name = item.get_item().get_string()
        item._rl_label.set_text(name)
        swatch = item._rl_swatch
        swatch._rl_is_custom = (name == CUSTOM_LABEL)
        swatch._rl_label_name = name
        swatch.queue_draw()

    factory.connect("setup", _setup)
    factory.connect("bind", _bind)
    return factory


def _draw_item_swatch(widget: Gtk.DrawingArea, cr, w, h, state: dict) -> None:
    if getattr(widget, "_rl_is_custom", False):
        hex_color = state.get("custom") or "#888888"
    else:
        name = getattr(widget, "_rl_label_name", "")
        hex_color = color_map().get(name, "#888888")
    _draw_swatch_hex(cr, w, h, hex_color)


def make_color_combo_row(
    title: str,
    current: str,
    *,
    subtitle: str = "",
    on_change: Callable[[str], None] | None = None,
) -> tuple[Adw.ComboRow, list[str], dict]:
    """Combo row over the named palette plus a leading "Custom…" entry.

    When the "Custom…" entry is selected a native color-picker button
    appears alongside the dropdown so the custom color can be picked
    directly. The row emits *on_change(hex)* for every committed custom
    color; the caller is responsible for persisting it and refreshing its
    ``ManagedRow``.

    Returns ``(row, ids, state)`` where ``ids`` is
    ``["__custom__", *COLOR_NAMES]`` (index 0 is the custom entry) and
    ``state`` carries the live custom hex (``state["custom"]``), the row's
    swatch widgets (``state["swatches"]``) and the picker button
    (``state["picker"]``).

    Use :func:`get_color` / :func:`set_color` to read/write the row's value: a
    palette name for named selections, the raw custom hex for "Custom…".
    """
    ids = [CUSTOM_ID, *COLOR_NAMES]
    labels = [CUSTOM_LABEL, *COLOR_NAMES]
    custom_hex = current if is_custom_value(current) else color_map().get(str(current), "#888888")
    state: dict = {"custom": custom_hex or "#888888", "swatches": []}
    try:
        selected = ids.index(current)
    except ValueError:
        selected = 0
    row = make_combo_row(title, model=Gtk.StringList.new(labels), selected=selected,
                          subtitle=subtitle, factory=_make_color_item_factory(state))

    picker = Gtk.ColorDialogButton()
    picker.set_dialog(Gtk.ColorDialog())
    picker.set_valign(Gtk.Align.CENTER)
    picker.set_tooltip_text("Pick a color")
    picker.set_rgba(_parse_rgba(state["custom"]))
    row.add_suffix(picker)
    state["picker"] = picker

    def _commit(hex_color: str) -> None:
        set_custom_color(state, hex_color)
        if on_change is not None:
            on_change(hex_color)

    def _refresh_controls() -> None:
        is_custom = row.get_selected() == 0
        picker.set_visible(is_custom)

    def _on_picker_rgba(*_args) -> None:
        hex_color = _rgba_to_hex(picker.get_rgba())
        if hex_color == state["custom"]:
            return
        _commit(hex_color)

    row.connect("notify::selected", lambda *_a: _refresh_controls())
    picker.connect("notify::rgba", _on_picker_rgba)
    _refresh_controls()
    return row, ids, state


def get_color(row: Adw.ComboRow, ids: list[str], current: str) -> str:
    """Return the row's current value as a palette name or raw hex.

    When the "Custom…" entry is selected the live *current* value is returned;
    otherwise the selected palette name. ``ids`` is the list returned by
    :func:`make_color_combo_row`.
    """
    idx = row.get_selected()
    if 0 <= idx < len(ids) and ids[idx] == CUSTOM_ID:
        return current
    return ids[idx] if 0 <= idx < len(ids) else ids[0]


def set_color(row: Adw.ComboRow, ids: list[str], state: dict, value: str) -> None:
    """Position the row for *value*.

    A raw hex selects the "Custom…" entry and updates ``state["custom"]``; a
    palette name selects its entry. Unknown values fall back to "Custom…".
    """
    if is_custom_value(value):
        set_custom_color(state, value)
        row.set_selected(0)
        return
    try:
        row.set_selected(ids.index(value))
    except ValueError:
        row.set_selected(0)


def set_custom_color(state: dict, hex_color: str) -> None:
    """Update the custom color and sync every widget (swatches, picker
    button). Does not emit the caller's change callback."""
    state["custom"] = hex_color
    for swatch in state["swatches"]:
        swatch.queue_draw()
    picker = state.get("picker")
    if picker is not None:
        picker.set_rgba(_parse_rgba(hex_color))
