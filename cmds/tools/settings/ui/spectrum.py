"""Audio spectrum visualizer — Cairo bar graph with smooth animation."""

import math
import cairo
from gi.repository import GLib, Gtk


class AudioSpectrumWidget(Gtk.DrawingArea):
    def __init__(self, num_bars: int = 16):
        super().__init__()
        self._num_bars = num_bars
        self._bars = [0.0] * num_bars
        self._target = [0.0] * num_bars
        self.set_hexpand(True)
        self.set_size_request(-1, 90)
        self.set_draw_func(self._draw)
        self._tick_source = GLib.timeout_add(16, self._tick)

    def set_bars(self, bars: list[float]) -> None:
        self._target = bars[:]

    def _tick(self) -> bool:
        changed = False
        for i in range(self._num_bars):
            diff = self._target[i] - self._bars[i]
            if abs(diff) > 0.001:
                if diff > 0:
                    self._bars[i] += diff * 0.85
                else:
                    self._bars[i] += diff * 0.24
                changed = True
            else:
                self._bars[i] = self._target[i]
        if changed:
            self.queue_draw()
        return True

    def _draw(self, _area, cr, width, height):
        if width < 10 or height < 10:
            return
        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        _, accent = self.get_style_context().lookup_color("accent_bg_color")
        r, g, b = (accent.red, accent.green, accent.blue)

        n = self._num_bars
        pad_x = 8
        pad_y_top = 4
        pad_y_bot = 4
        area_w = width - 2 * pad_x
        area_h = height - pad_y_top - pad_y_bot
        bar_w = area_w / n
        gap = max(3, bar_w * 0.18)
        actual_bar_w = bar_w - gap

        for i in range(n):
            bar_h = max(1, self._bars[i] * area_h)
            x = pad_x + i * bar_w
            y = pad_y_top + area_h - bar_h

            cr.set_source_rgba(r, g, b, 0.85)

            dynamic_r = min(3, actual_bar_w / 2, bar_h / 2)
            if bar_h <= 2:
                cr.rectangle(x, y, actual_bar_w, bar_h)
            else:
                self._rounded_rect(cr, x, y, actual_bar_w, bar_h, dynamic_r)
            cr.fill()

    @staticmethod
    def _rounded_rect(cr, x, y, w, h, r):
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def stop(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None

    def __del__(self):
        self.stop()
