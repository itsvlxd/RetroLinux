"""Add/edit dialog for a single layer rule with one or more effects.

Two halves:

1. **Match this layer surface** — a single namespace regex entry.
2. **Apply these effects** — a list of effect rows, each with an
   action dropdown and per-preset argument fields. Add as many effects
   as you want with the "+" button; remove any with the trash icon.

A live preview at the bottom shows the exact config line that will
be written.

The dialog is opened via :meth:`SingletonDialogMixin.present_singleton`,
not constructed directly.
"""

from collections.abc import Callable

from gi.repository import Adw, Gtk
from hyprland_config import LAYER_BOOL_EFFECTS, render_rule_hyprlang, render_rule_lua

from settings.core import config
from settings.core.layer_rules import (
    CUSTOM_PRESET,
    LAYER_ACTION_PRESETS,
    LayerActionField,
    LayerActionPreset,
    LayerEffect,
    LayerRule,
    lookup_preset,
)
from settings.ui import build_preview_group
from settings.ui.dialog import SingletonDialogMixin

_PRESETS_WITH_CUSTOM: tuple[LayerActionPreset, ...] = (*LAYER_ACTION_PRESETS, CUSTOM_PRESET)


def _preview_for(rule: LayerRule) -> str:
    node = rule.to_rule_node()
    if config.is_lua_mode():
        return render_rule_lua(node)
    return render_rule_hyprlang(node).rstrip("\n")


class LayerRuleEditDialog(SingletonDialogMixin, Adw.Dialog):
    """Add/edit dialog for a single ``layerrule`` with one or more effects."""

    def __init__(
        self,
        *,
        rule: LayerRule | None = None,
        on_apply: Callable[[LayerRule], None] | None = None,
    ):
        super().__init__()
        self._is_new = rule is None
        self._on_apply_callback = on_apply

        # Effect rows — each is an ``_EffectRow`` with its own dropdown,
        # argument fields, and delete button.
        self._effect_rows: list[_EffectRow] = []
        self._effects_box: Gtk.Box

        # Single namespace entry
        self._namespace_entry: Adw.EntryRow

        # Live preview label
        self._preview_label: Gtk.Label

        # Pass-through state for name and enabled flag
        self._rule_name: str = ""
        self._rule_enabled: bool = True

        self.set_title("New Layer Rule" if self._is_new else "Edit Layer Rule")
        self.set_content_width(560)
        self.set_content_height(560)

        toolbar = Adw.ToolbarView()

        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: self.close())
        header.pack_start(cancel_btn)

        self._apply_btn = Gtk.Button(label="Apply")
        self._apply_btn.add_css_class("suggested-action")
        self._apply_btn.connect("clicked", self._on_apply)
        self._apply_btn.set_sensitive(False)
        header.pack_end(self._apply_btn)
        toolbar.add_top_bar(header)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(720)
        clamp.set_tightening_threshold(560)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)

        content.append(self._build_name_section())
        content.append(self._build_match_section())
        content.append(self._build_apply_section())
        content.append(self._build_preview_section())

        clamp.set_child(content)
        scrolled.set_child(clamp)
        toolbar.set_content(scrolled)
        self.set_child(toolbar)

        if rule is not None:
            self._load_from_rule(rule)
        else:
            self._add_effect_row(LAYER_ACTION_PRESETS[0])

        self._refresh()

    # ── Section builders ──────────────────────────────────────────────

    def _build_name_section(self) -> Gtk.Widget:
        group = Adw.PreferencesGroup(title="Name (optional)")
        group.set_description(
            "Naming a rule lets you enable / disable it at runtime via "
            "Hyprland's Lua API or hyprctl. Anonymous rules are written "
            "as the compact one-line form."
        )

        self._name_entry = Adw.EntryRow(title="Name")
        self._name_entry.set_text(self._rule_name)
        self._name_entry.connect("changed", self._on_name_changed)
        group.add(self._name_entry)

        self._enabled_row = Adw.SwitchRow(
            title="Enabled",
            subtitle="Uncheck to keep the rule defined but inactive on next reload.",
        )
        self._enabled_row.set_active(self._rule_enabled)
        self._enabled_row.connect("notify::active", self._on_enabled_changed)
        group.add(self._enabled_row)

        return group

    def _build_match_section(self) -> Gtk.Widget:
        group = Adw.PreferencesGroup(title="Match this layer surface")
        group.set_description(
            "Type the layer namespace as a regex. "
            "Common namespaces: waybar, notifications, rofi, mako, dunst, wallpaper."
        )

        self._namespace_entry = Adw.EntryRow(title="Namespace regex")
        self._namespace_entry.set_tooltip_text(
            "Regex matching the layer surface namespace. "
            "Examples: 'waybar', '^(rofi|wofi)$', 'notifications'."
        )
        self._namespace_entry.connect("changed", lambda *_: self._refresh())
        group.add(self._namespace_entry)

        return group

    def _build_apply_section(self) -> Gtk.Widget:
        group = Adw.PreferencesGroup(title="Apply these effects")
        group.set_description(
            "Add one or more effects. Each gets its own action dropdown "
            "and argument fields."
        )

        add_btn = Gtk.Button.new_from_icon_name("list-add-symbolic")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text("Add another effect")
        add_btn.connect("clicked", lambda _b: self._on_add_effect())
        group.set_header_suffix(add_btn)

        self._effects_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self._effects_box.set_margin_top(4)
        group.add(self._effects_box)

        return group

    def _build_preview_section(self) -> Gtk.Widget:
        group, self._preview_label = build_preview_group()
        return group

    # ── Hydration / loading from an existing rule ─────────────────────

    def _load_from_rule(self, rule: LayerRule) -> None:
        self._rule_name = rule.name
        self._rule_enabled = rule.enabled
        if hasattr(self, "_name_entry"):
            self._name_entry.handler_block_by_func(self._on_name_changed)
            self._name_entry.set_text(rule.name)
            self._name_entry.handler_unblock_by_func(self._on_name_changed)
        if hasattr(self, "_enabled_row"):
            self._enabled_row.handler_block_by_func(self._on_enabled_changed)
            self._enabled_row.set_active(rule.enabled)
            self._enabled_row.handler_unblock_by_func(self._on_enabled_changed)
        self._namespace_entry.set_text(rule.namespace)

        for eff in rule.effects:
            preset = lookup_preset(eff.name)
            if preset is CUSTOM_PRESET:
                self._add_effect_row(preset, args_str=eff.full)
            else:
                args_str = "" if eff.name in LAYER_BOOL_EFFECTS else eff.args
                self._add_effect_row(preset, args_str=args_str)
    # ── Effect row management ─────────────────────────────────────────

    def _add_effect_row(self, preset: LayerActionPreset, *, args_str: str = "") -> None:
        row = _EffectRow(
            initial_preset=preset,
            args_str=args_str,
            on_remove=self._on_remove_effect,
            on_changed=self._refresh,
        )
        self._effect_rows.append(row)
        self._effects_box.append(row.widget)

    def _on_add_effect(self) -> None:
        self._add_effect_row(LAYER_ACTION_PRESETS[0])
        self._refresh()

    def _on_remove_effect(self, row: "_EffectRow") -> None:
        self._effect_rows.remove(row)
        self._effects_box.remove(row.widget)
        self._refresh()

    # ── Refresh: preview + apply gating ───────────────────────────────

    def _on_name_changed(self, *_args: object) -> None:
        self._rule_name = self._name_entry.get_text().strip()
        self._refresh()

    def _on_enabled_changed(self, *_args: object) -> None:
        self._rule_enabled = self._enabled_row.get_active()
        self._refresh()

    def _refresh(self) -> None:
        rule = self._build_rule()
        if rule is None:
            has_any = any(
                eff.name.strip()
                for row in self._effect_rows
                for eff in [row.read_effect()]
                if eff.name.strip() or eff.args.strip()
            )
            if not has_any and self._effect_rows:
                self._preview_label.set_text("No effects enabled — toggle at least one on")
            else:
                self._preview_label.set_text("(rule incomplete)")
        else:
            self._preview_label.set_text(_preview_for(rule))
        ok = (
            rule is not None
            and any(
                e.name for e in rule.effects if e.name or (hasattr(e, "full") and e.full.strip())
            )
            and bool(rule.namespace.strip())
        )
        self._apply_btn.set_sensitive(ok)

    def _build_rule(self) -> LayerRule | None:
        effects: list[LayerEffect] = []
        for row in self._effect_rows:
            eff = row.read_effect()
            if not eff.name.strip() and not eff.args.strip():
                continue
            effects.append(eff)

        namespace = self._namespace_entry.get_text().strip()

        if not effects:
            return None

        return LayerRule(
            namespace=namespace,
            effects=effects,
            name=self._rule_name,
            enabled=self._rule_enabled,
        )

    # ── Apply ─────────────────────────────────────────────────────────

    def _on_apply(self, *_args: object) -> None:
        rule = self._build_rule()
        if rule is None or not rule.namespace.strip():
            return
        if self._on_apply_callback is not None:
            self._on_apply_callback(rule)
        self.close()


# ---------------------------------------------------------------------------
# Helper widget: a single effect row
# ---------------------------------------------------------------------------


class _EffectRow:
    """Single effect card: dropdown + trash on top, argument fields below.

    Layout::

        [ PreferencesGroup                     ]
        [   [Dropdown ▼]                 [✕]  ]
        [   [Arg1 field]                      ]
        [   [Arg2 field]                      ]
    """

    def __init__(
        self,
        *,
        initial_preset: LayerActionPreset,
        args_str: str = "",
        on_remove: Callable[["_EffectRow"], None],
        on_changed: Callable[[], None],
    ):
        self._on_remove = on_remove
        self._on_changed = on_changed
        self._preset: LayerActionPreset = initial_preset
        self._arg_widgets: list[Gtk.Widget] = []

        self._group = Adw.PreferencesGroup()

        action_row = Adw.ActionRow()
        action_row.set_title("")

        labels = Gtk.StringList.new([p.label for p in _PRESETS_WITH_CUSTOM])
        self._preset_dropdown = Gtk.DropDown(model=labels)
        self._preset_dropdown.set_valign(Gtk.Align.CENTER)
        self._preset_dropdown.set_size_request(250, -1)
        try:
            initial_idx = _PRESETS_WITH_CUSTOM.index(initial_preset)
        except ValueError:
            initial_idx = 0
        self._preset_dropdown.set_selected(initial_idx)
        self._preset_dropdown.connect("notify::selected", self._on_preset_changed)
        action_row.add_prefix(self._preset_dropdown)

        remove_btn = Gtk.Button.new_from_icon_name("user-trash-symbolic")
        remove_btn.set_valign(Gtk.Align.CENTER)
        remove_btn.add_css_class("flat")
        remove_btn.set_tooltip_text("Remove this effect")
        remove_btn.connect("clicked", lambda _b: self._on_remove(self))
        action_row.add_suffix(remove_btn)

        self._group.add(action_row)
        self._arg_container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._group.add(self._arg_container)
        self._rebuild_args(args_str)

    @property
    def widget(self) -> Gtk.Widget:
        return self._group

    def read_effect(self) -> LayerEffect:
        if self._preset is CUSTOM_PRESET:
            values = self._read_arg_values()
            full = values[0].strip() if values else ""
            name, _, args = full.partition(" ")
            return LayerEffect(name=name.strip(), args=args.strip())
        if not self._preset.fields and self._preset is not CUSTOM_PRESET:
            sw = self._arg_widgets[0] if self._arg_widgets else None
            if isinstance(sw, Adw.SwitchRow) and not sw.get_active():
                return LayerEffect(name="", args="")
            return LayerEffect(name=self._preset.id, args="on")
        args = self._preset.format(self._read_arg_values())
        return LayerEffect(name=self._preset.id, args=args)

    def _on_preset_changed(self, *_args: object) -> None:
        idx = self._preset_dropdown.get_selected()
        if idx < 0 or idx >= len(_PRESETS_WITH_CUSTOM):
            return
        new_preset = _PRESETS_WITH_CUSTOM[idx]
        if new_preset is self._preset:
            return
        self._preset = new_preset
        self._rebuild_args()
        self._on_changed()

    def _rebuild_args(self, args_str: str = "") -> None:
        child = self._arg_container.get_first_child()
        while child is not None:
            self._arg_container.remove(child)
            child = self._arg_container.get_first_child()
        self._arg_widgets = []

        if not self._preset.fields:
            sw = Adw.SwitchRow(
                title="Enabled",
                subtitle="Uncheck to disable this effect.",
            )
            active = args_str.strip().lower() in ("on", "true", "yes", "1", "") if args_str else True
            sw.set_active(active)
            sw.connect("notify::active", lambda *_: self._on_changed())
            self._arg_widgets.append(sw)
            self._arg_container.append(sw)
            return

        if self._preset is CUSTOM_PRESET:
            initial_values = [args_str] if args_str else [""]
        else:
            parsed = self._preset.parse_args(args_str) if args_str else None
            initial_values = (
                parsed if parsed is not None else [f.default for f in self._preset.fields]
            )

        for field, initial in zip(self._preset.fields, initial_values, strict=False):
            widget = self._build_arg_widget(field, initial)
            self._arg_widgets.append(widget)
            self._arg_container.append(widget)

    def _build_arg_widget(self, field: LayerActionField, initial: str) -> Gtk.Widget:
        if field.kind == "number":
            row = Adw.SpinRow.new_with_range(field.min_value, field.max_value, field.step)
            row.set_title(field.label)
            if field.hint:
                row.set_subtitle(field.hint)
            row.set_digits(field.digits)
            try:
                row.set_value(float(initial) if initial else float(field.default or "0"))
            except ValueError:
                row.set_value(float(field.default or "0"))
            row.connect("notify::value", lambda *_: self._on_changed())
            return row

        if field.kind == "bool":
            row = Adw.SwitchRow(title=field.label)
            if field.hint:
                row.set_subtitle(field.hint)
            row.set_active(initial.strip().lower() in {"1", "true", "yes", "on"})
            row.connect("notify::active", lambda *_: self._on_changed())
            return row

        row = Adw.EntryRow(title=field.label)
        if field.hint:
            row.set_tooltip_text(field.hint)
        row.set_text(initial)
        row.connect("changed", lambda *_: self._on_changed())
        return row

    def _read_arg_values(self) -> list[str]:
        result: list[str] = []
        for w in self._arg_widgets:
            if isinstance(w, Adw.SpinRow):
                digits = w.get_digits()
                val = w.get_value()
                if digits == 0:
                    result.append(str(int(val)))
                else:
                    result.append(f"{val:.{digits}f}")
            elif isinstance(w, Adw.SwitchRow):
                result.append("on" if w.get_active() else "off")
            elif isinstance(w, Adw.EntryRow):
                result.append(w.get_text())
            else:
                result.append("")
        return result


__all__ = ["LayerRuleEditDialog"]
