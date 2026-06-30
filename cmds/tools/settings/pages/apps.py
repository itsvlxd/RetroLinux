import os
import subprocess

from gi.repository import Adw, Gtk

from lib.python.variable import get_module_default, get_var, set_var
from settings.ui import make_page_layout
from settings.ui.row_actions import RowActions

_FONT_ALIASES = [
    ("Main Font", "RETRO_FONT_MAIN"),
    ("Nerd Font", "RETRO_FONT_NERD"),
    ("Emoji Font", "RETRO_FONT_EMOJI"),
]


def _list_installed_fonts() -> list[str]:
    result = subprocess.run(
        ["bash", os.environ.get("RETRO_DIR", "") + "/scripts/font_core.sh", "--list-installed"],
        capture_output=True, text=True, timeout=15,
    )
    fonts = [l.strip() for l in result.stdout.strip().split("\n") if l.strip()]
    return sorted(set(fonts), key=str.casefold)


def _resolve_alias(var_name: str, fallback: str = "") -> str:
    return get_var(var_name, fallback)


class AppsPage:
    _FONT_VARS = ("GTK_FONT", "KITTY_FONT", "ROFI_FONT")

    def __init__(self, window):
        self._window = window
        self._notify_dirty = lambda: None
        self._dirty = False

        self._installed_fonts: list[str] = []
        self._font_alias_values: list[str] = []

        # Combo rows + parallel value lists
        self._gtk_font_row: Adw.ComboRow | None = None
        self._gtk_font_values: list[str] = []
        self._kitty_font_row: Adw.ComboRow | None = None
        self._kitty_font_values: list[str] = []
        self._rofi_font_row: Adw.ComboRow | None = None
        self._rofi_font_values: list[str] = []

        self._gtk_font_size_row: Adw.ActionRow | None = None
        self._kitty_font_size_row: Adw.ActionRow | None = None
        self._kitty_padding_row: Adw.ActionRow | None = None
        self._kitty_opacity_active_row: Adw.ActionRow | None = None
        self._kitty_shrink_row: Adw.SwitchRow | None = None
        self._kitty_font_width_row: Adw.ActionRow | None = None
        self._kitty_font_height_row: Adw.ActionRow | None = None
        self._kitty_scrollback_row: Adw.ActionRow | None = None
        self._kitty_dynamic_opacity_row: Adw.SwitchRow | None = None
        self._kitty_audio_bell_row: Adw.SwitchRow | None = None
        self._kitty_tab_edge_row: Adw.ComboRow | None = None
        self._kitty_tab_edge_values: list[str] = []
        self._kitty_tab_style_row: Adw.ComboRow | None = None
        self._kitty_tab_style_values: list[str] = []
        self._rofi_font_size_row: Adw.ActionRow | None = None
        self._rofi_y_offset_row: Adw.ActionRow | None = None
        self._rofi_icon_size_row: Adw.ActionRow | None = None
        self._rofi_spacing_row: Adw.ActionRow | None = None
        self._rofi_input_padding_row: Adw.ActionRow | None = None
        self._rofi_padding_row: Adw.ActionRow | None = None
        self._rofi_rounding_row: Adw.ActionRow | None = None
        self._rofi_border_row: Adw.ActionRow | None = None

        self._gtk_font_actions: RowActions | None = None
        self._gtk_font_size_actions: RowActions | None = None
        self._kitty_font_actions: RowActions | None = None
        self._kitty_font_size_actions: RowActions | None = None
        self._kitty_padding_actions: RowActions | None = None
        self._kitty_opacity_active_actions: RowActions | None = None
        self._kitty_shrink_actions: RowActions | None = None
        self._kitty_font_width_actions: RowActions | None = None
        self._kitty_font_height_actions: RowActions | None = None
        self._kitty_scrollback_actions: RowActions | None = None
        self._kitty_dynamic_opacity_actions: RowActions | None = None
        self._kitty_audio_bell_actions: RowActions | None = None
        self._kitty_tab_edge_actions: RowActions | None = None
        self._kitty_tab_style_actions: RowActions | None = None
        self._rofi_font_actions: RowActions | None = None
        self._rofi_font_size_actions: RowActions | None = None
        self._rofi_y_offset_actions: RowActions | None = None
        self._rofi_icon_size_actions: RowActions | None = None
        self._rofi_spacing_actions: RowActions | None = None
        self._rofi_input_padding_actions: RowActions | None = None
        self._rofi_padding_actions: RowActions | None = None
        self._rofi_rounding_actions: RowActions | None = None
        self._rofi_border_actions: RowActions | None = None

        self._gtk_font_spin: Gtk.SpinButton | None = None
        self._kitty_font_spin: Gtk.SpinButton | None = None
        self._kitty_font_width_spin: Gtk.SpinButton | None = None
        self._kitty_font_height_spin: Gtk.SpinButton | None = None
        self._kitty_scrollback_spin: Gtk.SpinButton | None = None
        self._kitty_padding_spin: Gtk.SpinButton | None = None
        self._kitty_opacity_active_spin: Gtk.SpinButton | None = None
        self._rofi_font_spin: Gtk.SpinButton | None = None
        self._rofi_y_offset_spin: Gtk.SpinButton | None = None
        self._rofi_icon_size_spin: Gtk.SpinButton | None = None
        self._rofi_spacing_spin: Gtk.SpinButton | None = None
        self._rofi_input_padding_spin: Gtk.SpinButton | None = None
        self._rofi_padding_spin: Gtk.SpinButton | None = None
        self._rofi_rounding_spin: Gtk.SpinButton | None = None
        self._rofi_border_spin: Gtk.SpinButton | None = None

        self._setting_value = False

        # Pending state per variable
        self._pending: dict[str, str | None] = {}

    # ── Managed-row helpers ──────────────────────────────────────────────

    _MANAGED = [
        ("GTK_FONT", "_gtk_font_row", "_gtk_font_actions"),
        ("GTK_FONT_SIZE", "_gtk_font_size_row", "_gtk_font_size_actions"),
        ("KITTY_FONT", "_kitty_font_row", "_kitty_font_actions"),
        ("KITTY_FONT_SIZE", "_kitty_font_size_row", "_kitty_font_size_actions"),
        ("KITTY_PADDING", "_kitty_padding_row", "_kitty_padding_actions"),
        ("KITTY_OPACITY_ACTIVE", "_kitty_opacity_active_row", "_kitty_opacity_active_actions"),
        ("KITTY_FONT_WIDTH", "_kitty_font_width_row", "_kitty_font_width_actions"),
        ("KITTY_FONT_HEIGHT", "_kitty_font_height_row", "_kitty_font_height_actions"),
        ("KITTY_SCROLLBACK", "_kitty_scrollback_row", "_kitty_scrollback_actions"),
        ("KITTY_DYNAMIC_OPACITY", "_kitty_dynamic_opacity_row", "_kitty_dynamic_opacity_actions"),
        ("KITTY_AUDIO_BELL", "_kitty_audio_bell_row", "_kitty_audio_bell_actions"),
        ("KITTY_TAB_EDGE", "_kitty_tab_edge_row", "_kitty_tab_edge_actions"),
        ("KITTY_TAB_STYLE", "_kitty_tab_style_row", "_kitty_tab_style_actions"),
        ("KITTY_SHRINK_PADDING_FULLSCREEN", "_kitty_shrink_row", "_kitty_shrink_actions"),
        ("ROFI_FONT", "_rofi_font_row", "_rofi_font_actions"),
        ("ROFI_FONT_SIZE", "_rofi_font_size_row", "_rofi_font_size_actions"),
        ("ROFI_Y_OFFSET", "_rofi_y_offset_row", "_rofi_y_offset_actions"),
        ("ROFI_ICON_SIZE", "_rofi_icon_size_row", "_rofi_icon_size_actions"),
        ("ROFI_SPACING", "_rofi_spacing_row", "_rofi_spacing_actions"),
        ("ROFI_INPUT_PADDING", "_rofi_input_padding_row", "_rofi_input_padding_actions"),
        ("ROFI_PADDING", "_rofi_padding_row", "_rofi_padding_actions"),
        ("ROFI_ROUNDING", "_rofi_rounding_row", "_rofi_rounding_actions"),
        ("ROFI_BORDER_SIZE", "_rofi_border_row", "_rofi_border_actions"),
    ]

    def _refresh_managed(self) -> None:
        for var, row_attr, actions_attr in self._MANAGED:
            row = getattr(self, row_attr)
            actions = getattr(self, actions_attr)
            if row is None or actions is None:
                continue
            live = get_var(var, "")
            default = get_module_default(var)
            if not default:
                default = live
            effective = self._pending.get(var, live)
            is_managed = effective != default
            is_dirty = var in self._pending
            is_saved = live != default
            actions.update(is_managed=is_managed, is_dirty=is_dirty, is_saved=is_saved)

    # ── Discard / Reset per variable ─────────────────────────────────────

    def _discard_var(self, var: str):
        live = get_var(var, get_module_default(var))
        self._set_widget_value(var, live)
        self._pending.pop(var, None)
        self._check_dirty()
        self._refresh_managed()

    def _reset_var(self, var: str):
        default = get_module_default(var)
        self._set_widget_value(var, default)
        self._set_pending_from_widget(var, default)
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _set_pending_from_widget(self, var: str, raw: str):
        live = get_var(var, "")
        if raw == live:
            self._pending.pop(var, None)
        else:
            self._pending[var] = raw
        self._check_dirty()

    def _font_value_list(self, var: str) -> list[str]:
        if var == "GTK_FONT":
            return self._gtk_font_values
        if var == "KITTY_FONT":
            return self._kitty_font_values
        if var == "ROFI_FONT":
            return self._rofi_font_values
        return []

    def _set_widget_value(self, var: str, value: str):
        self._setting_value = True
        if var in self._FONT_VARS:
            values = self._font_value_list(var)
            if not values:
                self._setting_value = False
                return
            try:
                idx = values.index(value)
            except ValueError:
                idx = 0
            widget: Adw.ComboRow | None = getattr(self, f"_{var.lower()}_row", None)  # type: ignore[assignment]
            if widget is not None:
                widget.set_selected(idx)
        elif var == "GTK_FONT_SIZE" and self._gtk_font_spin is not None:
            self._gtk_font_spin.set_value(float(value) if value else 10.0)
        elif var == "KITTY_FONT_SIZE" and self._kitty_font_spin is not None:
            self._kitty_font_spin.set_value(float(value) if value else 11.0)
        elif var == "KITTY_PADDING" and self._kitty_padding_spin is not None:
            self._kitty_padding_spin.set_value(float(value) if value else 10)
        elif var == "KITTY_OPACITY_ACTIVE" and self._kitty_opacity_active_spin is not None:
            self._kitty_opacity_active_spin.set_value(float(value) if value else 1.0)
        elif var == "KITTY_FONT_WIDTH" and self._kitty_font_width_spin is not None:
            self._kitty_font_width_spin.set_value(float(value) if value else 105)
        elif var == "KITTY_FONT_HEIGHT" and self._kitty_font_height_spin is not None:
            self._kitty_font_height_spin.set_value(float(value) if value else 95)
        elif var == "KITTY_SCROLLBACK" and self._kitty_scrollback_spin is not None:
            self._kitty_scrollback_spin.set_value(float(value) if value else 10000)
        elif var == "KITTY_DYNAMIC_OPACITY" and self._kitty_dynamic_opacity_row is not None:
            self._kitty_dynamic_opacity_row.set_active(value == "true")
        elif var == "KITTY_AUDIO_BELL" and self._kitty_audio_bell_row is not None:
            self._kitty_audio_bell_row.set_active(value == "true")
        elif var == "KITTY_SHRINK_PADDING_FULLSCREEN" and self._kitty_shrink_row is not None:
            self._kitty_shrink_row.set_active(value == "true")
        elif var == "KITTY_TAB_EDGE" and self._kitty_tab_edge_row is not None:
            values = self._kitty_tab_edge_values
            try:
                idx = values.index(value)
            except ValueError:
                idx = 0
            self._kitty_tab_edge_row.set_selected(idx)
        elif var == "KITTY_TAB_STYLE" and self._kitty_tab_style_row is not None:
            values = self._kitty_tab_style_values
            try:
                idx = values.index(value)
            except ValueError:
                idx = 0
            self._kitty_tab_style_row.set_selected(idx)
        elif var == "ROFI_FONT_SIZE" and self._rofi_font_spin is not None:
            self._rofi_font_spin.set_value(float(value) if value else 12.0)
        elif var == "ROFI_PADDING" and self._rofi_padding_spin is not None:
            self._rofi_padding_spin.set_value(float(value) if value else 8)
        elif var == "ROFI_ROUNDING" and self._rofi_rounding_spin is not None:
            self._rofi_rounding_spin.set_value(float(value) if value else 12)
        elif var == "ROFI_BORDER_SIZE" and self._rofi_border_spin is not None:
            self._rofi_border_spin.set_value(float(value) if value else 2)
        elif var == "ROFI_Y_OFFSET" and self._rofi_y_offset_spin is not None:
            self._rofi_y_offset_spin.set_value(float(value) if value else 40)
        elif var == "ROFI_ICON_SIZE" and self._rofi_icon_size_spin is not None:
            self._rofi_icon_size_spin.set_value(float(value) if value else 128)
        elif var == "ROFI_SPACING" and self._rofi_spacing_spin is not None:
            self._rofi_spacing_spin.set_value(float(value) if value else 5)
        elif var == "ROFI_INPUT_PADDING" and self._rofi_input_padding_spin is not None:
            self._rofi_input_padding_spin.set_value(float(value) if value else 12)
        self._setting_value = False

    # ── Dirty tracking ──────────────────────────────────────────────────

    def _check_dirty(self):
        any_dirty = bool(self._pending)
        if any_dirty != self._dirty:
            self._dirty = any_dirty
            if not any_dirty:
                self._notify_dirty()

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self):
        self._dirty = False
        self._pending.clear()
        self._refresh_managed()

    def flush_pending(self):
        if not self._pending:
            return
        needs_colors = False
        for var, val in self._pending.items():
            if val is not None:
                set_var(var, val)
                if var in ("GTK_FONT", "GTK_FONT_SIZE"):
                    needs_colors = True
        subprocess.Popen(
            ["retro", "app", "all", "refresh"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if needs_colors:
            subprocess.Popen(
                ["retro", "theme", "apply-colors"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        self.mark_saved()

    # ── Callbacks ───────────────────────────────────────────────────────

    def _on_font_changed(self, row: Adw.ComboRow, _pspec, var: str, values: list[str]):
        if self._setting_value:
            return
        idx = row.get_selected()
        if idx < 0 or idx >= len(values):
            return
        raw = values[idx]
        self._set_pending_from_widget(var, raw)
        if var in self._pending:
            self._dirty = True
            self._notify_dirty()
        self._refresh_managed()

    def _on_spin_changed(self, spin: Gtk.SpinButton, _pspec, var: str):
        if self._setting_value:
            return
        raw = spin.get_value()
        val = str(int(raw)) if raw == int(raw) else str(raw)
        self._set_pending_from_widget(var, val)
        if var in self._pending:
            self._dirty = True
            self._notify_dirty()
        self._refresh_managed()

    def _on_switch_changed(self, switch: Adw.SwitchRow, _pspec, var: str):
        if self._setting_value:
            return
        val = "true" if switch.get_active() else "false"
        self._set_pending_from_widget(var, val)
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    # ── Build ───────────────────────────────────────────────────────────

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "apps:gtk_font", "label": "GTK Font", "description": "Font used by GTK applications and dialogs", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:gtk_font_size", "label": "GTK Font Size", "description": "Base font size for GTK applications (px)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_font", "label": "Kitty Font", "description": "Font used in the Kitty terminal emulator", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_font_size", "label": "Kitty Font Size", "description": "Font size for Kitty terminal (pt)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_padding", "label": "Kitty Padding", "description": "Inner padding around terminal content (px)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_shrink", "label": "Kitty Shrink Padding Fullscreen", "description": "Reduce padding when Kitty goes fullscreen", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_opacity_active", "label": "Kitty Active Opacity", "description": "Opacity for the active Kitty window", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_font_width", "label": "Kitty Font Cell Width", "description": "Width modifier for Kitty cell (percent)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_font_height", "label": "Kitty Font Cell Height", "description": "Height modifier for Kitty cell (percent)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_scrollback", "label": "Kitty Scrollback Lines", "description": "Number of scrollback lines in Kitty", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_dynamic_opacity", "label": "Kitty Dynamic Opacity", "description": "Allow per-window opacity changes in Kitty", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_audio_bell", "label": "Kitty Audio Bell", "description": "Enable terminal bell in Kitty", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_tab_edge", "label": "Kitty Tab Bar Edge", "description": "Position of the tab bar in Kitty", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:kitty_tab_style", "label": "Kitty Tab Bar Style", "description": "Visual style of the Kitty tab bar", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_font", "label": "Rofi Font", "description": "Font used by the Rofi application launcher", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_font_size", "label": "Rofi Font Size", "description": "Font size for Rofi (pt)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_padding", "label": "Rofi Padding", "description": "Inner padding for Rofi dialog (px)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_rounding", "label": "Rofi Rounding", "description": "Corner radius for Rofi windows (px)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_border", "label": "Rofi Border Size", "description": "Border width for Rofi windows (px)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_y_offset", "label": "Rofi Y Offset", "description": "Vertical offset for Rofi window position (%)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_icon_size", "label": "Rofi Icon Size", "description": "Size of app icons in Rofi (px)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_spacing", "label": "Rofi Spacing", "description": "Spacing between Rofi elements (px)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
            {"key": "apps:rofi_input_padding", "label": "Rofi Input Padding", "description": "Padding inside the Rofi search bar (px)", "_group_id": "apps", "_group_label": "Applications", "_section_label": "Settings"},
        ]

    def _make_spin_row(self, title: str, subtitle: str, var: str,
                       lower: float, upper: float, step: float,
                       default_val: float,
                       actions_attr: str, spin_attr: str,
                       is_int: bool = True) -> tuple[Adw.ActionRow, Gtk.SpinButton]:
        row = Adw.ActionRow(title=title)
        row.set_subtitle(subtitle)
        adj = Gtk.Adjustment(
            value=float(get_var(var, str(int(default_val)))),
            lower=lower, upper=upper,
            step_increment=step, page_increment=step * 10,
        )
        spin = Gtk.SpinButton(adjustment=adj, digits=0 if is_int else 1)
        spin.set_valign(Gtk.Align.CENTER)
        spin.connect("notify::value", self._on_spin_changed, var)
        row.add_suffix(spin)
        actions = RowActions(
            row,
            on_discard=lambda: self._discard_var(var),
            on_reset=lambda: self._reset_var(var),
        )
        row.add_suffix(actions.box)
        actions.reorder_first()
        setattr(self, actions_attr, actions)
        setattr(self, spin_attr, spin)
        return row, spin

    def _make_font_combo(self, var: str, title: str, subtitle: str,
                         actions_attr: str, row_attr: str,
                         values_attr: str) -> Adw.ComboRow:
        current = get_var(var, "")
        alias_values = [_resolve_alias(vn) for _, vn in _FONT_ALIASES]
        alias_display = [label for label, _ in _FONT_ALIASES]
        all_values = list(alias_values) + self._installed_fonts
        all_display = list(alias_display) + self._installed_fonts

        model = Gtk.StringList.new(all_display)
        try:
            sel = all_values.index(current)
        except ValueError:
            sel = 0

        row = Adw.ComboRow(title=title)
        row.set_subtitle(subtitle)
        row.set_model(model)
        row.set_selected(sel)

        row.connect("notify::selected", self._on_font_changed, var, all_values)
        actions = RowActions(
            row,
            on_discard=lambda: self._discard_var(var),
            on_reset=lambda: self._reset_var(var),
        )
        row.add_suffix(actions.box)
        actions.reorder_first()

        setattr(self, actions_attr, actions)
        setattr(self, row_attr, row)
        setattr(self, values_attr, all_values)
        return row

    def _make_combo_row(self, var: str, title: str, subtitle: str,
                        options: list[str], values: list[str],
                        actions_attr: str, row_attr: str,
                        values_attr: str) -> Adw.ComboRow:
        current = get_var(var, values[0])
        model = Gtk.StringList.new(options)
        try:
            sel = values.index(current)
        except ValueError:
            sel = 0
        row = Adw.ComboRow(title=title)
        row.set_subtitle(subtitle)
        row.set_model(model)
        row.set_selected(sel)
        row.connect("notify::selected", self._on_font_changed, var, values)
        actions = RowActions(
            row,
            on_discard=lambda: self._discard_var(var),
            on_reset=lambda: self._reset_var(var),
        )
        row.add_suffix(actions.box)
        actions.reorder_first()
        setattr(self, actions_attr, actions)
        setattr(self, row_attr, row)
        setattr(self, values_attr, values)
        return row

    def build(self, header: Adw.HeaderBar | None = None) -> Gtk.Widget:
        self._installed_fonts = _list_installed_fonts()
        self._font_alias_values = [_resolve_alias(vn) for _, vn in _FONT_ALIASES]

        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)

        # ── GTK ──────────────────────────────────────────────────────────
        gtk_group = Adw.PreferencesGroup(title="GTK")

        gtk_font_row = self._make_font_combo(
            var="GTK_FONT",
            title="GTK Font",
            subtitle="Font used by GTK applications and dialogs",
            actions_attr="_gtk_font_actions",
            row_attr="_gtk_font_row",
            values_attr="_gtk_font_values",
        )
        gtk_group.add(gtk_font_row)

        gtk_font_size_row, gtk_font_size_spin = self._make_spin_row(
            title="GTK Font Size",
            subtitle="Base font size for GTK applications (px)",
            var="GTK_FONT_SIZE",
            lower=1, upper=200, step=0.5,
            default_val=10.0,
            actions_attr="_gtk_font_size_actions",
            spin_attr="_gtk_font_spin",
            is_int=False,
        )
        gtk_group.add(gtk_font_size_row)
        self._gtk_font_size_row = gtk_font_size_row

        content_box.append(gtk_group)

        # ── Kitty ────────────────────────────────────────────────────────
        kitty_group = Adw.PreferencesGroup(title="Kitty")

        kitty_font_row = self._make_font_combo(
            var="KITTY_FONT",
            title="Kitty Font",
            subtitle="Font used in the Kitty terminal emulator",
            actions_attr="_kitty_font_actions",
            row_attr="_kitty_font_row",
            values_attr="_kitty_font_values",
        )
        kitty_group.add(kitty_font_row)

        kitty_font_size_row, kitty_font_size_spin = self._make_spin_row(
            title="Kitty Font Size",
            subtitle="Font size for Kitty terminal (pt)",
            var="KITTY_FONT_SIZE",
            lower=1, upper=200, step=0.5,
            default_val=11.0,
            actions_attr="_kitty_font_size_actions",
            spin_attr="_kitty_font_spin",
            is_int=False,
        )
        kitty_group.add(kitty_font_size_row)
        self._kitty_font_size_row = kitty_font_size_row

        kitty_padding_row, kitty_padding_spin = self._make_spin_row(
            title="Kitty Padding",
            subtitle="Inner padding around terminal content (px)",
            var="KITTY_PADDING",
            lower=0, upper=200, step=1,
            default_val=10,
            actions_attr="_kitty_padding_actions",
            spin_attr="_kitty_padding_spin",
        )
        kitty_group.add(kitty_padding_row)
        self._kitty_padding_row = kitty_padding_row

        kitty_opacity_active_row, kitty_opacity_active_spin = self._make_spin_row(
            title="Active Opacity",
            subtitle="Opacity for the active Kitty window",
            var="KITTY_OPACITY_ACTIVE",
            lower=0.0, upper=1.0, step=0.1,
            default_val=1.0,
            actions_attr="_kitty_opacity_active_actions",
            spin_attr="_kitty_opacity_active_spin",
            is_int=False,
        )
        kitty_group.add(kitty_opacity_active_row)
        self._kitty_opacity_active_row = kitty_opacity_active_row

        kitty_shrink_row = Adw.SwitchRow(title="Shrink Padding on Fullscreen")
        kitty_shrink_row.set_subtitle("Automatically reduce padding when Kitty goes fullscreen")
        kitty_shrink_row.set_active(get_var("KITTY_SHRINK_PADDING_FULLSCREEN", "false") == "true")
        kitty_shrink_row.connect("notify::active", self._on_switch_changed, "KITTY_SHRINK_PADDING_FULLSCREEN")
        self._kitty_shrink_actions = RowActions(
            kitty_shrink_row,
            on_discard=lambda: self._discard_var("KITTY_SHRINK_PADDING_FULLSCREEN"),
            on_reset=lambda: self._reset_var("KITTY_SHRINK_PADDING_FULLSCREEN"),
        )
        kitty_shrink_row.add_suffix(self._kitty_shrink_actions.box)
        self._kitty_shrink_actions.reorder_first()
        kitty_group.add(kitty_shrink_row)
        self._kitty_shrink_row = kitty_shrink_row

        # ── Kitty Advanced ────────────────────────────────────────────────
        kitty_font_width_row, kitty_font_width_spin = self._make_spin_row(
            title="Font Cell Width",
            subtitle="Width modifier for Kitty cell (percent)",
            var="KITTY_FONT_WIDTH",
            lower=50, upper=150, step=1,
            default_val=105,
            actions_attr="_kitty_font_width_actions",
            spin_attr="_kitty_font_width_spin",
        )
        kitty_group.add(kitty_font_width_row)
        self._kitty_font_width_row = kitty_font_width_row

        kitty_font_height_row, kitty_font_height_spin = self._make_spin_row(
            title="Font Cell Height",
            subtitle="Height modifier for Kitty cell (percent)",
            var="KITTY_FONT_HEIGHT",
            lower=50, upper=150, step=1,
            default_val=95,
            actions_attr="_kitty_font_height_actions",
            spin_attr="_kitty_font_height_spin",
        )
        kitty_group.add(kitty_font_height_row)
        self._kitty_font_height_row = kitty_font_height_row

        kitty_scrollback_row, kitty_scrollback_spin = self._make_spin_row(
            title="Scrollback Lines",
            subtitle="Number of scrollback lines in Kitty",
            var="KITTY_SCROLLBACK",
            lower=100, upper=1000000, step=500,
            default_val=10000,
            actions_attr="_kitty_scrollback_actions",
            spin_attr="_kitty_scrollback_spin",
        )
        kitty_group.add(kitty_scrollback_row)
        self._kitty_scrollback_row = kitty_scrollback_row

        kitty_dynamic_opacity_row = Adw.SwitchRow(title="Dynamic Background Opacity")
        kitty_dynamic_opacity_row.set_subtitle("Allow per-window opacity changes in Kitty")
        kitty_dynamic_opacity_row.set_active(get_var("KITTY_DYNAMIC_OPACITY", "true") == "true")
        kitty_dynamic_opacity_row.connect("notify::active", self._on_switch_changed, "KITTY_DYNAMIC_OPACITY")
        self._kitty_dynamic_opacity_actions = RowActions(
            kitty_dynamic_opacity_row,
            on_discard=lambda: self._discard_var("KITTY_DYNAMIC_OPACITY"),
            on_reset=lambda: self._reset_var("KITTY_DYNAMIC_OPACITY"),
        )
        kitty_dynamic_opacity_row.add_suffix(self._kitty_dynamic_opacity_actions.box)
        self._kitty_dynamic_opacity_actions.reorder_first()
        kitty_group.add(kitty_dynamic_opacity_row)
        self._kitty_dynamic_opacity_row = kitty_dynamic_opacity_row

        kitty_audio_bell_row = Adw.SwitchRow(title="Audio Bell")
        kitty_audio_bell_row.set_subtitle("Enable terminal bell in Kitty")
        kitty_audio_bell_row.set_active(get_var("KITTY_AUDIO_BELL", "false") == "true")
        kitty_audio_bell_row.connect("notify::active", self._on_switch_changed, "KITTY_AUDIO_BELL")
        self._kitty_audio_bell_actions = RowActions(
            kitty_audio_bell_row,
            on_discard=lambda: self._discard_var("KITTY_AUDIO_BELL"),
            on_reset=lambda: self._reset_var("KITTY_AUDIO_BELL"),
        )
        kitty_audio_bell_row.add_suffix(self._kitty_audio_bell_actions.box)
        self._kitty_audio_bell_actions.reorder_first()
        kitty_group.add(kitty_audio_bell_row)
        self._kitty_audio_bell_row = kitty_audio_bell_row

        kitty_tab_edge_row = self._make_combo_row(
            var="KITTY_TAB_EDGE",
            title="Tab Bar Edge",
            subtitle="Position of the tab bar in Kitty",
            options=["Bottom", "Top"],
            values=["bottom", "top"],
            actions_attr="_kitty_tab_edge_actions",
            row_attr="_kitty_tab_edge_row",
            values_attr="_kitty_tab_edge_values",
        )
        kitty_group.add(kitty_tab_edge_row)

        kitty_tab_style_row = self._make_combo_row(
            var="KITTY_TAB_STYLE",
            title="Tab Bar Style",
            subtitle="Visual style of the Kitty tab bar",
            options=["Powerline", "Hidden", "Custom"],
            values=["powerline", "hidden", "custom"],
            actions_attr="_kitty_tab_style_actions",
            row_attr="_kitty_tab_style_row",
            values_attr="_kitty_tab_style_values",
        )
        kitty_group.add(kitty_tab_style_row)

        content_box.append(kitty_group)

        # ── Rofi ─────────────────────────────────────────────────────────
        rofi_group = Adw.PreferencesGroup(title="Rofi")

        rofi_font_row = self._make_font_combo(
            var="ROFI_FONT",
            title="Rofi Font",
            subtitle="Font used by the Rofi application launcher",
            actions_attr="_rofi_font_actions",
            row_attr="_rofi_font_row",
            values_attr="_rofi_font_values",
        )
        rofi_group.add(rofi_font_row)

        rofi_font_size_row, rofi_font_size_spin = self._make_spin_row(
            title="Rofi Font Size",
            subtitle="Font size for Rofi (pt)",
            var="ROFI_FONT_SIZE",
            lower=1, upper=200, step=0.5,
            default_val=12.0,
            actions_attr="_rofi_font_size_actions",
            spin_attr="_rofi_font_spin",
            is_int=False,
        )
        rofi_group.add(rofi_font_size_row)
        self._rofi_font_size_row = rofi_font_size_row

        rofi_padding_row, rofi_padding_spin = self._make_spin_row(
            title="Rofi Padding",
            subtitle="Inner padding for Rofi dialog (px)",
            var="ROFI_PADDING",
            lower=0, upper=200, step=1,
            default_val=8,
            actions_attr="_rofi_padding_actions",
            spin_attr="_rofi_padding_spin",
        )
        rofi_group.add(rofi_padding_row)
        self._rofi_padding_row = rofi_padding_row

        rofi_rounding_row, rofi_rounding_spin = self._make_spin_row(
            title="Rofi Rounding",
            subtitle="Corner radius for Rofi windows (px)",
            var="ROFI_ROUNDING",
            lower=0, upper=99, step=1,
            default_val=12,
            actions_attr="_rofi_rounding_actions",
            spin_attr="_rofi_rounding_spin",
        )
        rofi_group.add(rofi_rounding_row)
        self._rofi_rounding_row = rofi_rounding_row

        rofi_border_row, rofi_border_spin = self._make_spin_row(
            title="Rofi Border Size",
            subtitle="Border width for Rofi windows (px)",
            var="ROFI_BORDER_SIZE",
            lower=0, upper=99, step=1,
            default_val=2,
            actions_attr="_rofi_border_actions",
            spin_attr="_rofi_border_spin",
        )
        rofi_group.add(rofi_border_row)
        self._rofi_border_row = rofi_border_row

        rofi_y_offset_row, rofi_y_offset_spin = self._make_spin_row(
            title="Rofi Y Offset",
            subtitle="Vertical offset for Rofi window position (%)",
            var="ROFI_Y_OFFSET",
            lower=0, upper=200, step=1,
            default_val=40,
            actions_attr="_rofi_y_offset_actions",
            spin_attr="_rofi_y_offset_spin",
        )
        rofi_group.add(rofi_y_offset_row)
        self._rofi_y_offset_row = rofi_y_offset_row

        rofi_icon_size_row, rofi_icon_size_spin = self._make_spin_row(
            title="Rofi Icon Size",
            subtitle="Size of app icons in Rofi (px)",
            var="ROFI_ICON_SIZE",
            lower=16, upper=512, step=8,
            default_val=128,
            actions_attr="_rofi_icon_size_actions",
            spin_attr="_rofi_icon_size_spin",
        )
        rofi_group.add(rofi_icon_size_row)
        self._rofi_icon_size_row = rofi_icon_size_row

        rofi_spacing_row, rofi_spacing_spin = self._make_spin_row(
            title="Rofi Spacing",
            subtitle="Spacing between Rofi elements (px)",
            var="ROFI_SPACING",
            lower=0, upper=100, step=1,
            default_val=5,
            actions_attr="_rofi_spacing_actions",
            spin_attr="_rofi_spacing_spin",
        )
        rofi_group.add(rofi_spacing_row)
        self._rofi_spacing_row = rofi_spacing_row

        rofi_input_padding_row, rofi_input_padding_spin = self._make_spin_row(
            title="Rofi Input Padding",
            subtitle="Padding inside the Rofi search bar (px)",
            var="ROFI_INPUT_PADDING",
            lower=0, upper=100, step=1,
            default_val=12,
            actions_attr="_rofi_input_padding_actions",
            spin_attr="_rofi_input_padding_spin",
        )
        rofi_group.add(rofi_input_padding_row)
        self._rofi_input_padding_row = rofi_input_padding_row

        content_box.append(rofi_group)

        self._refresh_managed()
        return toolbar
