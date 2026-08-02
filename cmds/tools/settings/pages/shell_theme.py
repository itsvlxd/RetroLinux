"""Shell Theme page — configure the Retro Shell theme (``theme.json``).

Mirrors the General, Shadow, and Colors sections of the in-shell
``ThemePanel.qml`` (and the per-variant ``VariantEditor``). Values are
written to ``~/.config/retro/shell/theme.json``; the shell's ``FileView``
watches that file with ``watchChanges`` and reloads on external writes, so
changes apply live without a shell restart.

Writes are gated by the settings window's save/discard lifecycle: edits
are staged in memory (``_data`` vs the ``_saved`` deep snapshot) and only
persisted on Save, exactly like the other standalone pages.
"""

from collections.abc import Iterable
from copy import deepcopy
import os
import subprocess
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import THEME_DEFAULTS, load_theme, save_theme
from settings.ui.color_combo import get_color, make_color_combo_row, set_color
from settings.ui.icons import SHELL_THEME_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_float_row, make_spin_int_row
from settings.ui.variant_preview import make_variant_preview, make_variant_preview_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

# Variant keys from THEME_DEFAULTS (mirrors ``theme.js`` sr* entries).
_VARIANT_KEYS = [k for k in THEME_DEFAULTS if k.startswith("sr")]

_RETRO_DIR = os.environ.get("RETRO_DIR", "/opt/retrolinux")
_FONT_CORE = os.path.join(_RETRO_DIR, "scripts", "font_core.sh")


def _installed_fonts() -> list[str]:
    """Return installed font families (sorted), like the Fonts page."""
    try:
        result = subprocess.run(
            ["bash", _FONT_CORE, "--list-installed"],
            capture_output=True, text=True, timeout=15,
            stdin=subprocess.DEVNULL,
        )
        return sorted(
            l.strip() for l in result.stdout.strip().splitlines() if l.strip()
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return []

_GRADIENT_TYPES = [
    ("linear", "Linear"),
    ("radial", "Radial"),
    ("halftone", "Halftone"),
]

_GRADIENT_TYPE_IDS = [t[0] for t in _GRADIENT_TYPES]


def _variant_id(key: str) -> str:
    """Convert ``srX`` key to the shell's variant id (``srBarBg`` → ``barbg``)."""
    return key[2:].lower()


class ShellThemePage:
    """Shell theme configuration — writes ``theme.json`` on save."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None
        self._data = load_theme()
        self._saved = deepcopy(self._data)
        self._rows: dict[str, ManagedRow] = {}
        self._editor_rows: dict[str, ManagedRow] = {}
        self._editor_group: Adw.PreferencesGroup | None = None
        self._editor_widgets: list[Gtk.Widget] = []
        self._stops_rows: list[tuple[str, str, int, ManagedRow]] = []
        self._stops_count = 0
        self._current_variant = _VARIANT_KEYS[0]
        self._preview: Gtk.DrawingArea | None = None

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        from settings.ui import make_page_layout

        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)

        general_group = Adw.PreferencesGroup(
            title="General",
            description="Icons, corners, animations, fonts, and corner roundness.",
        )
        self._build_general_group(general_group)
        content_box.append(general_group)

        shadow_group = Adw.PreferencesGroup(
            title="Shadow",
            description="Shadow opacity, blur, offset, and color.",
        )
        self._build_shadow_group(shadow_group)
        content_box.append(shadow_group)

        colors_group = Adw.PreferencesGroup(
            title="Colors",
            description="Pick a variant surface and tune its gradient, border, and opacity.",
        )
        self._build_colors_group(colors_group)
        content_box.append(colors_group)

        self._editor_group = Adw.PreferencesGroup(title="Variant")
        content_box.append(self._editor_group)
        self._rebuild_variant_editor()

        return toolbar

    # ── Groups ──

    def _build_general_group(self, group: Adw.PreferencesGroup) -> None:
        for key, label, sub in (
            ("tintIcons", "Tint Icons", "Apply the theme accent color to icons"),
            ("enableCorners", "Enable Corners", "Round the corners of panels and surfaces"),
        ):
            self._add_switch(group, key, label, subtitle=sub)
        self._add_spin(group, "animDuration", "Animation Duration",
                       lower=0, upper=2000, suffix="ms",
                       subtitle="Length of UI animations in milliseconds (0 disables)")
        self._add_font_combo(group, "font", "UI Font",
                             subtitle="Font family used across the shell interface")
        self._add_spin(group, "fontSize", "UI Font Size",
                       lower=8, upper=32, suffix="px",
                       subtitle="Base font size for the shell interface")
        self._add_font_combo(group, "monoFont", "Mono Font",
                             subtitle="Monospace font used for terminals and code")
        self._add_spin(group, "monoFontSize", "Mono Font Size",
                       lower=8, upper=32, suffix="px",
                       subtitle="Base size for monospace text")
        self._add_spin(group, "roundness", "Roundness",
                       lower=0, upper=20, suffix="px",
                       subtitle="Corner radius of panels and buttons")

    def _build_shadow_group(self, group: Adw.PreferencesGroup) -> None:
        self._add_float_spin(group, "shadowOpacity", "Opacity", lower=0.0, upper=1.0,
                             subtitle="Shadow strength (0–1)")
        self._add_float_spin(group, "shadowBlur", "Blur", lower=0.0, upper=20.0, digits=1,
                             subtitle="Shadow softness in pixels")
        for key, label, sub in (
            ("shadowXOffset", "Offset X", "Horizontal shadow offset"),
            ("shadowYOffset", "Offset Y", "Vertical shadow offset"),
        ):
            self._add_spin(group, key, label, lower=-20, upper=20, suffix="px", subtitle=sub)
        self._add_color_combo(group, "shadowColor", "Color",
                              subtitle="Color used for the drop shadow")

    def _build_colors_group(self, group: Adw.PreferencesGroup) -> None:
        options = [(k, self._data.get(k, {}).get("label", _variant_id(k))) for k in _VARIANT_KEYS]
        ids = [o[0] for o in options]
        labels = [o[1] for o in options]
        row = make_variant_preview_row(self, "Variant", ids, labels, selected=0,
                                       subtitle="Surface whose colors you want to adjust")
        group.add(row)

        def _on_variant_changed(_row, _pspec):
            idx = row.get_selected()
            if 0 <= idx < len(ids):
                self._current_variant = ids[idx]
            self._rebuild_variant_editor()

        row.connect("notify::selected", _on_variant_changed)

    def _editor_add(self, widget: Gtk.Widget) -> None:
        """Append a row to the variant editor group, tracking it for removal."""
        if self._editor_group is not None:
            self._editor_group.add(widget)  # type: ignore[attr-defined]
            self._editor_widgets.append(widget)

    def _rebuild_variant_editor(self) -> None:
        group = self._editor_group
        if group is None:
            return
        for widget in self._editor_widgets:
            group.remove(widget)  # type: ignore[attr-defined]
        self._editor_widgets.clear()
        self._editor_rows.clear()
        self._stops_rows.clear()
        self._stops_count = 0

        vk = self._current_variant
        vdata = self._data.get(vk, {})
        label = vdata.get("label", _variant_id(vk))
        group.set_title(f"Variant — {label}")

        preview = make_variant_preview(self, vk)
        preview_holder = Adw.PreferencesRow()
        preview_holder.set_child(preview)
        preview_holder.set_selectable(False)
        self._preview = preview
        self._editor_add(preview_holder)

        gradient_type = vdata.get("gradientType", "linear")
        try:
            gsel = _GRADIENT_TYPE_IDS.index(gradient_type)
        except ValueError:
            gsel = 0

        # Gradient type
        grow = make_combo_row("Gradient Type", model=Gtk.StringList.new(
            [t[1] for t in _GRADIENT_TYPES]), selected=gsel,
            subtitle="Fill style for this surface")
        self._editor_add(grow)

        def _get_gtype():
            idx = grow.get_selected()
            return _GRADIENT_TYPE_IDS[idx] if 0 <= idx < len(_GRADIENT_TYPE_IDS) else "linear"

        def _set_gtype(value):
            try:
                grow.set_selected(_GRADIENT_TYPE_IDS.index(value))
            except ValueError:
                grow.set_selected(0)

        def _on_gtype_value_set(value):
            self._on_variant_change("gradientType", value)

        gtype_mrow = self._make_managed(grow, "gradientType", _get_gtype, _set_gtype,
                                        _on_gtype_value_set)
        self._editor_rows["gradientType"] = gtype_mrow

        # Gradient-type dependent controls
        self._editor_rows["itemColor"] = self._add_variant_color(
            group, vk, "itemColor", "Item Color",
            subtitle="Color of icons and text on this surface")
        self._editor_rows["opacity"] = self._add_variant_float(
            group, vk, "opacity", "Opacity", lower=0.0, upper=1.0, step=0.01, digits=2,
            subtitle="Fill opacity (0–1)")

        if gradient_type in ("linear", "radial"):
            self._editor_rows["borderColor"] = self._add_variant_border_color(
                group, vk, subtitle="Color of the border around this surface")
            self._editor_rows["borderWidth"] = self._add_variant_border_width(
                group, vk, subtitle="Border thickness in pixels")
        else:
            # Halftone
            self._editor_rows["halftoneDotColor"] = self._add_variant_color(
                group, vk, "halftoneDotColor", "Dot Color",
                subtitle="Color of the halftone dots")
            self._editor_rows["halftoneBackgroundColor"] = self._add_variant_color(
                group, vk, "halftoneBackgroundColor", "Background Color",
                subtitle="Color between the halftone dots")

        if gradient_type == "linear":
            self._editor_rows["gradientAngle"] = self._add_variant_spin(
                group, vk, "gradientAngle", "Angle", lower=0, upper=360, suffix="°",
                subtitle="Gradient direction in degrees")
            self._build_stops_editor(group, vk)
        elif gradient_type == "radial":
            self._editor_rows["gradientCenterX"] = self._add_variant_float(
                group, vk, "gradientCenterX", "Center X", lower=0.0, upper=1.0, digits=2,
                subtitle="Radial gradient center, horizontally (0–1)")
            self._editor_rows["gradientCenterY"] = self._add_variant_float(
                group, vk, "gradientCenterY", "Center Y", lower=0.0, upper=1.0, digits=2,
                subtitle="Radial gradient center, vertically (0–1)")
            self._build_stops_editor(group, vk)
        else:
            # Halftone angle + dot size + range
            self._editor_rows["gradientAngle"] = self._add_variant_spin(
                group, vk, "gradientAngle", "Angle", lower=0, upper=360, suffix="°",
                subtitle="Gradient direction in degrees")
            self._editor_rows["halftoneDotMin"] = self._add_variant_float(
                group, vk, "halftoneDotMin", "Dot Min", lower=0.0, upper=20.0, digits=1,
                step=0.5, subtitle="Smallest halftone dot radius")
            self._editor_rows["halftoneDotMax"] = self._add_variant_float(
                group, vk, "halftoneDotMax", "Dot Max", lower=0.0, upper=20.0, digits=1,
                step=0.5, subtitle="Largest halftone dot radius")
            self._editor_rows["halftoneStart"] = self._add_variant_float(
                group, vk, "halftoneStart", "Range Start", lower=0.0, upper=1.0, digits=2,
                subtitle="Where the halftone gradient begins (0–1)")
            self._editor_rows["halftoneEnd"] = self._add_variant_float(
                group, vk, "halftoneEnd", "Range End", lower=0.0, upper=1.0, digits=2,
                subtitle="Where the halftone gradient ends (0–1)")

        # Wire gradient-type switching to rebuild dependent controls
        def _on_gtype_changed(*_args):
            self._data[vk]["gradientType"] = gtype_mrow.value
            self._rebuild_variant_editor()
            self._notify_dirty()

        grow.connect("notify::selected", _on_gtype_changed)

    # ── Gradient stops editor ──

    def _build_stops_editor(self, group: Adw.PreferencesGroup, vk: str) -> None:
        stops = self._data.get(vk, {}).get("gradient") or []
        self._stops_count = len(stops)

        for i, stop in enumerate(stops):
            color_name = stop[0] if isinstance(stop, list) and stop else "surface"
            position = float(stop[1]) if isinstance(stop, list) and len(stop) > 1 else 0.0

            def _commit_stop_color(value: str, s=stop) -> None:
                s[0] = value
                self._notify_dirty()

            crow, ids, state = make_color_combo_row(
                "Stop Color", color_name, subtitle="Color at this gradient stop",
                on_change=_commit_stop_color)
            self._editor_add(crow)

            def _stop_color_value(stop=stop):
                return stop[0] if isinstance(stop, list) and stop else "surface"

            def _get_stop_color(stop=stop):
                return get_color(crow, ids, _stop_color_value(stop))

            def _set_stop_color(value, stop=stop):
                set_color(crow, ids, state, value)

            def _on_stop_color(value, stop=stop):
                stop[0] = value
                self._notify_dirty()

            cmrow = ManagedRow(
                crow,
                default=color_name,
                baseline=color_name,
                get_value=_get_stop_color,
                set_value_silent=_set_stop_color,
                on_value_set=_on_stop_color,
            )

            def _on_stop_color_selected(*_args, m=cmrow):
                if crow.get_selected() == 0:
                    return
                m.refresh()
                self._notify_dirty()

            crow.connect("notify::selected", _on_stop_color_selected)
            self._stops_rows.append((vk, "color", i, cmrow))

            pro, spin = make_spin_float_row("Stop Position", value=position,
                                            lower=0.0, upper=1.0, digits=2,
                                            subtitle="Position of this stop along the gradient (0–1)")
            self._editor_add(pro)

            def _get_stop_pos(stop=stop):
                return float(spin.get_value())

            def _set_stop_pos(value, stop=stop):
                spin.set_value(float(value))

            def _on_stop_pos(value, stop=stop):
                stop[1] = float(value)
                self._notify_dirty()

            pmrow = ManagedRow(
                pro,
                default=position,
                baseline=position,
                get_value=_get_stop_pos,
                set_value_silent=_set_stop_pos,
                on_value_set=_on_stop_pos,
            )
            spin.connect("value-changed",
                         lambda *_a, m=pmrow: (m.refresh(), self._notify_dirty()))
            self._stops_rows.append((vk, "pos", i, pmrow))

        add_btn = Gtk.Button(label="Add Stop")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.add_css_class("flat")
        add_btn.connect("clicked", lambda *_a: self._add_stop(vk))
        add_row = Adw.ActionRow(title="Add Stop", subtitle="Append a gradient stop.")
        add_row.add_suffix(add_btn)
        self._editor_add(add_row)

        if stops:
            rm_btn = Gtk.Button(label="Remove Last")
            rm_btn.set_valign(Gtk.Align.CENTER)
            rm_btn.add_css_class("flat")
            rm_btn.connect("clicked", lambda *_a: self._remove_stop(vk))
            rm_row = Adw.ActionRow(title="Remove Last", subtitle="Drop the final stop.")
            rm_row.add_suffix(rm_btn)
            self._editor_add(rm_row)

    def _add_stop(self, vk: str) -> None:
        gradient = self._data[vk].setdefault("gradient", [["surface", 0.0]])
        gradient.append(["surface", 1.0])
        self._rebuild_variant_editor()
        self._notify_dirty()

    def _remove_stop(self, vk: str) -> None:
        gradient = self._data[vk].get("gradient")
        if gradient and len(gradient) > 1:
            gradient.pop()
            self._rebuild_variant_editor()
            self._notify_dirty()

    # ── Row builders ──

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, THEME_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=THEME_DEFAULTS[key],
            baseline=self._saved.get(key, THEME_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(row, "notify::active", key, mrow)
        return mrow

    def _add_entry(self, group: Adw.PreferencesGroup, key: str, label: str,
                   subtitle: str = "") -> ManagedRow:
        row = Adw.ActionRow(title=label, subtitle=subtitle)
        entry = Gtk.Entry(text=str(self._data.get(key, THEME_DEFAULTS[key])))
        row.set_child(entry)
        row.set_activatable_widget(entry)
        group.add(row)

        def get_value():
            return entry.get_text()

        def set_silent(value):
            entry.set_text(str(value))

        mrow = ManagedRow(
            row,
            default=THEME_DEFAULTS[key],
            baseline=self._saved.get(key, THEME_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(entry, "changed", key, mrow)
        return mrow

    def _add_font_combo(self, group: Adw.PreferencesGroup, key: str, label: str,
                        subtitle: str = "") -> ManagedRow:
        fonts = _installed_fonts()
        current = str(self._data.get(key, THEME_DEFAULTS[key]))
        if current and fonts:
            found = any(f.lower() == current.lower() for f in fonts)
            if not found:
                fonts = [current] + fonts
        model = Gtk.StringList.new(fonts) if fonts else Gtk.StringList.new([])
        selected = 0
        if current and fonts:
            for i, f in enumerate(fonts):
                if f.lower() == current.lower():
                    selected = i
                    break
        row = make_combo_row(label, model=model, selected=selected, subtitle=subtitle)
        group.add(row)

        def get_value():
            idx = row.get_selected()
            if 0 <= idx < len(fonts):
                return fonts[idx]
            return current if current else (fonts[0] if fonts else "")

        def set_silent(value):
            try:
                row.set_selected(
                    next(i for i, f in enumerate(fonts) if f.lower() == str(value).lower()))
            except StopIteration:
                row.set_selected(0)

        mrow = ManagedRow(
            row,
            default=THEME_DEFAULTS[key],
            baseline=self._saved.get(key, THEME_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(row, "notify::selected", key, mrow)
        return mrow

    def _add_spin(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        *,
        lower: int,
        upper: int,
        suffix: str,
        subtitle: str = "",
    ) -> ManagedRow:
        row, spin = make_spin_int_row(
            label,
            value=int(self._data.get(key, THEME_DEFAULTS[key])),
            lower=lower,
            upper=upper,
            step=1,
            page_step=5,
            subtitle=subtitle,
        )
        group.add(row)
        if suffix:
            suffix_lbl = Gtk.Label(label=suffix)
            suffix_lbl.add_css_class("dim-label")
            suffix_lbl.set_valign(Gtk.Align.CENTER)
            row.add_suffix(suffix_lbl)

        def get_value():
            return int(spin.get_value())

        def set_silent(value):
            spin.set_value(int(value))

        mrow = ManagedRow(
            row,
            default=THEME_DEFAULTS[key],
            baseline=self._saved.get(key, THEME_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(spin, "value-changed", key, mrow)
        return mrow

    def _add_float_spin(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        *,
        lower: float,
        upper: float,
        digits: int = 2,
        subtitle: str = "",
    ) -> ManagedRow:
        row, spin = make_spin_float_row(
            label,
            value=float(self._data.get(key, THEME_DEFAULTS[key])),
            lower=lower,
            upper=upper,
            digits=digits,
            subtitle=subtitle,
        )
        group.add(row)

        def get_value():
            return float(spin.get_value())

        def set_silent(value):
            spin.set_value(float(value))

        mrow = ManagedRow(
            row,
            default=THEME_DEFAULTS[key],
            baseline=self._saved.get(key, THEME_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(spin, "value-changed", key, mrow)
        return mrow

    def _add_color_combo(self, group: Adw.PreferencesGroup, key: str, label: str,
                         subtitle: str = "") -> ManagedRow:
        current = self._data.get(key, THEME_DEFAULTS[key])

        def _commit_custom(value: str, k=key) -> None:
            self._on_change(k, value)
            self._rows[k].refresh()

        row, ids, state = make_color_combo_row(
            label, current, subtitle=subtitle, on_change=_commit_custom)
        group.add(row)

        def get_value():
            return get_color(row, ids, self._data.get(key, THEME_DEFAULTS[key]))

        def set_silent(value):
            set_color(row, ids, state, value)

        mrow = ManagedRow(
            row,
            default=THEME_DEFAULTS[key],
            baseline=self._saved.get(key, THEME_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow

        def _on_color_selected(*_args):
            if row.get_selected() == 0:
                return
            self._data[key] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        row.connect("notify::selected", _on_color_selected)
        return mrow

    # ── Variant row builders (write into self._data[vk]) ──

    def _make_managed(self, row, field, get_value, set_silent, on_value_set) -> ManagedRow:
        vk = self._current_variant
        return ManagedRow(
            row,
            default=self._variant_default(vk, field),
            baseline=self._saved.get(vk, {}).get(field, self._variant_default(vk, field)),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=on_value_set,
        )

    def _variant_default(self, vk: str, field: str):
        return THEME_DEFAULTS.get(vk, {}).get(field)

    def _on_variant_change(self, field: str, value) -> None:
        self._data[self._current_variant][field] = value
        self._notify_dirty()

    def _add_variant_color(
        self,
        group: Adw.PreferencesGroup,
        vk: str,
        field: str,
        label: str,
        subtitle: str = "",
    ) -> ManagedRow:
        current = self._data.get(vk, {}).get(field, self._variant_default(vk, field))

        def _commit_custom(value: str, f=field) -> None:
            self._on_variant_change(f, value)
            self._editor_rows[f].refresh()

        row, ids, state = make_color_combo_row(
            label, current, subtitle=subtitle, on_change=_commit_custom)
        self._editor_add(row)

        def get_value():
            return get_color(row, ids,
                             self._data.get(vk, {}).get(field, self._variant_default(vk, field)))

        def set_silent(value):
            set_color(row, ids, state, value)

        def on_value_set(value, f=field):
            self._on_variant_change(f, value)

        mrow = ManagedRow(
            row,
            default=self._variant_default(vk, field),
            baseline=self._saved.get(vk, {}).get(field, self._variant_default(vk, field)),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=on_value_set,
        )
        self._editor_rows[field] = mrow

        def _on_color_selected(*_args):
            if row.get_selected() == 0:
                return
            self._data[vk][field] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        row.connect("notify::selected", _on_color_selected)
        return mrow

    def _add_variant_spin(
        self,
        group: Adw.PreferencesGroup,
        vk: str,
        field: str,
        label: str,
        *,
        lower: int,
        upper: int,
        suffix: str,
        subtitle: str = "",
    ) -> ManagedRow:
        row, spin = make_spin_int_row(
            label,
            value=int(self._data.get(vk, {}).get(field, self._variant_default(vk, field))),
            lower=lower,
            upper=upper,
            step=1,
            page_step=5,
            subtitle=subtitle,
        )
        self._editor_add(row)
        if suffix:
            suffix_lbl = Gtk.Label(label=suffix)
            suffix_lbl.add_css_class("dim-label")
            suffix_lbl.set_valign(Gtk.Align.CENTER)
            row.add_suffix(suffix_lbl)

        def get_value():
            return int(spin.get_value())

        def set_silent(value):
            spin.set_value(int(value))

        def on_value_set(value, f=field):
            self._on_variant_change(f, value)

        mrow = ManagedRow(
            row,
            default=self._variant_default(vk, field),
            baseline=self._saved.get(vk, {}).get(field, self._variant_default(vk, field)),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=on_value_set,
        )
        self._editor_rows[field] = mrow
        self._wire_variant_change(spin, "value-changed", vk, field, mrow)
        return mrow

    def _add_variant_float(
        self,
        group: Adw.PreferencesGroup,
        vk: str,
        field: str,
        label: str,
        *,
        lower: float,
        upper: float,
        step: float = 0.01,
        digits: int = 2,
        subtitle: str = "",
    ) -> ManagedRow:
        row, spin = make_spin_float_row(
            label,
            value=float(self._data.get(vk, {}).get(field, self._variant_default(vk, field))),
            lower=lower,
            upper=upper,
            step=step,
            digits=digits,
            subtitle=subtitle,
        )
        self._editor_add(row)

        def get_value():
            return float(spin.get_value())

        def set_silent(value):
            spin.set_value(float(value))

        def on_value_set(value, f=field):
            self._on_variant_change(f, value)

        mrow = ManagedRow(
            row,
            default=self._variant_default(vk, field),
            baseline=self._saved.get(vk, {}).get(field, self._variant_default(vk, field)),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=on_value_set,
        )
        self._editor_rows[field] = mrow
        self._wire_variant_change(spin, "value-changed", vk, field, mrow)
        return mrow

    def _add_variant_border_color(self, group: Adw.PreferencesGroup, vk: str,
                                  subtitle: str = "") -> ManagedRow:
        border = self._data.get(vk, {}).get("border", ["surfaceBright", 0])
        current = border[0] if isinstance(border, list) and border else "surfaceBright"

        def _commit_border_color(value: str, v=vk) -> None:
            self._set_border_color(v, value)
            self._editor_rows["borderColor"].refresh()
            self._notify_dirty()

        row, ids, state = make_color_combo_row(
            "Border Color", current, subtitle=subtitle, on_change=_commit_border_color)
        self._editor_add(row)

        def _border_value():
            border = self._data.get(vk, {}).get("border", ["surfaceBright", 0])
            return border[0] if isinstance(border, list) and border else "surfaceBright"

        def get_value():
            return get_color(row, ids, _border_value())

        def set_silent(value):
            set_color(row, ids, state, value)

        def on_value_set(value):
            self._set_border_color(vk, value)
            self._notify_dirty()

        mrow = ManagedRow(
            row,
            default="surfaceBright",
            baseline=self._saved.get(vk, {}).get("border", ["surfaceBright", 0])[0]
            if isinstance(self._saved.get(vk, {}).get("border", ["surfaceBright", 0]), list)
            else "surfaceBright",
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=on_value_set,
        )
        self._editor_rows["borderColor"] = mrow

        def _on_color_selected(*_args):
            if row.get_selected() == 0:
                return
            value = mrow.value
            self._set_border_color(vk, value)
            mrow.refresh()
            self._notify_dirty()

        row.connect("notify::selected", _on_color_selected)
        return mrow

    def _set_border_color(self, vk: str, value: str) -> None:
        border = self._data[vk].get("border", ["surfaceBright", 0])
        if isinstance(border, list) and len(border) > 1:
            border[0] = value
        else:
            self._data[vk]["border"] = [value, 0]

    def _add_variant_border_width(self, group: Adw.PreferencesGroup, vk: str,
                                  subtitle: str = "") -> ManagedRow:
        border = self._data.get(vk, {}).get("border", ["surfaceBright", 0])
        current = border[1] if isinstance(border, list) and len(border) > 1 else 0
        row, spin = make_spin_int_row(
            "Border Width", value=int(current), lower=0, upper=16, step=1, page_step=2,
            subtitle=subtitle)
        self._editor_add(row)
        suffix_lbl = Gtk.Label(label="px")
        suffix_lbl.add_css_class("dim-label")
        suffix_lbl.set_valign(Gtk.Align.CENTER)
        row.add_suffix(suffix_lbl)

        def get_value():
            return int(spin.get_value())

        def set_silent(value):
            spin.set_value(int(value))

        def on_value_set(value):
            border = self._data[vk].get("border", ["surfaceBright", 0])
            if isinstance(border, list):
                border[1] = int(value)
            else:
                self._data[vk]["border"] = ["surfaceBright", int(value)]
            self._notify_dirty()

        mrow = ManagedRow(
            row,
            default=0,
            baseline=self._saved.get(vk, {}).get("border", ["surfaceBright", 0])[1]
            if isinstance(self._saved.get(vk, {}).get("border", ["surfaceBright", 0]), list)
            else 0,
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=on_value_set,
        )
        self._editor_rows["borderWidth"] = mrow

        def _border_width_changed(*_args):
            value = mrow.value
            border = self._data[vk].get("border", ["surfaceBright", 0])
            if isinstance(border, list) and len(border) > 1:
                border[1] = value
            else:
                self._data[vk]["border"] = ["surfaceBright", value]
            mrow.refresh()
            self._notify_dirty()

        spin.connect("value-changed", _border_width_changed)
        return mrow

    # ── Change plumbing ──

    def _wire_change(self, widget: Gtk.Widget, signal: str, key: str, mrow: ManagedRow) -> None:
        def _changed(*_args):
            self._data[key] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        widget.connect(signal, _changed)

    def _wire_variant_change(
        self, widget: Gtk.Widget, signal: str, vk: str, field: str, mrow: ManagedRow
    ) -> None:
        def _changed(*_args):
            self._data[vk][field] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        widget.connect(signal, _changed)

    def _on_change(self, key: str, value) -> None:
        self._data[key] = value
        self._notify_dirty()

    def _notify_dirty(self) -> None:
        if self._preview is not None:
            self._preview.queue_draw()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    # ── Lifecycle ──

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        save_theme(self._data)
        self._saved = deepcopy(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, THEME_DEFAULTS[key]))
        vk = self._current_variant
        for field, mrow in self._editor_rows.items():
            if field == "borderColor":
                border = self._data.get(vk, {}).get("border", ["surfaceBright", 0])
                mrow.set_baseline(border[0] if isinstance(border, list) and border else "surfaceBright")
            elif field == "borderWidth":
                border = self._data.get(vk, {}).get("border", ["surfaceBright", 0])
                mrow.set_baseline(border[1] if isinstance(border, list) and len(border) > 1 else 0)
            else:
                mrow.set_baseline(self._data.get(vk, {}).get(field, self._variant_default(vk, field)))
        for _vk, _f, _i, mrow in self._stops_rows:
            mrow.refresh()

    def discard(self) -> None:
        self._data = deepcopy(self._saved)
        # Snapshot the row collections: discarding the Gradient Type row
        # rebuilds the variant editor (clearing/recreating these dicts), so
        # iterating them in place raises "dictionary changed size during
        # iteration".
        for mrow in list(self._rows.values()):
            mrow.discard()
        for mrow in list(self._editor_rows.values()):
            mrow.discard()
        for _vk, _f, _i, mrow in list(self._stops_rows):
            mrow.discard()
        self._rebuild_variant_editor()

    # ── Pending changes ──

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                changed.append({
                    "font": "Font", "monoFont": "Mono Font",
                    "shadowColor": "Shadow Color", "shadowOpacity": "Shadow Opacity",
                    "roundness": "Roundness", "animDuration": "Animation",
                }.get(key, key))
        for vk in _VARIANT_KEYS:
            if self._data.get(vk) != self._saved.get(vk):
                changed.append(self._data.get(vk, {}).get("label", _variant_id(vk)))
        if changed:
            yield PendingChange(
                category="Shell Theme",
                title="Theme",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_theme",
                icon=SHELL_THEME_ICON,
                kind="modified",
                revert=self.discard,
            )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_theme:general", "label": "Theme General",
             "description": "Tint icons, corners, animations, fonts, roundness",
             "_group_id": "shell_theme", "_group_label": "Theme", "_section_label": "General"},
            {"key": "shell_theme:shadow", "label": "Theme Shadow",
             "description": "Shadow opacity, blur, offset, color",
             "_group_id": "shell_theme", "_group_label": "Theme", "_section_label": "Shadow"},
            {"key": "shell_theme:colors", "label": "Theme Colors",
             "description": "Variant gradient, border, opacity, halftone",
             "_group_id": "shell_theme", "_group_label": "Theme", "_section_label": "Colors"},
        ]


__all__ = ["ShellThemePage"]
