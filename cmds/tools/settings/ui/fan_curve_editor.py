"""Fan curve editor dialog — edit piecewise-linear temperature→fan% curves."""

from gi.repository import Adw, Gtk

from settings.data.fan_curve_data import (
    curve_from_str, curve_to_str, get_fan_curve_store,
)
from settings.ui import make_page_layout
from settings.ui.fan_curve_canvas import FanCurveCanvas


class FanCurveEditorDialog:
    """Dialog for editing a fan curve with a draggable canvas."""

    def __init__(self, parent, initial_curve: str = "", on_curve_saved=None,
                 fan_label: str = "", get_fan_curve_usage=None):
        self._on_curve_saved = on_curve_saved
        self._fan_label = fan_label
        self._get_usage = get_fan_curve_usage
        self._store = get_fan_curve_store()

        self._dialog = Adw.Dialog()
        self._dialog.set_title(f"Edit Fan Curve — {fan_label}" if fan_label else "Edit Fan Curve")
        self._dialog.set_content_width(420)
        self._dialog.set_content_height(520)
        self._dialog.set_follows_content_size(True)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_top(12)
        content.set_margin_bottom(16)
        content.set_margin_start(12)
        content.set_margin_end(12)

        # Curve name / preset row
        name_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        name_lbl = Gtk.Label(label="Curve", halign=Gtk.Align.START)
        name_lbl.add_css_class("dim-label")
        name_row.append(name_lbl)
        self._name_entry = Gtk.Entry(hexpand=True, placeholder_text="Curve name")
        self._name_entry.set_text(initial_curve if initial_curve in self._store.get_all_curve_names() else "")
        name_row.append(self._name_entry)
        content.append(name_row)

        # Preset buttons
        preset_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        for pname in ["quiet", "balanced", "performance"]:
            btn = Gtk.Button(label=pname.capitalize())
            btn.add_css_class("flat")
            btn.connect("clicked", self._on_preset, pname)
            preset_box.append(btn)
        content.append(preset_box)

        # Canvas
        self._canvas = FanCurveCanvas(on_change=self._on_curve_changed)
        self._canvas.set_hexpand(True)
        points = curve_from_str(initial_curve) if initial_curve else []
        if not points:
            points = self._store.get_curve_points("balanced")
        self._canvas.set_points(points)
        self._canvas.set_size_request(-1, 280)
        content.append(self._canvas)

        # Spin buttons for selected point
        point_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        t_lbl = Gtk.Label(label="Temp °C")
        t_lbl.add_css_class("dim-label")
        point_box.append(t_lbl)
        self._temp_spin = Gtk.SpinButton.new_with_range(20, 100, 1)
        self._temp_spin.connect("value-changed", self._on_spin_changed)
        point_box.append(self._temp_spin)
        p_lbl = Gtk.Label(label="Fan %")
        p_lbl.add_css_class("dim-label")
        point_box.append(p_lbl)
        self._pct_spin = Gtk.SpinButton.new_with_range(0, 100, 1)
        self._pct_spin.connect("value-changed", self._on_spin_changed)
        point_box.append(self._pct_spin)
        content.append(point_box)

        # Action bar
        action_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        action_box.set_halign(Gtk.Align.END)

        add_btn = Gtk.Button(label="Add Point")
        add_btn.add_css_class("flat")
        add_btn.connect("clicked", self._on_add_point)
        action_box.append(add_btn)

        remove_btn = Gtk.Button(label="Remove Point")
        remove_btn.add_css_class("flat")
        remove_btn.add_css_class("destructive-action")
        remove_btn.connect("clicked", self._on_remove_point)
        action_box.append(remove_btn)

        save_btn = Gtk.Button(label="Save")
        save_btn.add_css_class("suggested-action")
        save_btn.connect("clicked", self._on_save)
        action_box.append(save_btn)

        content.append(action_box)
        toolbar.set_content(content)
        self._dialog.set_child(toolbar)
        self._dialog.present(parent)

    def _on_preset(self, _btn, name: str) -> None:
        pts = self._store.get_curve_points(name)
        if pts:
            self._canvas.set_points(pts)
            self._name_entry.set_text(name)
            self._on_curve_changed(self._canvas.points)

    def _on_curve_changed(self, points) -> None:
        if points:
            self._temp_spin.set_value(points[-1][0])
            self._pct_spin.set_value(points[-1][1])

    def _on_spin_changed(self, _spin) -> None:
        points = self._canvas.points
        if not points:
            return
        t = int(self._temp_spin.get_value())
        p = int(self._pct_spin.get_value())
        points[-1] = (t, p)
        self._canvas.set_points(points)

    def _on_add_point(self, _btn) -> None:
        points = self._canvas.points
        last_t = points[-1][0] if points else 30
        new_t = min(last_t + 10, 100)
        points.append((new_t, 50))
        points.sort(key=lambda x: x[0])
        self._canvas.set_points(points)

    def _on_remove_point(self, _btn) -> None:
        points = self._canvas.points
        if len(points) > 2:
            points.pop()
            self._canvas.set_points(points)

    def _on_save(self, _btn) -> None:
        name = self._name_entry.get_text().strip()
        if not name:
            return
        points = self._canvas.points
        if not points:
            return
        self._store.save_user_curve(name, points)
        if self._on_curve_saved:
            self._on_curve_saved(name)
        self._dialog.close()
