"""Add/edit dialog for a single window rule.

Two halves:

1. **Match windows where…** — a list of matcher rows, each with a
   key dropdown (class, title, xwayland, …) and a value entry. Plus
   a "Pick from open window" button that auto-fills class regex
   from a currently-running window.
2. **Apply these effects** — a list of effect rows, each with an
   action dropdown and per-preset argument fields. Add as many effects
   as you want with the "+" button; remove any with the trash icon.

A live preview at the bottom shows the exact config line that will
be written.

The dialog is opened via :meth:`SingletonDialogMixin.present_singleton`,
not constructed directly.
"""

import re
from collections.abc import Callable

from gi.repository import Adw, Gtk
from hyprland_config import render_rule_hyprlang, render_rule_lua
from hyprland_socket import Window

from settings.core import config
from settings.core.window_rules import (
    ACTION_PRESETS,
    CUSTOM_MATCHER_KIND,
    CUSTOM_PRESET,
    MATCHER_KINDS,
    MATCHER_KINDS_BY_KEY,
    RAW_KEY,
    ActionField,
    ActionPreset,
    Effect,
    Matcher,
    MatcherKind,
    WindowRule,
    lookup_matcher_kind,
    lookup_preset,
)
from settings.ui import build_preview_group
from settings.ui.dialog import SingletonDialogMixin
from settings.ui.window_picker import WindowPickerDialog

_PRESETS_WITH_CUSTOM: tuple[ActionPreset, ...] = (*ACTION_PRESETS, CUSTOM_PRESET)


def _escape_regex(value: str) -> str:
    """Wrap a plain string into an exact-match RE2 regex.

    Used by the "Pick from open window" path: a window's class is
    typically a fixed identifier (``firefox``, ``org.kde.dolphin``),
    so anchoring it as ``^(escaped)$`` matches that one app and
    nothing else. Users can loosen the regex afterwards if they want
    to match a family of classes.
    """
    return f"^({re.escape(value)})$"


def _preview_for(rule: WindowRule) -> str:
    """Render *rule* in the active mode's syntax for the dialog preview.

    Builds the structured :class:`hyprland_config.Rule` node and hands
    it to the right language-specific renderer — Lua mode picks
    :func:`render_rule_lua` (one ``hl.window_rule({…})`` call),
    Hyprlang mode picks :func:`render_rule_hyprlang` (block when
    name/disabled, single-line otherwise). Both routes match what
    would actually hit disk so the preview is byte-faithful.
    """
    node = rule.to_rule_node()
    if config.is_lua_mode():
        return render_rule_lua(node)
    return render_rule_hyprlang(node).rstrip("\n")


class WindowRuleEditDialog(SingletonDialogMixin, Adw.Dialog):
    """Add/edit dialog for a single window rule with one or more effects."""

    def __init__(
        self,
        *,
        rule: WindowRule | None = None,
        on_apply: Callable[[WindowRule], None] | None = None,
    ):
        super().__init__()
        self._is_new = rule is None
        self._on_apply_callback = on_apply

        # Matcher rows are tracked imperatively so Add/Remove and the
        # preview rebuild can find each row's current values.
        self._matcher_rows: list[_MatcherRow] = []
        self._matchers_listbox: Gtk.ListBox

        # Effect rows — each is an ``_EffectRow`` with its own dropdown,
        # argument fields, and delete button. Users can add multiple.
        self._effect_rows: list[_EffectRow] = []
        self._effects_listbox: Gtk.ListBox

        # Live-preview label updated on every form change.
        self._preview_label: Gtk.Label

        # Pass-through state for the rule's optional name and enabled flag.
        self._rule_name: str = ""
        self._rule_enabled: bool = True

        self.set_title("New Window Rule" if self._is_new else "Edit Window Rule")
        self.set_content_width(560)
        self.set_content_height(640)

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

        # Hydrate from the rule being edited (or seed with defaults).
        if rule is not None:
            self._load_from_rule(rule)
        else:
            self._add_matcher_row(MATCHER_KINDS[0])
            self._add_effect_row(ACTION_PRESETS[0])

        self._refresh()

    # ── Section builders ──────────────────────────────────────────────

    def _build_name_section(self) -> Gtk.Widget:
        """Optional ``Name`` row plus disabled toggle for block-form rules.

        A name promotes the rule from anonymous to named — Hyprland's
        Lua API and ``hyprctl`` can then reference it for dynamic
        enable/disable. Leaving the name blank keeps the rule
        anonymous and emits the compact single-line syntax.
        """
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
        """The 'Match windows where…' group with matcher rows + add buttons."""
        group = Adw.PreferencesGroup(title="Match windows where…")
        group.set_description(
            "Add one or more conditions. Hyprland matches windows where ALL conditions apply."
        )

        # Header-suffix buttons: pick-from-window (the high-leverage
        # shortcut) and add-condition (the manual fallback).
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

        pick_btn = Gtk.Button.new_from_icon_name("system-search-symbolic")
        pick_btn.set_valign(Gtk.Align.CENTER)
        pick_btn.add_css_class("flat")
        pick_btn.set_tooltip_text("Pick from an open window")
        pick_btn.connect("clicked", lambda _b: self._on_pick_window())
        button_box.append(pick_btn)

        add_btn = Gtk.Button.new_from_icon_name("list-add-symbolic")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text("Add a condition")
        add_btn.connect("clicked", lambda _b: self._on_add_matcher())
        button_box.append(add_btn)

        group.set_header_suffix(button_box)

        self._matchers_listbox = Gtk.ListBox()
        self._matchers_listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._matchers_listbox.add_css_class("boxed-list")
        group.add(self._matchers_listbox)

        return group

    def _build_apply_section(self) -> Gtk.Widget:
        """The 'Apply these effects' group with effect cards + add button."""
        group = Adw.PreferencesGroup(title="Apply these effects")
        group.set_description(
            "Add one or more effects. Each effect is a card with its own "
            "dropdown and argument fields."
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
        """The bottom preview: shows the actual config line that will be written."""
        group, self._preview_label = build_preview_group()
        return group

    # ── Hydration / loading from an existing rule ─────────────────────

    def _load_from_rule(self, rule: WindowRule) -> None:
        """Populate widgets from an existing ``WindowRule`` for editing."""
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
        # Matchers
        if not rule.matchers:
            self._add_matcher_row(MATCHER_KINDS[0])
        for m in rule.matchers:
            kind = lookup_matcher_kind(m.key)
            if kind is CUSTOM_MATCHER_KIND and m.key != RAW_KEY:
                value = f"match:{m.key} {m.value}"
            else:
                value = m.value
            self._add_matcher_row(kind, value=value, original_key=m.key)
        # Effects — create one row per effect
        for eff in rule.effects:
            preset = lookup_preset(eff.name)
            if preset is CUSTOM_PRESET:
                self._add_effect_row(preset, args_str=eff.full)
            else:
                self._add_effect_row(preset, args_str=eff.args)
    # ── Effect row management ─────────────────────────────────────────

    def _add_effect_row(self, preset: ActionPreset, *, args_str: str = "") -> None:
        """Append a new effect row to the list."""
        row = _EffectRow(
            initial_preset=preset,
            args_str=args_str,
            on_remove=self._on_remove_effect,
            on_changed=self._refresh,
        )
        self._effect_rows.append(row)
        self._effects_box.append(row.widget)

    def _on_add_effect(self) -> None:
        self._add_effect_row(ACTION_PRESETS[0])
        self._refresh()

    def _on_remove_effect(self, row: "_EffectRow") -> None:
        self._effect_rows.remove(row)
        self._effects_box.remove(row.widget)
        self._refresh()

    # ── Matcher row management ────────────────────────────────────────

    def _add_matcher_row(
        self,
        kind: MatcherKind,
        *,
        value: str = "",
        original_key: str = "",
    ) -> None:
        """Append a new matcher row to the list."""
        row = _MatcherRow(
            initial_kind=kind,
            initial_value=value,
            original_key=original_key or kind.key,
            on_remove=self._on_remove_matcher,
            on_changed=self._refresh,
        )
        self._matcher_rows.append(row)
        self._matchers_listbox.append(row.widget)

    def _on_add_matcher(self) -> None:
        self._add_matcher_row(MATCHER_KINDS[0])
        self._refresh()

    def _on_remove_matcher(self, row: "_MatcherRow") -> None:
        if len(self._matcher_rows) <= 1:
            self._reset_last_matcher_row()
            self._refresh()
            return
        self._matcher_rows.remove(row)
        self._matchers_listbox.remove(row.widget)
        self._refresh()

    def _reset_last_matcher_row(self) -> None:
        if not self._matcher_rows:
            self._add_matcher_row(MATCHER_KINDS[0])
            return
        last = self._matcher_rows[0]
        last.set_kind(MATCHER_KINDS[0])
        last.set_value("")

    # ── Pick-from-window ──────────────────────────────────────────────

    def _on_pick_window(self) -> None:
        def on_pick(window: Window) -> None:
            self._apply_picked_window(window)

        WindowPickerDialog.present_singleton(self, on_pick=on_pick)

    def _apply_picked_window(self, window: Window) -> None:
        for row in list(self._matcher_rows):
            self._matchers_listbox.remove(row.widget)
        self._matcher_rows.clear()

        if window.class_name:
            self._add_matcher_row(
                MATCHER_KINDS_BY_KEY["class"],
                value=_escape_regex(window.class_name),
            )
        elif window.title:
            self._add_matcher_row(
                MATCHER_KINDS_BY_KEY["title"],
                value=_escape_regex(window.title),
            )
        else:
            self._add_matcher_row(MATCHER_KINDS[0])

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
                effect.name.strip()
                for row in self._effect_rows
                for effect in [row.read_effect()]
                if effect.name.strip() or effect.args.strip()
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
            and any(m.value.strip() for m in rule.matchers)
        )
        self._apply_btn.set_sensitive(ok)

    def _build_rule(self) -> WindowRule | None:
        """Snapshot the current dialog state into a ``WindowRule``."""
        effects: list[Effect] = []
        for row in self._effect_rows:
            eff = row.read_effect()
            if not eff.name.strip() and not eff.args.strip():
                continue
            effects.append(eff)

        matchers: list[Matcher] = []
        for row in self._matcher_rows:
            matcher = row.read_matcher()
            if not matcher.value.strip():
                continue
            matchers.append(matcher)

        if not effects:
            return None

        return WindowRule(
            matchers=matchers,
            effects=effects,
            name=self._rule_name,
            enabled=self._rule_enabled,
        )

    # ── Apply ─────────────────────────────────────────────────────────

    def _on_apply(self, *_args: object) -> None:
        rule = self._build_rule()
        if rule is None or not rule.matchers:
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

    The preset dropdown and trash icon are in an ``Adw.ActionRow`` at the
    top. Argument fields are ``Adw.EntryRow`` / ``Adw.SpinRow`` children
    of the group, stacked below the action row.
    """

    def __init__(
        self,
        *,
        initial_preset: ActionPreset,
        args_str: str = "",
        on_remove: Callable[["_EffectRow"], None],
        on_changed: Callable[[], None],
    ):
        self._on_remove = on_remove
        self._on_changed = on_changed
        self._preset: ActionPreset = initial_preset
        self._arg_widgets: list[Gtk.Widget] = []

        self._group = Adw.PreferencesGroup()

        # Top row: dropdown + trash
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

    def read_effect(self) -> Effect:
        if self._preset is CUSTOM_PRESET:
            values = self._read_arg_values()
            full = values[0].strip() if values else ""
            name, _, args = full.partition(" ")
            return Effect(name=name.strip(), args=args.strip())
        if not self._preset.fields and self._preset is not CUSTOM_PRESET:
            # Boolean preset — use the switch state
            switch = self._arg_widgets[0] if self._arg_widgets else None
            if isinstance(switch, Adw.SwitchRow) and not switch.get_active():
                return Effect(name="", args="")
            return Effect(name=self._preset.id, args="on")
        args = self._preset.format(self._read_arg_values())
        return Effect(name=self._preset.id, args=args)

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
        """Remove old arg rows and build new ones for the current preset."""
        child = self._arg_container.get_first_child()
        while child is not None:
            self._arg_container.remove(child)
            child = self._arg_container.get_first_child()
        self._arg_widgets = []

        if not self._preset.fields:
            # Boolean preset — show a toggle instead of inline fields
            switch_row = Adw.SwitchRow(
                title="Enabled",
                subtitle="Uncheck to disable this effect.",
            )
            switch_row.set_active(True)
            # If args_str contains "on" (the canonical value for boolean effects)
            # or the rule was loaded with the effect active, keep it checked.
            active = args_str.strip().lower() in ("on", "true", "yes", "1", "") if args_str else True
            switch_row.set_active(active)
            switch_row.connect("notify::active", lambda *_: self._on_changed())
            self._arg_widgets.append(switch_row)
            self._arg_container.append(switch_row)
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

    def _build_arg_widget(self, field: ActionField, initial: str) -> Gtk.Widget:
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

        if field.kind == "choice":
            choices = list(field.choices)
            row = Adw.ActionRow(title=field.label)
            if field.hint:
                row.set_subtitle(field.hint)
            model = Gtk.StringList.new(choices)
            dropdown = Gtk.DropDown(model=model)
            dropdown.set_valign(Gtk.Align.CENTER)
            init = initial or field.default
            try:
                idx = choices.index(init) if init in choices else 0
            except (ValueError, IndexError):
                idx = 0
            dropdown.set_selected(idx)
            dropdown.connect("notify::selected", lambda *_: self._on_changed())
            row.add_suffix(dropdown)
            row._dropdown = dropdown
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
            elif isinstance(w, Adw.EntryRow):
                result.append(w.get_text())
            elif isinstance(w, Adw.SwitchRow):
                result.append("true" if w.get_active() else "false")
            elif isinstance(w, Adw.ActionRow):
                dd = getattr(w, '_dropdown', None)
                if dd is not None:
                    idx = dd.get_selected()
                    model = dd.get_model()
                    if 0 <= idx < len(model):
                        result.append(model[idx].get_string())
                    else:
                        result.append("")
                else:
                    result.append("")
            else:
                result.append("")
        return result


# ---------------------------------------------------------------------------
# Helper widget: a single matcher row
# ---------------------------------------------------------------------------


class _MatcherRow:
    """Single matcher row: dropdown of keys + value entry + remove button.

    Encapsulates the kind/key/value tri-state because the value widget
    type changes when the kind changes (regex/text → ``Gtk.Entry``,
    bool → ``Gtk.Switch``). Each row owns its widgets and exposes a
    :meth:`read_matcher` that returns the current ``Matcher`` snapshot.
    """

    # Build a dropdown model that is the catalog plus a Custom entry
    # at the end. Same shape pattern as the action dropdown so future
    # plugin matchers can land in Custom without UI churn.
    _KINDS_WITH_CUSTOM: tuple[MatcherKind, ...] = (*MATCHER_KINDS, CUSTOM_MATCHER_KIND)

    def __init__(
        self,
        *,
        initial_kind: MatcherKind,
        initial_value: str,
        original_key: str,
        on_remove: Callable[["_MatcherRow"], None],
        on_changed: Callable[[], None],
    ):
        self._on_remove = on_remove
        self._on_changed = on_changed
        # ``_original_key`` only matters for matchers we couldn't
        # parse: when the user is editing a token like
        # ``plugin:foo:bar:baz`` (which is RAW because the parser
        # didn't strip the leading key), we want to preserve the raw
        # text on save — the dropdown stays on "Custom" and the value
        # field carries the full token.
        self._original_key = original_key
        self._kind: MatcherKind = initial_kind
        self._value_widget: Gtk.Widget

        self._row = Adw.ActionRow()
        self._row.set_title("")  # title space used by the kind dropdown
        self._row.add_css_class("matcher-row")

        # Kind dropdown — narrow column on the left so the value field
        # gets the room. Using ``Gtk.DropDown`` directly (not ComboRow)
        # because we want it inline with the other suffixes, not as the
        # row's primary content.
        labels = Gtk.StringList.new([k.label for k in _MatcherRow._KINDS_WITH_CUSTOM])
        self._kind_dropdown = Gtk.DropDown(model=labels)
        self._kind_dropdown.set_valign(Gtk.Align.CENTER)
        self._kind_dropdown.set_size_request(180, -1)
        try:
            initial_idx = _MatcherRow._KINDS_WITH_CUSTOM.index(initial_kind)
        except ValueError:
            initial_idx = len(_MatcherRow._KINDS_WITH_CUSTOM) - 1
        self._kind_dropdown.set_selected(initial_idx)
        self._kind_dropdown.connect("notify::selected", self._on_kind_changed)
        self._row.add_prefix(self._kind_dropdown)

        # Value widget — built fresh on every kind change because the
        # widget *type* depends on the kind (entry vs. switch).
        self._value_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self._value_box.set_hexpand(True)
        self._value_box.set_valign(Gtk.Align.CENTER)
        self._value_widget = self._build_value_widget(initial_kind, initial_value)
        self._value_box.append(self._value_widget)
        self._row.add_suffix(self._value_box)

        # Remove button — small flat icon, last position so the user's
        # eye lands on the value field first.
        remove_btn = Gtk.Button.new_from_icon_name("user-trash-symbolic")
        remove_btn.set_valign(Gtk.Align.CENTER)
        remove_btn.add_css_class("flat")
        remove_btn.set_tooltip_text("Remove this condition")
        remove_btn.connect("clicked", lambda _b: self._on_remove(self))
        self._row.add_suffix(remove_btn)

        # v3 Hyprland encodes regex negation as a ``negative:`` prefix
        # on the value (e.g. ``match:class negative:firefox``), not as
        # a separate flag on the matcher. Users can type that prefix
        # manually; surfacing a checkbox is a future polish item.

    @property
    def widget(self) -> Gtk.Widget:
        return self._row

    # ── Public mutators (used by the parent dialog's reset path) ──

    def set_kind(self, kind: MatcherKind) -> None:
        try:
            idx = _MatcherRow._KINDS_WITH_CUSTOM.index(kind)
        except ValueError:
            idx = len(_MatcherRow._KINDS_WITH_CUSTOM) - 1
        self._kind_dropdown.handler_block_by_func(self._on_kind_changed)
        self._kind_dropdown.set_selected(idx)
        self._kind_dropdown.handler_unblock_by_func(self._on_kind_changed)
        self._swap_value_widget(kind, "")

    def set_value(self, value: str) -> None:
        if isinstance(self._value_widget, Gtk.Entry):
            self._value_widget.set_text(value)
        elif isinstance(self._value_widget, Gtk.Switch):
            # v3 boolean matchers use ``true``/``false`` (also accepts
            # ``yes``/``no``/``1``/``0``); we canonicalise to ``true``.
            self._value_widget.set_active(value.strip().lower() in {"1", "true", "yes", "on"})

    # ── Reading current state ──

    def read_matcher(self) -> Matcher:
        """Return a ``Matcher`` snapshot of the current widget state."""
        if self._kind is CUSTOM_MATCHER_KIND:
            text = (
                self._value_widget.get_text() if isinstance(self._value_widget, Gtk.Entry) else ""
            )
            # Custom holds opaque text — round-trip as a RAW token so
            # whatever the user typed (``match:foo bar``, plugin
            # tokens, …) survives serialization byte-for-byte.
            return Matcher(key=RAW_KEY, value=text)

        if self._kind.value_kind == "bool":
            value = (
                "true"
                if (isinstance(self._value_widget, Gtk.Switch) and self._value_widget.get_active())
                else "false"
            )
            return Matcher(key=self._kind.key, value=value)

        text = self._value_widget.get_text() if isinstance(self._value_widget, Gtk.Entry) else ""
        return Matcher(key=self._kind.key, value=text)

    # ── Internal: kind change rebuilds the value widget ──

    def _on_kind_changed(self, *_args: object) -> None:
        idx = self._kind_dropdown.get_selected()
        if idx < 0 or idx >= len(_MatcherRow._KINDS_WITH_CUSTOM):
            return
        new_kind = _MatcherRow._KINDS_WITH_CUSTOM[idx]
        if new_kind is self._kind:
            return
        # Carry the existing text across kind changes — switching
        # between class/title both keep the regex value, which is
        # what the user usually wants.
        carry = ""
        if isinstance(self._value_widget, Gtk.Entry):
            carry = self._value_widget.get_text()
        elif isinstance(self._value_widget, Gtk.Switch):
            carry = "true" if self._value_widget.get_active() else "false"
        self._swap_value_widget(new_kind, carry)
        self._on_changed()

    def _swap_value_widget(self, kind: MatcherKind, initial_value: str) -> None:
        # Drop the old widget and replace with one matching the new kind.
        self._value_box.remove(self._value_widget)
        self._value_widget = self._build_value_widget(kind, initial_value)
        self._value_box.append(self._value_widget)
        self._kind = kind

    def _build_value_widget(self, kind: MatcherKind, initial_value: str) -> Gtk.Widget:
        if kind.value_kind == "bool":
            switch = Gtk.Switch()
            switch.set_valign(Gtk.Align.CENTER)
            # v3 accepts ``true``/``false``/``yes``/``no``/``1``/``0``;
            # we canonicalise to ``true``/``false`` on output.
            switch.set_active(initial_value.strip().lower() in {"1", "true", "yes", "on"})
            switch.connect("notify::active", lambda *_: self._on_changed())
            return switch

        entry = Gtk.Entry()
        entry.set_hexpand(True)
        entry.set_valign(Gtk.Align.CENTER)
        if kind.placeholder:
            entry.set_placeholder_text(kind.placeholder)
        entry.set_text(initial_value)
        entry.connect("changed", lambda *_: self._on_changed())
        return entry


__all__ = ["WindowRuleEditDialog"]
