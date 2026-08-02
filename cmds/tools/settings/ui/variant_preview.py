"""Mini variant preview chips for the shell Theme page's Variant dropdown.

Each variant (``srBg``, ``srPrimary``, …) is a ``StyledRect`` surface in the
shell: a gradient (linear/radial/halftone), a border, an item color for text,
and an opacity. The shell's ThemePanel shows every variant as a little chip
built from those exact values.

This module re-renders the same chip in Cairo so the settings Variant dropdown
shows what each option actually looks like. Color names resolve through
:func:`settings.ui.color_combo.color_map` (the same palette the shell uses);
gradient math mirrors ``modules/retroshell/files/modules/components/*.frag``.
"""

import math

import cairo

from gi.repository import Adw, Gdk, Gtk, Pango, PangoCairo

from settings.ui.color_combo import color_map
from settings.ui.managed_row import make_combo_row

# Fallback used when a named color is unknown (keeps previews rendering).
_FALLBACK_HEX = "#888888"


def _resolve_hex(name: str) -> str:
    """Resolve a color name (or pass through a ``#…``/``rgb…`` hex)."""
    if not name:
        return _FALLBACK_HEX
    stripped = str(name).strip()
    if stripped.startswith("#") or stripped.startswith("rgb"):
        return stripped
    return color_map().get(stripped, _FALLBACK_HEX)


def _rgba(hex_color: str):
    rgba = Gdk.RGBA()
    if not rgba.parse(_resolve_hex(hex_color)):
        rgba.parse(_FALLBACK_HEX)
    return rgba


def _rounded_rect_path(cr, x, y, w, h, radius: float):
    """Trace a rounded-rectangle path in the given bounds."""
    r = max(0.0, min(radius, min(w, h) / 2))
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def _set_source_rgba(cr, rgba, alpha: float = 1.0):
    cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha * alpha)


def _stop_color(stops, index: int, default: str) -> str:
    if 0 <= index < len(stops):
        stop = stops[index]
        if isinstance(stop, list) and stop:
            return stop[0] if isinstance(stop[0], str) else default
    return default


def _stop_pos(stops, index: int, default: float) -> float:
    if 0 <= index < len(stops):
        stop = stops[index]
        if isinstance(stop, list) and len(stop) > 1:
            try:
                return float(stop[1])
            except (TypeError, ValueError):
                return default
    return default


def _draw_linear(cr, w, h, stops, angle: float, opacity: float):
    """Draw a linear gradient mirroring linear_gradient.frag."""
    if not stops:
        return
    center_x, center_y = w / 2.0, h / 2.0
    rad = math.radians(angle)
    dir_x, dir_y = math.sin(rad), math.cos(rad)

    corners = [
        (0 - center_x, 0 - center_y),
        (w - center_x, 0 - center_y),
        (0 - center_x, h - center_y),
        (w - center_x, h - center_y),
    ]
    projs = [x * dir_x + y * dir_y for x, y in corners]
    min_p, max_p = min(projs), max(projs)
    span = max_p - min_p
    if span <= 0:
        rgba = _rgba(_stop_color(stops, 0, "surface"))
        _set_source_rgba(cr, rgba, opacity)
        cr.paint()
        return

    grad = cairo.LinearGradient(
        center_x + dir_x * min_p, center_y + dir_y * min_p,
        center_x + dir_x * max_p, center_y + dir_y * max_p,
    )
    for i, stop in enumerate(stops):
        pos = _stop_pos(stops, i, 0.0 if i == 0 else 1.0)
        rgba = _rgba(_stop_color(stops, i, "surface"))
        grad.add_color_stop_rgba(pos, rgba.red, rgba.green, rgba.blue, rgba.alpha * opacity)
    cr.set_source(grad)
    cr.paint()


def _draw_radial(cr, w, h, stops, center_x: float, center_y: float, opacity: float):
    """Draw a radial gradient mirroring radial_gradient.frag.

    The shader works in normalized [0,1] UV space with Euclidean distance
    from a configurable centre; we match that by scaling the Cairo context
    so the unit square fills the canvas exactly.
    """
    if not stops:
        return
    cr.save()
    cr.scale(w, h)
    grad = cairo.RadialGradient(
        center_x, center_y, 0.0, center_x, center_y, 1.0)
    for i in range(len(stops)):
        pos = _stop_pos(stops, i, 0.0 if i == 0 else 1.0)
        rgba = _rgba(_stop_color(stops, i, "surface"))
        grad.add_color_stop_rgba(pos, rgba.red, rgba.green, rgba.blue, rgba.alpha * opacity)
    cr.set_source(grad)
    cr.paint()
    cr.restore()


def _draw_halftone(cr, w, h, vdata, opacity: float):
    """Draw the halftone dot pattern mirroring halftone.frag.

    The shader rotates the pixel grid so the gradient runs along the
    rotated Y axis; each cell's dot radius is determined by that
    projection, producing a dissolve-like sweep of shrinking dots.
    """
    dot_rgba = _rgba(vdata.get("halftoneDotColor", "surface"))
    bg_rgba = _rgba(vdata.get("halftoneBackgroundColor", "background"))
    try:
        dot_min = float(vdata.get("halftoneDotMin", 0.0))
        dot_max = float(vdata.get("halftoneDotMax", 2.0))
        start = float(vdata.get("halftoneStart", 0.0))
        end = float(vdata.get("halftoneEnd", 1.0))
        angle = float(vdata.get("gradientAngle", 0.0))
    except (TypeError, ValueError):
        return

    cell_size = dot_max * 2.0
    if cell_size <= 0.0:
        return

    # Background fill
    _set_source_rgba(cr, bg_rgba, opacity)
    cr.paint()

    rad = math.radians(angle)
    cos_a = math.cos(rad)
    sin_a = math.sin(rad)
    cx, cy = w / 2.0, h / 2.0

    # Projection range – Y of the four corners after rotating about centre.
    corners = [(0, 0), (w, 0), (w, h), (0, h)]
    projs = [(x - cx) * sin_a + (y - cy) * cos_a for x, y in corners]
    min_p, max_p = min(projs), max(projs)
    total = max(max_p - min_p, 0.001)
    a_start = min_p + start * total
    a_end = min_p + end * total
    a_range = max(a_end - a_start, 0.001)

    # Bounding-box of rotated corners → cell-index sweep.
    rot_xs = [(x - cx) * cos_a - (y - cy) * sin_a for x, y in corners]
    rot_ys = projs  # same as above
    i0 = int(math.floor(min(rot_xs) / cell_size))
    i1 = int(math.ceil(max(rot_xs) / cell_size))
    j0 = int(math.floor(min(rot_ys) / cell_size))
    j1 = int(math.ceil(max(rot_ys) / cell_size))

    _set_source_rgba(cr, dot_rgba, opacity)

    for i in range(i0, i1 + 1):
        rcx = i * cell_size
        for j in range(j0, j1 + 1):
            rcy = j * cell_size
            proj = rcy

            if proj < a_start:
                growth = (a_start - proj) / a_range
                radius = dot_max * (1.0 + growth)
            elif proj > a_end:
                radius = 0.0
            else:
                gp = (proj - a_start) / a_range
                radius = dot_max + (dot_min - dot_max) * gp

            if radius > 0.0:
                # Inverse-rotate cell centre back to device coordinates.
                ox = cx + rcx * cos_a + rcy * sin_a
                oy = cy - rcx * sin_a + rcy * cos_a
                if -radius <= ox <= w + radius and -radius <= oy <= h + radius:
                    cr.new_sub_path()
                    cr.arc(ox, oy, radius, 0.0, 2.0 * math.pi)
                    cr.fill()


def _draw_variant_surface(cr, w, h, vdata: dict, roundness: int):
    """Render a variant's gradient + border (no label)."""
    opacity = 1.0
    try:
        opacity = float(vdata.get("opacity", 1.0))
    except (TypeError, ValueError):
        pass
    gradient_type = vdata.get("gradientType", "linear")
    stops = vdata.get("gradient") or []

    radius = max(roundness // 2, 2)
    _rounded_rect_path(cr, 0.5, 0.5, w - 1, h - 1, radius)
    cr.save()
    cr.clip()

    if gradient_type == "radial" and stops:
        try:
            cx = float(vdata.get("gradientCenterX", 0.5))
            cy = float(vdata.get("gradientCenterY", 0.5))
        except (TypeError, ValueError):
            cx, cy = 0.5, 0.5
        _draw_radial(cr, w, h, stops, cx, cy, opacity)
    elif gradient_type == "halftone":
        _draw_halftone(cr, w, h, vdata, opacity)
    elif gradient_type == "linear" and stops:
        try:
            angle = float(vdata.get("gradientAngle", 0.0))
        except (TypeError, ValueError):
            angle = 0.0
        _draw_linear(cr, w, h, stops, angle, opacity)
    else:
        rgba = _rgba(_stop_color(stops, 0, "surface"))
        _set_source_rgba(cr, rgba, opacity)
        cr.paint()
    cr.restore()

    # Border (mirrors StyledRect's border overlay).
    border = vdata.get("border")
    if isinstance(border, list) and border:
        b_color = border[0] if border and isinstance(border[0], str) else "surfaceBright"
        try:
            b_width = float(border[1]) if len(border) > 1 else 0.0
        except (TypeError, ValueError):
            b_width = 0.0
        if b_width > 0:
            b_rgba = _rgba(b_color)
            _rounded_rect_path(cr, 0.5, 0.5, w - 1, h - 1, radius)
            _set_source_rgba(cr, b_rgba)
            cr.set_line_width(b_width)
            cr.stroke()


def _draw_variant_chip(cr, w, h, vdata: dict, label: str, roundness: int):
    """Render one variant chip: gradient + border + item-colored label."""
    _draw_variant_surface(cr, w, h, vdata, roundness)
    _draw_label(cr, w, h, label, vdata.get("itemColor", "overBackground"))


def _draw_label(cr, w, h, label: str, item_color: str):
    rgba = _rgba(item_color)
    layout = PangoCairo.create_layout(cr)
    layout.set_text(label, -1)
    font = Pango.FontDescription()
    font.set_family("Sans")
    font.set_size(int(10 * Pango.SCALE))
    font.set_weight(Pango.Weight.BOLD)
    layout.set_font_description(font)
    _set_source_rgba(cr, rgba)
    ink, logical = layout.get_pixel_extents()
    if logical.width > w - 8:
        layout.set_ellipsize(Pango.EllipsizeMode.END)
        layout.set_width(int((w - 8) * Pango.SCALE))
        ink, logical = layout.get_pixel_extents()
    cr.move_to((w - logical.width) / 2.0, (h - logical.height) / 2.0)
    PangoCairo.show_layout(cr, layout)


def make_variant_preview_row(
    page,
    title: str,
    ids: list[str],
    labels: list[str],
    selected: int = 0,
    subtitle: str = "",
) -> Adw.ComboRow:
    """Build the Variant combo row with per-option preview chips."""
    factory = _make_variant_item_factory(page, ids, labels)
    row = make_combo_row(title, model=Gtk.StringList.new(labels),
                         factory=factory, selected=selected, subtitle=subtitle)
    return row


def _make_variant_item_factory(page, ids: list[str], labels: list[str]) -> Gtk.SignalListItemFactory:
    factory = Gtk.SignalListItemFactory()

    def _setup(_factory, item):
        chip = Gtk.DrawingArea()
        chip.set_size_request(120, 34)
        chip.set_valign(Gtk.Align.CENTER)
        chip.set_hexpand(True)
        chip.set_draw_func(_chip_draw)
        item.set_child(chip)
        item._rl_chip = chip

    def _bind(_factory, item):
        # The collapsed combo-row renders a single-item ListView whose item's
        # position is always 0, so bind by the selected label string instead.
        label = item.get_item().get_string()
        try:
            idx = labels.index(label)
        except ValueError:
            idx = item.get_position()
        if not (0 <= idx < len(ids)):
            idx = 0
        chip = item._rl_chip
        chip._rl_page = page
        chip._rl_id = ids[idx]
        chip._rl_label = labels[idx] if 0 <= idx < len(labels) else ""
        chip._rl_roundness = int(page._data.get("roundness", 16) or 16)
        chip.queue_draw()

    factory.connect("setup", _setup)
    factory.connect("bind", _bind)
    return factory


def _chip_draw(widget: Gtk.DrawingArea, cr, w, h):
    page = getattr(widget, "_rl_page", None)
    vdata = page._data.get(getattr(widget, "_rl_id", ""), {}) if page is not None else {}
    label = getattr(widget, "_rl_label", "")
    roundness = getattr(widget, "_rl_roundness", 16)
    _draw_variant_chip(cr, w, h, vdata, label, roundness)


# ── Large live preview ─────────────────────────────────────────────────

def make_variant_preview(page, vk: str, height: int = 140) -> Gtk.DrawingArea:
    """A full-width live preview of one variant surface.

    Redrawn on every change to ``page._data[vk]`` — the Theme page calls
    ``queue_draw()`` on the returned widget from its dirty-change plumbing.
    """
    preview = Gtk.DrawingArea()
    preview.set_size_request(-1, height)
    preview.set_hexpand(True)
    preview.set_draw_func(lambda w, cr, ww, hh: _draw_variant_preview(cr, ww, hh, page, vk))
    return preview


def _draw_variant_preview(cr, w, h, page, vk: str):
    vdata = page._data.get(vk, {}) or {}
    roundness = int(page._data.get("roundness", 16) or 16)
    _draw_variant_surface(cr, w, h, vdata, roundness)

    label = vdata.get("label", vk)
    item_color = vdata.get("itemColor", "overBackground")
    _draw_preview_label(cr, w, h, label, _preview_subtitle(vdata), item_color)


def _preview_subtitle(vdata: dict) -> str:
    gradient_type = vdata.get("gradientType", "linear")
    stops = vdata.get("gradient") or []
    parts = [str(gradient_type).capitalize()]
    if gradient_type == "halftone":
        try:
            dmin = float(vdata.get("halftoneDotMin", 0))
            dmax = float(vdata.get("halftoneDotMax", 2))
        except (TypeError, ValueError):
            dmin, dmax = 0, 2
        parts.append(f"dots {dmin:.0f}–{dmax:.0f}")
    elif gradient_type in ("linear", "radial") and stops:
        count = len(stops)
        parts.append(f"{count} stop{'s' if count != 1 else ''}")
    return " · ".join(parts)


def _make_preview_layout(cr, text: str, size_px: int, *, bold: bool, max_w: float):
    layout = PangoCairo.create_layout(cr)
    layout.set_text(text, -1)
    font = Pango.FontDescription()
    font.set_family("Sans")
    font.set_size(int(size_px * Pango.SCALE))
    if bold:
        font.set_weight(Pango.Weight.BOLD)
    layout.set_font_description(font)
    if max_w is not None:
        layout.set_ellipsize(Pango.EllipsizeMode.END)
        layout.set_width(int(max_w * Pango.SCALE))
    return layout


def _show_layout(cr, layout, x, y, rgba, *, shadow: bool):
    if shadow:
        sh = Gdk.RGBA(red=0.0, green=0.0, blue=0.0, alpha=0.4)
        cr.move_to(x + 1.5, y + 1.5)
        _set_source_rgba(cr, sh)
        PangoCairo.show_layout(cr, layout)
    cr.move_to(x, y)
    _set_source_rgba(cr, rgba)
    PangoCairo.show_layout(cr, layout)


def _draw_preview_label(cr, w, h, label: str, subtitle: str, item_color: str):
    rgba = _rgba(item_color)
    max_w = w - 32.0
    label_layout = _make_preview_layout(cr, label, 22, bold=True, max_w=max_w)
    sub_layout = _make_preview_layout(cr, subtitle, 12, bold=False, max_w=max_w)
    _ink, label_logical = label_layout.get_pixel_extents()
    _ink, sub_logical = sub_layout.get_pixel_extents()

    gap = 6.0
    block_h = label_logical.height + gap + sub_logical.height
    y = (h - block_h) / 2.0
    _show_layout(cr, label_layout,
                 (w - label_logical.width) / 2.0, y, rgba, shadow=True)
    _show_layout(cr, sub_layout,
                 (w - sub_logical.width) / 2.0, y + label_logical.height + gap, rgba,
                 shadow=False)
