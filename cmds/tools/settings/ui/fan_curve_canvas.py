"""Interactive piecewise-linear fan curve canvas with draggable breakpoints."""

from gi.repository import Gtk

from settings.ui import ACCENT_RGB, ACTIVE_RGB, get_cursor_grab, get_cursor_none

HANDLE_RADIUS = 7
CANVAS_PAD = 40
TEMP_MIN = 20
TEMP_MAX = 100
PCT_MIN = 0
PCT_MAX = 100


class FanCurveCanvas(Gtk.DrawingArea):
    """Interactive fan curve canvas: Temperature (°C) vs Fan Speed (%).

    Displays a piecewise-linear curve with draggable breakpoint handles.
    """

    def __init__(self, on_change=None, on_drag_end=None):
        super().__init__()
        self._points: list[tuple[int, int]] = [(30, 30), (50, 50), (70, 75), (85, 100)]
        self._dragging: int | None = None
        self._on_change = on_change
        self._drag_end_cb = on_drag_end

        self._drag_origin_x: float = 0.0
        self._drag_origin_y: float = 0.0

        self.set_content_width(300)
        self.set_content_height(300)
        self.set_draw_func(self._draw)

        drag = Gtk.GestureDrag.new()
        drag.connect("drag-begin", self._on_drag_begin)
        drag.connect("drag-update", self._on_drag_update)
        drag.connect("drag-end", self._on_drag_end)
        self.add_controller(drag)

        motion = Gtk.EventControllerMotion.new()
        motion.connect("motion", self._on_motion)
        self.add_controller(motion)

    @property
    def points(self) -> list[tuple[int, int]]:
        return list(self._points)

    def set_points(self, points: list[tuple[int, int]]) -> None:
        self._points = sorted(points, key=lambda p: p[0])
        self.queue_draw()

    def _temp_to_x(self, temp: int, w: int) -> float:
        return CANVAS_PAD + (temp - TEMP_MIN) / (TEMP_MAX - TEMP_MIN) * (w - 2 * CANVAS_PAD)

    def _pct_to_y(self, pct: int, h: int) -> float:
        return h - CANVAS_PAD - (pct - PCT_MIN) / (PCT_MAX - PCT_MIN) * (h - 2 * CANVAS_PAD)

    def _x_to_temp(self, x: float, w: int) -> int:
        t = TEMP_MIN + (x - CANVAS_PAD) / (w - 2 * CANVAS_PAD) * (TEMP_MAX - TEMP_MIN)
        return max(TEMP_MIN, min(TEMP_MAX, int(round(t))))

    def _y_to_pct(self, y: float, h: int) -> int:
        p = PCT_MIN + (h - CANVAS_PAD - y) / (h - 2 * CANVAS_PAD) * (PCT_MAX - PCT_MIN)
        return max(PCT_MIN, min(PCT_MAX, int(round(p))))

    def _draw(self, _da, cr, w, h) -> None:
        if w < 50 or h < 50:
            return

        fg = self.get_color()
        accent = ACCENT_RGB
        active = ACTIVE_RGB

        cr.set_line_width(1.0)

        # Grid
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.12)
        for t in range(TEMP_MIN, TEMP_MAX + 1, 10):
            x = self._temp_to_x(t, w)
            cr.move_to(x, CANVAS_PAD)
            cr.line_to(x, h - CANVAS_PAD)
            cr.stroke()
        for p in range(PCT_MIN, PCT_MAX + 1, 25):
            y = self._pct_to_y(p, h)
            cr.move_to(CANVAS_PAD, y)
            cr.line_to(w - CANVAS_PAD, y)
            cr.stroke()

        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.25)
        cr.set_line_width(1)
        cr.rectangle(CANVAS_PAD, CANVAS_PAD, w - 2 * CANVAS_PAD, h - 2 * CANVAS_PAD)
        cr.stroke()

        # Axis labels
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.5)
        cr.set_font_size(10)
        for t in range(TEMP_MIN, TEMP_MAX + 1, 20):
            x = self._temp_to_x(t, w)
            cr.move_to(x - 5, h - CANVAS_PAD + 16)
            cr.show_text(f"{t}")
        for p in range(PCT_MIN, PCT_MAX + 1, 25):
            y = self._pct_to_y(p, h)
            cr.move_to(4, y + 4)
            cr.show_text(f"{p}")

        # Axis titles
        cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.35)
        cr.set_font_size(11)
        cr.move_to(w / 2 - 20, h - 4)
        cr.show_text("Temp °C")
        cr.save()
        cr.move_to(4, h / 2 + 15)
        cr.rotate(-1.5708)
        cr.show_text("Fan %")
        cr.restore()

        if len(self._points) < 2:
            return

        # Curve fill
        cr.set_source_rgba(*accent, 0.08)
        first_x, first_y = self._temp_to_x(self._points[0][0], w), self._pct_to_y(self._points[0][1], h)
        cr.move_to(first_x, h - CANVAS_PAD)
        cr.line_to(first_x, first_y)
        for temp, pct in self._points[1:]:
            cr.line_to(self._temp_to_x(temp, w), self._pct_to_y(pct, h))
        last_x = self._temp_to_x(self._points[-1][0], w)
        cr.line_to(last_x, h - CANVAS_PAD)
        cr.close_path()
        cr.fill()

        # Curve line
        cr.set_line_width(2.5)
        cr.set_source_rgba(*accent, 0.9)
        cr.move_to(first_x, first_y)
        for temp, pct in self._points[1:]:
            cr.line_to(self._temp_to_x(temp, w), self._pct_to_y(pct, h))
        cr.stroke()

        # Handles
        for i, (temp, pct) in enumerate(self._points):
            cx = self._temp_to_x(temp, w)
            cy = self._pct_to_y(pct, h)
            is_hover = self._dragging == i
            r = HANDLE_RADIUS + (2 if is_hover else 0)

            cr.set_source_rgba(0, 0, 0, 0.3)
            cr.arc(cx, cy, r + 2, 0, 6.2832)
            cr.fill()

            cr.set_source_rgba(*active if is_hover else accent, 1.0)
            cr.arc(cx, cy, r, 0, 6.2832)
            cr.fill()

            cr.set_source_rgba(1, 1, 1, 0.9)
            cr.set_font_size(9)
            cr.move_to(cx - 5, cy - r - 4)
            cr.show_text(f"{temp}°")

    def _hit_test(self, mx: float, my: float, w: int, h: int) -> int | None:
        for i, (temp, pct) in enumerate(self._points):
            cx = self._temp_to_x(temp, w)
            cy = self._pct_to_y(pct, h)
            if (mx - cx) ** 2 + (my - cy) ** 2 < (HANDLE_RADIUS + 6) ** 2:
                return i
        return None

    def _on_drag_begin(self, gesture, x, y) -> None:
        w, h = self.get_width(), self.get_height()
        idx = self._hit_test(x, y, w, h)
        if idx is not None:
            self._dragging = idx
            self._drag_origin_x = x
            self._drag_origin_y = y
            gesture.set_state(Gtk.EventSequenceState.CLAIMED)
            self.set_cursor(*get_cursor_grab())
        else:
            gesture.set_state(Gtk.EventSequenceState.DENIED)

    def _on_drag_update(self, gesture, offset_x, offset_y) -> None:
        if self._dragging is None:
            return
        w, h = self.get_width(), self.get_height()
        abs_x = self._drag_origin_x + offset_x
        abs_y = self._drag_origin_y + offset_y
        temp = self._x_to_temp(abs_x, w)
        pct = self._y_to_pct(abs_y, h)

        old_temp, _ = self._points[self._dragging]
        self._points[self._dragging] = (temp, pct)
        self._points.sort(key=lambda p: p[0])
        new_idx = next(i for i, p in enumerate(self._points) if p == (temp, pct))
        self._dragging = new_idx

        self.queue_draw()
        if self._on_change:
            self._on_change(self.points)

    def _on_drag_end(self, _gesture, _x, _y) -> None:
        self._dragging = None
        self.set_cursor(*get_cursor_none())
        if self._drag_end_cb:
            self._drag_end_cb(self.points)

    def _on_motion(self, _ctrl, x, y) -> None:
        if self._dragging is not None:
            return
        w, h = self.get_width(), self.get_height()
        idx = self._hit_test(x, y, w, h)
        if idx is not None:
            self.set_cursor(*get_cursor_grab())
        else:
            self.set_cursor(*get_cursor_none())
