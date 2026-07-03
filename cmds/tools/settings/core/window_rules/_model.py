"""Data shapes and catalogs for v3 window rules.

Holds the parsed-rule classes (:class:`Matcher`, :class:`WindowRule`),
the immutable v3 keyword/effect/matcher constants, and the curated
presentation catalogs (:data:`ACTION_PRESETS`, :data:`MATCHER_KINDS`)
used by the rule-edit dialog.

This module deliberately has no parsing or runtime-dispatch logic —
those live in :mod:`._parse` and :mod:`._runtime` respectively. Keeping
the data types in their own module lets the catalogs (which are
hundreds of lines of static config) coexist with the dataclasses
without dragging the parser or the IPC layer along.
"""

from dataclasses import dataclass
from typing import Literal

from hyprland_config import (
    ANIM_FLAT,
    V3_BOOL_EFFECTS,
    WINDOWRULE_V3_VERSION,
    Rule,
    parse_version,
    render_rule_hyprlang,
)

from settings.constants import APPLICATION_ID
from settings.core import config

# All known animation style names from the Hyprland animation tree.
_ANIMATION_STYLES: tuple[str, ...] = tuple(
    sorted({s for _, _, _, styles in ANIM_FLAT for s in styles})
)

def _predates_v3_windowrule(version: str) -> bool:
    """True when *version* is older than Hyprland adopted v3 windowrule syntax.

    Below 0.53 the compositor only understands ``windowrulev2 = effect,
    class:regex`` (effect-first); pushing v3 ``match:`` syntax is
    rejected as "Invalid rulev2 found".
    """
    return parse_version(version) < WINDOWRULE_V3_VERSION


# Retro Settings's own application id — the value Hyprland reports as ``class``
# for our window. Used by :func:`matches_settings` to gate live-apply
# behind a confirmation dialog when a user-authored rule would target
# the editor itself (e.g. floating or fading the running editor mid-edit).
RETRO_SETTINGS_APP_ID: str = APPLICATION_ID

# Both keywords accepted on read. Output is always v3 ``windowrule``.
# Legacy ``windowrulev2`` lines auto-migrate (see :mod:`._migrate`).
WINDOW_RULE_KEYWORDS: tuple[str, ...] = (
    config.KEYWORD_WINDOWRULE,
    config.KEYWORD_WINDOWRULEV2,
)

# Sentinel matcher key for opaque tokens — anything in the matcher slot
# that doesn't fit the v3 ``match:KEY VALUE`` shape (usually a custom
# token someone pasted in) is round-tripped under this key with the
# raw text in ``value``.
RAW_KEY: str = "_raw"


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class Matcher:
    """A single ``match:KEY VALUE`` clause.

    Negation in v3 is encoded by prefixing the *value* with
    ``negative:`` (e.g. ``match:class negative:firefox``). We keep that
    in the value field rather than introducing a separate negated flag
    so byte-for-byte round-trips work even for unusual prefixes the
    parser doesn't introspect.
    """

    key: str
    value: str

    def __str__(self) -> str:
        """Serialize as ``match:KEY VALUE`` (or raw text for RAW_KEY)."""
        if self.key == RAW_KEY:
            return self.value
        return f"match:{self.key} {self.value}"


@dataclass(slots=True)
class Effect:
    """A single ``EFFECT [ARGS]`` clause inside a windowrule.

    Multi-effect block-form rules (``windowrule { match:class kitty;
    border_size = 5; no_blur = on }``) become one :class:`WindowRule`
    with several :class:`Effect` entries; single-line rules collapse
    to a one-element list.
    """

    name: str
    args: str = ""

    @property
    def full(self) -> str:
        """Serialize as ``name [args]`` with auto-``on`` for v3 booleans.

        Hyprland 0.53+ rejects bare boolean effects, so the empty-args
        case fills in ``on`` for any name in :data:`V3_BOOL_EFFECTS`.
        """
        args = self.args.strip()
        if not args and self.name in V3_BOOL_EFFECTS:
            args = "on"
        return f"{self.name} {args}" if args else self.name


@dataclass(slots=True)
class WindowRule:
    """A v3 window rule: matchers plus one or more effects, optionally named.

    Hyprland's special-category form (``windowrule { name = X;
    match:K = V; e1 = …; e2 = … }``) bundles several effects under a
    single name; single-line rules (``windowrule = match:K V, EFFECT
    ARGS``) carry exactly one effect and no name. Both shapes land in
    this dataclass — the serializer picks block vs. single-line at
    :meth:`to_line` time based on whether *name*, *enabled*, or a
    multi-effect list demand the block form (Hyprland rejects
    ``name:``/``enable:`` tokens in the single-line handler).
    """

    matchers: list[Matcher]
    effects: list[Effect]
    # Empty when the rule is anonymous. Naming a rule lets Hyprland's
    # Lua API / ``hyprctl`` reference it for dynamic enable/disable.
    name: str = ""
    # False when the rule is defined-but-inactive (``enable = 0`` in
    # the source block). Only meaningful for named rules; anonymous
    # rules can't be toggled at runtime so the flag round-trips but
    # has no UI affordance.
    enabled: bool = True

    # -- Single-effect compatibility shims ---------------------------------
    # The dialog, runtime, and a chunk of the test suite predate the
    # multi-effect refactor and reach for ``effect_name`` / ``effect_args``
    # directly. These read the *first* effect and let single-effect
    # callers keep working unchanged; multi-effect-aware sites should
    # iterate :attr:`effects` instead.

    @property
    def effect_name(self) -> str:
        return self.effects[0].name if self.effects else ""

    @property
    def effect_args(self) -> str:
        return self.effects[0].args if self.effects else ""

    @property
    def effect_full(self) -> str:
        return self.effects[0].full if self.effects else ""

    def body(self) -> str:
        """Serialize the v3 single-line value half of the rule.

        Returns ``match:..., effect ...`` — i.e. everything that would
        come after ``windowrule = ``. Live-apply via ``hypr.keyword``
        wants exactly this; the keyword prefix is supplied separately.
        Matchers come before effects by convention; Hyprland accepts
        either order but match-first reads more naturally.

        :attr:`name` and the disabled flag are intentionally omitted
        because Hyprland's single-line ``handleWindowrule`` rejects
        them. Use :meth:`to_line` for the on-disk form that switches
        to block when those fields demand it.
        """
        parts = [str(m) for m in self.matchers]
        parts.extend(e.full for e in self.effects)
        return ", ".join(parts)

    def to_rule_node(self) -> Rule:
        """Build the equivalent library :class:`hyprland_config.Rule` node.

        Used for previews and writers that consume structured Rule
        nodes — the language-specific serializers
        (:func:`hyprland_config.render_rule_hyprlang`,
        :func:`hyprland_config.render_rule_lua`) take a Rule and pick
        the right shape (block / single-line / Lua table) themselves.
        """
        return Rule(
            raw="",
            kind=config.KEYWORD_WINDOWRULE,
            name=self.name,
            enabled=self.enabled,
            matchers=[(m.key, m.value) for m in self.matchers if m.key != RAW_KEY],
            effects=[(e.name, e.args) for e in self.effects],
        )

    def to_line(self, version: str | None = None) -> str:
        """Serialize as the on-disk form for *version*.

        Hyprland 0.53+ accepts the v3 grammar: anonymous rules emit as
        compact single-line, named/disabled ones as a ``windowrule { … }``
        block (the single-line handler rejects ``name``/``enable``).
        Below 0.53 the grammar is effect-first (``windowrulev2 = float,
        class:^(x)$``), one line per effect, with no named/disabled
        equivalent; that path delegates to
        :func:`hyprland_config.render_rule_hyprlang` so the grammar lives
        in one place. ``None`` (the default, used for identity keys)
        always emits v3.
        """
        if version is not None and _predates_v3_windowrule(version):
            # ``RAW_KEY`` opaque tokens get dropped here; they don't
            # translate to pre-v3 grammar anyway.
            return render_rule_hyprlang(self.to_rule_node(), version).rstrip("\n")
        needs_block = bool(self.name) or not self.enabled
        if needs_block:
            return self._to_block()
        return f"{config.KEYWORD_WINDOWRULE} = {self.body()}"

    def _to_block(self) -> str:
        """Serialize as a multi-line ``windowrule { … }`` block."""
        lines = [f"{config.KEYWORD_WINDOWRULE} {{"]
        if self.name:
            lines.append(f"    name = {self.name}")
        if not self.enabled:
            lines.append("    enable = 0")
        for m in self.matchers:
            if m.key == RAW_KEY:
                # No block-form equivalent for raw tokens — keep them as a
                # comment so the user can fix them by hand rather than
                # silently dropping content.
                lines.append(f"    # raw: {m.value}")
            else:
                lines.append(f"    match:{m.key} = {m.value}")
        for e in self.effects:
            args = e.args.strip()
            if not args and e.name in V3_BOOL_EFFECTS:
                args = "on"
            lines.append(f"    {e.name} = {args}" if args else f"    {e.name} =")
        lines.append("}")
        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Action catalog (for the UI's structured editor)
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class ActionField:
    """A single argument field for an :class:`ActionPreset`."""

    label: str
    placeholder: str = ""
    hint: str = ""
    kind: Literal["text", "number", "choice"] = "text"
    digits: int = 2
    min_value: float = 0.0
    max_value: float = 9999.0
    step: float = 1.0
    default: str = ""
    choices: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class ActionPreset:
    """A pre-canned v3 effect with a friendly label and zero-or-more args.

    ``id`` doubles as the v3 effect name and the dropdown machine
    value. The dialog asks the preset to ``format(values)`` when the
    user clicks Apply; ``parse_args(args)`` runs in reverse when
    re-opening an existing rule.

    Boolean presets (``id`` in :data:`V3_BOOL_EFFECTS`) have no fields
    — they always emit ``<id> on``. The serializer adds the ``on``;
    the preset just has ``fields=()`` to signal "no UI args."
    """

    id: str
    label: str
    description: str
    fields: tuple[ActionField, ...] = ()
    override_fields: bool = False

    def format(self, values: list[str]) -> str:
        """Build the effect args string from user-supplied field values."""
        cleaned = [v.strip() for v in values]
        if self.override_fields:
            cleaned = [f"{v} override" if v else "" for v in cleaned]
        while cleaned and not cleaned[-1]:
            cleaned.pop()
        return " ".join(cleaned)

    def parse_args(self, args_str: str) -> list[str] | None:
        """Try to extract field values from the args portion of an effect.

        Always succeeds (returns the split args, padded to
        ``len(fields)``) — there's no preset-mismatch concept now
        that an effect's ``id`` is the leading token of the line.
        """
        args = args_str.strip().split() if args_str.strip() else []
        if self.override_fields:
            args = [a for i, a in enumerate(args) if i % 2 == 0]
        while len(args) < len(self.fields):
            args.append("")
        return args


# Curated, ordered set of "common" v3 effects. Boolean-only effects
# show up with ``fields=()`` — picking them auto-emits ``<id> on``.
ACTION_PRESETS: tuple[ActionPreset, ...] = (
    ActionPreset(
        id="float",
        label="Float window",
        description="Open the window detached from the tiling layout.",
    ),
    ActionPreset(
        id="tile",
        label="Tile window",
        description="Force the window into the tiling layout.",
    ),
    ActionPreset(
        id="pin",
        label="Pin to all workspaces",
        description="Window stays visible across workspace switches (floating only).",
    ),
    ActionPreset(
        id="center",
        label="Center on monitor",
        description="Center the window on its monitor (floating only).",
    ),
    ActionPreset(
        id="fullscreen",
        label="Fullscreen",
        description="Open the window fullscreen.",
    ),
    ActionPreset(
        id="maximize",
        label="Maximize",
        description="Open the window maximized.",
    ),
    ActionPreset(
        id="workspace",
        label="Open on workspace",
        description="Send the window to a specific workspace on spawn.",
        fields=(
            ActionField(
                label="Workspace",
                placeholder="1",
                hint=(
                    "Workspace id (e.g. 1) or name (e.g. name:work). "
                    "Append ' silent' to open without focusing."
                ),
            ),
        ),
    ),
    ActionPreset(
        id="monitor",
        label="Open on monitor",
        description="Send the window to a specific monitor on spawn.",
        fields=(
            ActionField(
                label="Monitor",
                placeholder="DP-1",
                hint="Monitor name (e.g. DP-1) or numeric index.",
            ),
        ),
    ),
    ActionPreset(
        id="size",
        label="Set size",
        description="Set the window's initial size (floating only).",
        fields=(
            ActionField(
                label="Width",
                placeholder="1280",
                kind="number",
                digits=0,
                max_value=16384,
                step=10,
                default="1280",
            ),
            ActionField(
                label="Height",
                placeholder="720",
                kind="number",
                digits=0,
                max_value=16384,
                step=10,
                default="720",
            ),
        ),
    ),
    ActionPreset(
        id="move",
        label="Set position",
        description="Set the window's initial position. Two space-separated expressions.",
        fields=(
            ActionField(
                label="X",
                placeholder="100",
                kind="number",
                digits=0,
                min_value=-16384,
                max_value=16384,
                step=10,
                default="100",
            ),
            ActionField(
                label="Y",
                placeholder="100",
                kind="number",
                digits=0,
                min_value=-16384,
                max_value=16384,
                step=10,
                default="100",
            ),
        ),
    ),
    ActionPreset(
        id="opacity",
        label="Set opacity",
        description="Active and inactive opacity. Values are set absolutely via 'override' suffix.",
        override_fields=True,
        fields=(
            ActionField(
                label="Active",
                kind="number",
                digits=2,
                min_value=0.0,
                max_value=1.0,
                step=0.05,
                default="1.00",
            ),
            ActionField(
                label="Inactive",
                hint="Leave blank to use the active value for both.",
                kind="number",
                digits=2,
                min_value=0.0,
                max_value=1.0,
                step=0.05,
                default="0.80",
            ),
        ),
    ),
    ActionPreset(
        id="rounding",
        label="Set corner rounding",
        description="Override the corner rounding (in pixels) for this window.",
        fields=(
            ActionField(
                label="Pixels",
                kind="number",
                digits=0,
                max_value=200,
                step=1,
                default="8",
            ),
        ),
    ),
    ActionPreset(
        id="opaque",
        label="Force opaque",
        description="Disable transparency for this window.",
    ),
    ActionPreset(
        id="no_blur",
        label="No blur",
        description="Disable background blur behind this window.",
    ),
    ActionPreset(
        id="no_shadow",
        label="No shadow",
        description="Disable the drop shadow for this window.",
    ),
    ActionPreset(
        id="no_anim",
        label="No animations",
        description="Disable open/close animations for this window.",
    ),
    ActionPreset(
        id="no_initial_focus",
        label="No initial focus",
        description="Don't focus the window when it spawns.",
    ),
    ActionPreset(
        id="no_focus",
        label="Never focusable",
        description="Hyprland will never focus this window (e.g. legacy XWayland helpers).",
    ),
    ActionPreset(
        id="stay_focused",
        label="Stay focused",
        description="Window keeps focus even when others would steal it.",
    ),
    ActionPreset(
        id="idle_inhibit",
        label="Inhibit idle",
        description="Prevent idle/screensaver while this window is around.",
        fields=(
            ActionField(
                label="Mode",
                placeholder="focus",
                hint="One of: none, always, focus, fullscreen.",
                default="focus",
            ),
        ),
    ),
    ActionPreset(
        id="suppress_event",
        label="Suppress event",
        description="Tell Hyprland to ignore a class of events from this window.",
        fields=(
            ActionField(
                label="Event",
                placeholder="activatefocus",
                hint=(
                    "Space-separated: activate, activatefocus, "
                    "fullscreen, maximize, fullscreenoutput."
                ),
            ),
        ),
    ),
    ActionPreset(
        id="pseudo",
        label="Pseudotile",
        description="Pseudotile the window (floating with tiling-like sizing).",
    ),
    ActionPreset(
        id="animation",
        label="Animation style",
        description="Force an animation style on this window, with optional percentage.",
        fields=(
            ActionField(
                label="Style",
                kind="choice",
                choices=_ANIMATION_STYLES,
                default="popin",
            ),
            ActionField(
                label="Amount",
                placeholder="80%",
                hint="Optional percentage like '80%'. Leave blank for default.",
                default="",
            ),
        ),
    ),
    ActionPreset(
        id="border_size",
        label="Border size",
        description="Override the border thickness for this window.",
        fields=(
            ActionField(
                label="Pixels",
                kind="number",
                digits=0,
                max_value=50,
                step=1,
                default="2",
            ),
        ),
    ),
    ActionPreset(
        id="border_color",
        label="Border color",
        description="Force the border color. Accepts a color or gradient.",
        fields=(
            ActionField(
                label="Color",
                placeholder='rgb(FF0000) or {"rgba(...)", "rgba(...)"}',
                hint="Solid: rgb(FF0000). Gradient with angle or two colors.",
            ),
        ),
    ),
    ActionPreset(
        id="dim_around",
        label="Dim around window",
        description="Dim the background around this floating window.",
    ),
    ActionPreset(
        id="group",
        label="Group options",
        description="Set window group properties: set, new, lock, barred, deny, invade, override, unset.",
        fields=(
            ActionField(
                label="Options",
                placeholder="set",
                hint="Space-separated: set new lock barred deny invade override unset",
            ),
        ),
    ),
    ActionPreset(
        id="no_screen_share",
        label="Hide from screen share",
        description="Block screen sharing by drawing black rectangles over this window.",
    ),
    ActionPreset(
        id="fullscreen_state",
        label="Fullscreen state",
        description='Set the fullscreen mode. E.g. "1 2" (internal client). 0=none 1=maximize 2=fullscreen 3=both.',
        fields=(
            ActionField(
                label="State",
                placeholder="1 2",
                hint="Two space-separated values: internal fullscreen_state and client fullscreen_state.",
            ),
        ),
    ),
    ActionPreset(
        id="no_close_for",
        label="Block close (ms)",
        description="Prevent close with killactive for N ms after opening.",
        fields=(
            ActionField(
                label="Milliseconds",
                kind="number",
                digits=0,
                max_value=60000,
                step=500,
                default="5000",
            ),
        ),
    ),
    ActionPreset(
        id="scrolling_width",
        label="Scrolling column width",
        description="Set the column width when opening on a scrolling-layout workspace.",
        fields=(
            ActionField(
                label="Width",
                kind="number",
                digits=1,
                max_value=9999,
                step=10,
                default="500",
            ),
        ),
    ),
    ActionPreset(
        id="content",
        label="Content type",
        description='Hint at the window content type: none, photo, video, or game.',
        fields=(
            ActionField(
                label="Type",
                placeholder="none",
                hint="One of: none, photo, video, game.",
            ),
        ),
    ),
    ActionPreset(
        id="no_max_size",
        label="Remove max size",
        description="Remove max-size limits for this floating window.",
    ),
    ActionPreset(
        id="keep_aspect_ratio",
        label="Keep aspect ratio",
        description="Lock aspect ratio when resizing with the mouse.",
    ),
    ActionPreset(
        id="immediate",
        label="Allow tearing",
        description="Allow tearing (immediate presents) for this window.",
    ),
    ActionPreset(
        id="xray",
        label="Blur xray",
        description="Enable blur xray mode for this window.",
    ),
    ActionPreset(
        id="nearest_neighbor",
        label="Nearest-neighbor filtering",
        description="Force nearest-neighbor filtering (no bilinear interpolation).",
    ),
    ActionPreset(
        id="allows_input",
        label="Force input",
        description="Force an XWayland window to receive input events.",
    ),
    ActionPreset(
        id="decorate",
        label="Draw decorations",
        description="Whether to draw window decorations (titlebar, borders).",
    ),
    ActionPreset(
        id="focus_on_activate",
        label="Focus on activate",
        description="Whether Hyprland should focus the window when it requests activation.",
    ),
    ActionPreset(
        id="no_dim",
        label="No dimming",
        description="Disable window dimming for this window.",
    ),
    ActionPreset(
        id="no_follow_mouse",
        label="No mouse focus",
        description="Prevent focus on mouse hover over this window.",
    ),
    ActionPreset(
        id="no_shortcuts_inhibit",
        label="No shortcut inhibit",
        description="Prevent this window from inhibiting your keyboard shortcuts.",
    ),
    ActionPreset(
        id="no_vrr",
        label="No VRR",
        description="Disable variable refresh rate for this window (needs misc:vrr 2 or 3).",
    ),
    ActionPreset(
        id="no_auto_hdr",
        label="No AutoHDR",
        description="Disable AutoHDR for this window.",
    ),
    ActionPreset(
        id="force_rgbx",
        label="Force opaque pixels",
        description="Force Hyprland to ignore the alpha channel entirely.",
    ),
    ActionPreset(
        id="sync_fullscreen",
        label="Sync fullscreen",
        description="Sync the internal fullscreen mode with the one sent to the window.",
    ),
    ActionPreset(
        id="render_unfocused",
        label="Render when hidden",
        description="Force the window to render even when not visible.",
    ),
    ActionPreset(
        id="confine_pointer",
        label="Confine pointer",
        description="Lock the mouse cursor to the window area.",
    ),
    ActionPreset(
        id="persistent_size",
        label="Remember size",
        description="Store and restore floating window size across opens (same class+title).",
    ),
    ActionPreset(
        id="rounding_power",
        label="Rounding power",
        description="Override the rounding power/curve for this window.",
        fields=(
            ActionField(
                label="Power",
                kind="number",
                digits=2,
                min_value=0.0,
                max_value=10.0,
                step=0.1,
                default="1.00",
            ),
        ),
    ),
    ActionPreset(
        id="scroll_mouse",
        label="Scroll speed (mouse)",
        description="Override input.scroll_factor for this window.",
        fields=(
            ActionField(
                label="Factor",
                kind="number",
                digits=2,
                min_value=0.0,
                max_value=10.0,
                step=0.25,
                default="1.00",
            ),
        ),
    ),
    ActionPreset(
        id="scroll_touchpad",
        label="Scroll speed (touchpad)",
        description="Override input.touchpad.scroll_factor for this window.",
        fields=(
            ActionField(
                label="Factor",
                kind="number",
                digits=2,
                min_value=0.0,
                max_value=10.0,
                step=0.25,
                default="1.00",
            ),
        ),
    ),
    ActionPreset(
        id="tonemap",
        label="Tonemap",
        description='Tonemapping: on (default), off, clamp, or limited.',
        fields=(
            ActionField(
                label="Mode",
                placeholder="on",
                hint="on, off, clamp, limited.",
                default="on",
            ),
        ),
    ),
    ActionPreset(
        id="tag",
        label="Tag",
        description="Apply a dynamic tag. Use +/- prefix to set/unset, no prefix to toggle.",
        fields=(
            ActionField(
                label="Tag",
                placeholder="+myTag",
                hint="+name to add, -name to remove, name to toggle. Dynamic tags get * suffix.",
            ),
        ),
    ),
    ActionPreset(
        id="max_size",
        label="Max size",
        description="Maximum size for the floating window.",
        fields=(
            ActionField(label="Width", kind="number", digits=0, max_value=16384, step=10, default="1920"),
            ActionField(label="Height", kind="number", digits=0, max_value=16384, step=10, default="1080"),
        ),
    ),
    ActionPreset(
        id="min_size",
        label="Min size",
        description="Minimum size for the floating window.",
        fields=(
            ActionField(label="Width", kind="number", digits=0, max_value=16384, step=10, default="400"),
            ActionField(label="Height", kind="number", digits=0, max_value=16384, step=10, default="300"),
        ),
    ),
)

ACTION_PRESETS_BY_ID: dict[str, ActionPreset] = {p.id: p for p in ACTION_PRESETS}

# Fall-through preset for plugin actions or anything not catalogued.
# The single field holds the full effect string verbatim, including the
# effect name and any args (e.g. ``plugin:foo:bar arg1``).
CUSTOM_PRESET: ActionPreset = ActionPreset(
    id="__custom__",
    label="Custom action…",
    description="Type any Hyprland action verbatim, including plugin actions.",
    fields=(
        ActionField(
            label="Action",
            placeholder="plugin:foo:bar arg1 arg2",
            hint="The full action string as it would appear before the comma.",
        ),
    ),
)


def lookup_preset(effect_name: str) -> ActionPreset:
    """Return the :class:`ActionPreset` matching *effect_name*, or Custom."""
    return ACTION_PRESETS_BY_ID.get(effect_name, CUSTOM_PRESET)


# ---------------------------------------------------------------------------
# Matcher catalog (for the UI's matcher-key dropdown)
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class MatcherKind:
    """A v3 matcher key, with UI hints and value type."""

    key: str
    label: str
    description: str
    value_kind: Literal["regex", "bool", "text"] = "regex"
    placeholder: str = ""


MATCHER_KINDS: tuple[MatcherKind, ...] = (
    MatcherKind(
        key="class",
        label="Window class",
        description="Match by app class (e.g. firefox, kitty). Regex.",
        placeholder="^(firefox)$",
    ),
    MatcherKind(
        key="title",
        label="Window title",
        description="Match by window title text. Regex.",
        placeholder="^(.*Mozilla Firefox)$",
    ),
    MatcherKind(
        key="initial_class",
        label="Initial class",
        description="Class at spawn time, before the app sets a different one. Regex.",
        placeholder="^(firefox)$",
    ),
    MatcherKind(
        key="initial_title",
        label="Initial title",
        description="Title at spawn time, before the app updates it. Regex.",
        placeholder="^(Loading…)$",
    ),
    MatcherKind(
        key="xwayland",
        label="XWayland window",
        description="Window is running under XWayland.",
        value_kind="bool",
    ),
    MatcherKind(
        key="float",
        label="Floating",
        description="Window is currently floating. Re-evaluates dynamically.",
        value_kind="bool",
    ),
    MatcherKind(
        key="fullscreen",
        label="Fullscreen",
        description="Window is currently fullscreen. Re-evaluates dynamically.",
        value_kind="bool",
    ),
    MatcherKind(
        key="pin",
        label="Pinned",
        description="Window is pinned across workspaces. Re-evaluates dynamically.",
        value_kind="bool",
    ),
    MatcherKind(
        key="focus",
        label="Focused",
        description="Window currently has keyboard focus. Re-evaluates dynamically.",
        value_kind="bool",
    ),
    MatcherKind(
        key="modal",
        label="Modal",
        description="Window is a modal dialog (e.g. 'Are you sure?').",
        value_kind="bool",
    ),
    MatcherKind(
        key="workspace",
        label="On workspace",
        description="Window is on a specific workspace.",
        value_kind="text",
        placeholder="1",
    ),
    MatcherKind(
        key="tag",
        label="Tag",
        description="Window has a specific tag.",
        value_kind="text",
        placeholder="my-tag",
    ),
    MatcherKind(
        key="group",
        label="Grouped",
        description="Window is part of a group. Re-evaluates dynamically.",
        value_kind="bool",
    ),
    MatcherKind(
        key="fullscreen_state_client",
        label="Fullscreen (client)",
        description="Window's self-reported fullscreen state: 0=none, 1=maximize, 2=fullscreen, 3=both.",
        value_kind="text",
        placeholder="0",
    ),
    MatcherKind(
        key="fullscreen_state_internal",
        label="Fullscreen (internal)",
        description="Hyprland's fullscreen state: 0=none, 1=maximize, 2=fullscreen, 3=both.",
        value_kind="text",
        placeholder="0",
    ),
    MatcherKind(
        key="content",
        label="Content type",
        description="Window content type: none, photo, video, or game.",
        value_kind="text",
        placeholder="none",
    ),
    MatcherKind(
        key="xdg_tag",
        label="XDG tag",
        description="Match by XDG tag (see hyprctl clients). Regex.",
        placeholder="^(my-tag)$",
    ),
)

MATCHER_KINDS_BY_KEY: dict[str, MatcherKind] = {m.key: m for m in MATCHER_KINDS}

CUSTOM_MATCHER_KIND: MatcherKind = MatcherKind(
    key="__custom__",
    label="Custom matcher…",
    description="Any other Hyprland matcher key, including future additions.",
    value_kind="text",
    placeholder="match:key value",
)


def lookup_matcher_kind(key: str) -> MatcherKind:
    """Return the :class:`MatcherKind` for *key*, or Custom if unknown.

    ``RAW_KEY`` always falls through to Custom so unparseable tokens
    are editable as opaque text rather than raising in the UI.
    """
    if key == RAW_KEY:
        return CUSTOM_MATCHER_KIND
    return MATCHER_KINDS_BY_KEY.get(key, CUSTOM_MATCHER_KIND)


# ---------------------------------------------------------------------------
# Summaries (for row titles and pending-changes copy)
# ---------------------------------------------------------------------------


def summarize_matchers(matchers: list[Matcher]) -> str:
    """Plain-English summary of what windows the matchers target."""
    if not matchers:
        return "all windows"

    # Identity matchers users mentally key off: class > initial_class
    # > title > initial_title.
    priority = ("class", "initial_class", "title", "initial_title")
    chosen: Matcher | None = None
    for k in priority:
        for m in matchers:
            if m.key == k:
                chosen = m
                break
        if chosen is not None:
            break
    if chosen is None:
        chosen = matchers[0]

    if chosen.key == RAW_KEY:
        return chosen.value or "all windows"

    kind = lookup_matcher_kind(chosen.key)
    label = kind.label.lower()

    # Detect ``negative:`` regex prefix so the summary reads as
    # "not class: foo" instead of "class: negative:foo".
    value = chosen.value
    negated = False
    if kind.value_kind == "regex" and value.startswith("negative:"):
        negated = True
        value = value[len("negative:") :]

    if kind.value_kind == "bool":
        truthy = value.strip().lower() in {"1", "true", "yes", "on"}
        if truthy:
            return label
        return f"not {label}"

    return f"{'not ' if negated else ''}{label}: {value}"


def _summarize_one_effect(effect: Effect) -> str:
    """Friendly label for a single effect (e.g. ``Set opacity: 0.8 0.95``)."""
    preset = ACTION_PRESETS_BY_ID.get(effect.name)
    if preset is None:
        full = effect.full
        return full or "(no action)"
    args = effect.args.strip()
    # Boolean presets don't surface their auto-``on`` in the title —
    # "Float window" reads cleaner than "Float window: on".
    if not args or args.lower() == "on":
        return preset.label
    return f"{preset.label}: {args}"


def summarize_action(rule: WindowRule) -> str:
    """Friendly label for a rule's effects.

    Single-effect rules read as ``Float window`` / ``Set opacity: 0.8``;
    multi-effect (block / named) rules join the per-effect labels with
    ``+`` to fit on one row, e.g. ``Float window + No blur``.
    """
    if not rule.effects:
        return "(no action)"
    if len(rule.effects) == 1:
        return _summarize_one_effect(rule.effects[0])
    return " + ".join(_summarize_one_effect(e) for e in rule.effects)


def summarize_rule(rule: WindowRule) -> tuple[str, str]:
    """Two-line ``(title, subtitle)`` summary for an ``Adw.ActionRow``.

    The subtitle leads with the matchers so users key off "for these
    windows…"; if the rule is named, the name is appended so block
    rules are recognisable without expanding the row.
    """
    subtitle = summarize_matchers(rule.matchers)
    if rule.name:
        subtitle = f"{subtitle} · {rule.name}"
    if not rule.enabled:
        subtitle = f"{subtitle} (disabled)"
    return summarize_action(rule), subtitle
