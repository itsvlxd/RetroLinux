"""Read/write settings's managed config file.

The managed file lives at ``~/.config/hypr/hyprland-gui.{conf,lua}`` by
default (path is user-configurable via :func:`set_managed_path`). The
suffix is mode-driven: ``.lua`` when the user has ``hyprland.lua`` on
disk (Hyprland 0.55+ default), ``.conf`` otherwise. Both formats are
read back into the same :class:`Document` shape, so the rest of settings
doesn't care which one is on disk.
"""

import logging
from collections.abc import Iterable
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

from hyprland_config import (
    Assignment,
    BindData,
    BlankLine,
    Comment,
    Document,
    Keyword,
    ParseError,
    Rule,
    atomic_write,
    check_deprecated,
    default_hyprlang_entrypoint,
    default_lua_entrypoint,
    is_bind_keyword,
    load_any,
    migrate,
    parse_bind_line,
    parse_string,
    parse_version,
    serialize_any,
    serialize_hyprlang,
)

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Retro Actions — single source of truth
# ---------------------------------------------------------------------------
# Each entry defines a Retro Lua function that can be bound as a keybind.
# The three derived maps below (DISPATCHER, FN, STANDARD) are built
# automatically from this dict, so adding a new action is just one entry.
#
# Fields:
#   lua_fn   – the Lua function reference (e.g. ``Retro.open_terminal``)
#   label    – human-readable label displayed in the GUI
#   standard – fallback ``(dispatcher, arg)`` for Hyprlang mode / live IPC

RETRO_ACTIONS: dict = {
    "retro_open_terminal": {
        "lua_fn": "Retro.open_terminal",
        "label": "Open Terminal",
        "standard": ("exec", "retro terminal"),
    },
    "retro_open_filemanager": {
        "lua_fn": "Retro.open_filemanager",
        "label": "Open File Manager",
        "standard": ("exec", "retro filemanager"),
    },
    "retro_fullscreen": {
        "lua_fn": "Retro.fullscreen",
        "label": "Toggle Fullscreen",
        "standard": ("fullscreen", "0"),
    },
    # --- retro shell run actions ---
    "retro_open_launcher": {
        "lua_fn": "Retro.open_launcher",
        "label": "Open Launcher",
        "standard": ("exec", "retro shell run launcher"),
    },
    "retro_open_clipboard": {
        "lua_fn": "Retro.open_clipboard",
        "label": "Open Clipboard",
        "standard": ("exec", "retro shell run clipboard"),
    },
    "retro_open_emoji": {
        "lua_fn": "Retro.open_emoji",
        "label": "Open Emoji",
        "standard": ("exec", "retro shell run emoji"),
    },
    "retro_open_tmux": {
        "lua_fn": "Retro.open_tmux",
        "label": "Open Tmux",
        "standard": ("exec", "retro shell run tmux"),
    },
    "retro_open_notes": {
        "lua_fn": "Retro.open_notes",
        "label": "Open Notes",
        "standard": ("exec", "retro shell run notes"),
    },
    "retro_open_wallpapers": {
        "lua_fn": "Retro.open_wallpapers",
        "label": "Open Wallpapers",
        "standard": ("exec", "retro shell run wallpapers"),
    },
    "retro_open_screenshot": {
        "lua_fn": "Retro.open_screenshot",
        "label": "Open Screenshot",
        "standard": ("exec", "retro shell run screenshot"),
    },
    "retro_open_screenrecord": {
        "lua_fn": "Retro.open_screenrecord",
        "label": "Open Screen Recorder",
        "standard": ("exec", "retro shell run screenrecord"),
    },
    "retro_open_lockscreen": {
        "lua_fn": "Retro.open_lockscreen",
        "label": "Open Lockscreen",
        "standard": ("exec", "retro shell run lockscreen"),
    },
    "retro_open_overview": {
        "lua_fn": "Retro.open_overview",
        "label": "Open Overview",
        "standard": ("exec", "retro shell run overview"),
    },
    "retro_open_powermenu": {
        "lua_fn": "Retro.open_powermenu",
        "label": "Open Power Menu",
        "standard": ("exec", "retro shell run powermenu"),
    },
    "retro_open_tools": {
        "lua_fn": "Retro.open_tools",
        "label": "Open Tools",
        "standard": ("exec", "retro shell run tools"),
    },
    "retro_open_assistant": {
        "lua_fn": "Retro.open_assistant",
        "label": "Open Assistant",
        "standard": ("exec", "retro shell run assistant"),
    },
    "retro_open_config": {
        "lua_fn": "Retro.open_config",
        "label": "Open Config",
        "standard": ("exec", "retro shell run config"),
    },
    "retro_open_dashboard": {
        "lua_fn": "Retro.open_dashboard",
        "label": "Open Dashboard",
        "standard": ("exec", "retro shell run dashboard"),
    },
    "retro_media_play_pause": {
        "lua_fn": "Retro.media_play_pause",
        "label": "Media Play / Pause",
        "standard": ("exec", "retro shell run media-play-pause"),
    },
    "retro_media_next": {
        "lua_fn": "Retro.media_next",
        "label": "Media Next",
        "standard": ("exec", "retro shell run media-next"),
    },
    "retro_media_prev": {
        "lua_fn": "Retro.media_prev",
        "label": "Media Previous",
        "standard": ("exec", "retro shell run media-prev"),
    },
    "retro_lock_screen": {
        "lua_fn": "Retro.lock_screen",
        "label": "Lock Screen",
        "standard": ("exec", "retro shell lock"),
    },
    "retro_audio_up": {
        "lua_fn": "Retro.audio_up",
        "label": "Volume Up",
        "standard": ("exec", "retro audio up 5"),
    },
    "retro_audio_down": {
        "lua_fn": "Retro.audio_down",
        "label": "Volume Down",
        "standard": ("exec", "retro audio down 5"),
    },
    "retro_audio_mute": {
        "lua_fn": "Retro.audio_mute",
        "label": "Toggle Mute",
        "standard": ("exec", "retro audio mute"),
    },
    "retro_audio_mic_mute": {
        "lua_fn": "Retro.audio_mic_mute",
        "label": "Toggle Mic Mute",
        "standard": ("exec", "retro audio mic-mute"),
    },
    "retro_brightness_up": {
        "lua_fn": "Retro.brightness_up",
        "label": "Brightness Up",
        "standard": ("exec", "retro display brightness all +5"),
    },
    "retro_brightness_down": {
        "lua_fn": "Retro.brightness_down",
        "label": "Brightness Down",
        "standard": ("exec", "retro display brightness all -5"),
    },
    "retro_open_settings": {
        "lua_fn": "Retro.open_settings",
        "label": "Open Settings",
        "standard": ("exec", "retro settings"),
    },
}

# --- Derived maps (do not edit manually) ---

RETRO_DISPATCHER_MAP: dict[str, str] = {
    k: v["lua_fn"] for k, v in RETRO_ACTIONS.items()
}
RETRO_FN_MAP: dict[str, str] = {v: k for k, v in RETRO_DISPATCHER_MAP.items()}
RETRO_STANDARD_MAP: dict[str, tuple[str, str]] = {
    k: v["standard"] for k, v in RETRO_ACTIONS.items()
}


@dataclass(slots=True)
class ConfigSections:
    """Per-section line buffers for a single :func:`write_all` invocation.

    Each field is the serialised output of one feature page's contribution
    to the managed config. ``None`` means "page didn't run"; an empty list
    means "page ran but had nothing to emit".
    """

    binds: list[str] | None = None
    monitors: list[str] | None = None
    workspaces: list[str] | None = None
    animations: list[str] | None = None
    beziers: list[str] | None = None
    env: list[str] | None = None
    exec_: list[str] | None = None
    window_rules: list[str] | None = None
    layer_rules: list[str] | None = None
    window_rules_nodes: list["Rule"] | None = None
    layer_rules_nodes: list["Rule"] | None = None


RETRO_SETTINGS_DIR = Path.home() / ".config" / "retro"
_DEFAULT_MANAGED_BASE = Path.home() / ".config" / "retro" / "settings"
_KEYBINDS_FILENAME = "keybinds"
# Public so UI strings can format a label off the same source of truth.
LUA_MIN_VERSION: tuple[int, int, int] = (0, 55, 0)

# User-configurable override for the managed-file path. When ``None`` we
# fall back to ``_DEFAULT_MANAGED_BASE`` with the mode-appropriate suffix.
_path_override: Path | None = None
_lua_mode_cache: tuple[Path, bool] | None = None


# ---------------------------------------------------------------------------
# Mode + path resolution
# ---------------------------------------------------------------------------


def is_lua_mode() -> bool:
    """Return ``True`` when Hyprland is using its Lua config (0.55+ default).

    Signalled by the on-disk presence of ``~/.config/hypr/hyprland.lua`` —
    Hyprland 0.55 prefers that file over ``hyprland.conf`` and generates
    an empty one on first launch when neither exists.
    """
    global _lua_mode_cache
    entry = default_lua_entrypoint()
    cached = _lua_mode_cache
    if cached is not None and cached[0] == entry:
        return cached[1]
    mode = entry.exists()
    _lua_mode_cache = (entry, mode)
    return mode


def invalidate_lua_mode_cache() -> None:
    """Drop the memoized :func:`is_lua_mode` result.

    Primarily for tests that monkeypatch Hyprland config paths.
    """
    global _lua_mode_cache
    _lua_mode_cache = None


def supports_lua_migration(version: str | None) -> bool:
    """Return ``True`` when *version* is Hyprland 0.55.0 or newer."""
    parsed = parse_version(version)
    return bool(parsed) and parsed >= LUA_MIN_VERSION


_MANAGED_SUFFIXES = (".conf", ".lua")


def is_lua_target(path: Path) -> bool:
    """Return ``True`` when *path* targets Lua config output."""
    return path.suffix.lower() == ".lua"


def _with_active_suffix(base: Path) -> Path:
    """Apply the active mode's suffix to *base* — passthrough when one is set.

    Callers store paths in two forms: a suffix-less "base" that should
    follow the current mode (so a single GSetting survives Lua/Hyprlang
    flips), or an explicit ``.conf`` / ``.lua`` path that we honour as-is.
    """
    if base.suffix in _MANAGED_SUFFIXES:
        return base
    return base.with_suffix(".lua" if is_lua_mode() else ".conf")


def managed_path() -> Path:
    """Active managed-file path (suffix matches active mode by default)."""
    return _with_active_suffix(_path_override or _DEFAULT_MANAGED_BASE)


def keybinds_path() -> Path:
    """Path to the keybinds override file (suffix matches active mode)."""
    return _with_active_suffix(RETRO_SETTINGS_DIR / _KEYBINDS_FILENAME)


def managed_lua_path() -> Path:
    """``.lua`` form of the managed path — what ``hyprland.lua`` dofiles."""
    return managed_path().with_suffix(".lua")


def managed_conf_path() -> Path:
    """``.conf`` form of the managed path — what ``hyprland.conf`` sources."""
    return managed_path().with_suffix(".conf")


def default_managed_path() -> Path:
    """Default managed-file path with the active mode's suffix."""
    return _with_active_suffix(_DEFAULT_MANAGED_BASE)


def display_path(path: Path) -> str:
    """Return *path* as a string with ``$HOME`` collapsed to ``~``.

    Used wherever an absolute home path would be noise or would leak the
    username (UI source-line previews, external-rule provenance, bug-report
    bodies). Falls back to the absolute path verbatim when *path* is
    outside ``$HOME``.
    """
    try:
        return "~/" + str(path.relative_to(Path.home()))
    except ValueError:
        return str(path)


def set_managed_path(path: Path | None) -> None:
    """Override the managed-file path (``None`` reverts to the default).

    A path with a ``.conf`` / ``.lua`` suffix is stored as-given. A
    suffix-less path becomes a "base" — :func:`managed_path` will add
    the mode-appropriate suffix at call time so the override survives a
    Lua/Hyprlang switch.
    """
    global _path_override
    _path_override = path


@contextmanager
def managed_path_override(path: Path | None):
    """Temporarily override :func:`managed_path` for a ``with`` block."""
    global _path_override
    previous = _path_override
    _path_override = path
    try:
        yield
    finally:
        _path_override = previous


def user_entry_path() -> Path:
    """Path of the user's top-level Hyprland config (the file Hyprland reads)."""
    return default_lua_entrypoint() if is_lua_mode() else default_hyprlang_entrypoint()


def lua_replacement_for_stored_path(stored: str, written: Iterable[Path]) -> str | None:
    """Repoint a stored ``.conf`` managed-path at the ``.lua`` a migration just wrote.

    After the Lua converter runs, a user who customised ``config-path``
    while in Hyprlang mode otherwise keeps writing to a ``.conf`` file
    Hyprland — now in Lua mode after the restart — never loads. This
    helper computes the new stored value: same path with ``.conf`` swapped
    for ``.lua``, but only when *written* (the converter's actual outputs)
    contains it, so we don't blindly point at a non-existent file.

    Returns ``None`` when no swap is warranted — empty *stored* (user is
    on the default path; the mode-driven suffix already adapts), a
    non-.conf suffix, or no matching ``.lua`` in *written*.
    """
    if not stored:
        return None
    stored_path = Path(stored).expanduser()
    if stored_path.suffix.lower() != ".conf":
        return None
    lua_version = stored_path.with_suffix(".lua")
    written_paths = {Path(p).expanduser() for p in written}
    if lua_version not in written_paths:
        return None
    return str(lua_version)


def ensure_managed_path_matches_mode(stored: str) -> str | None:
    """Repoint a stored managed-config path to match the active Hyprland mode.

    Hyprmod owns its managed file — when the user switches Hyprland's
    config language out-of-band (e.g. creates ``hyprland.lua`` while the
    ``config-path`` GSetting is still pinned to a custom ``.conf``),
    settings silently writes the wrong format to a file Hyprland never
    loads. Fixed at startup by swapping the suffix to match
    :func:`is_lua_mode` and, when no sibling is on disk yet, converting
    the existing content via a :class:`Document` round-trip so the
    user's managed settings carry over to the new file.

    Returns the path the caller should persist + use, or ``None`` when
    no swap is warranted — empty *stored*, non-managed suffix, or the
    suffix already matches the active mode.
    """
    if not stored:
        return None
    stored_path = Path(stored).expanduser()
    if stored_path.suffix.lower() not in _MANAGED_SUFFIXES:
        return None
    target_suffix = ".lua" if is_lua_mode() else ".conf"
    if stored_path.suffix.lower() == target_suffix:
        return None
    new_path = stored_path.with_suffix(target_suffix)
    if not new_path.exists() and stored_path.exists():
        # Hyprmod-managed content — Document round-trip is safe, no user
        # authoring at risk. Original is left on disk for the user to
        # archive or delete on their own terms.
        try:
            doc = load_any(stored_path, lenient=True)
            atomic_write(new_path, serialize_any(doc, new_path))
        except (OSError, ParseError):
            # Bail without repointing — keep writing to the original
            # file (status quo, broken-but-no-data-loss) instead of
            # silently moving to a half-written or empty new sibling.
            log.warning(
                "skip auto-repoint of %s -> %s: conversion failed",
                stored_path,
                new_path,
                exc_info=True,
            )
            return None
        log.info(
            "auto-converted stale managed file %s -> %s to match active mode",
            stored_path,
            new_path,
        )
    return str(new_path)


# ---------------------------------------------------------------------------
# Special-keyword catalogue
# ---------------------------------------------------------------------------

KEYWORD_MONITOR = "monitor"
KEYWORD_WORKSPACE = "workspace"
KEYWORD_ANIMATION = "animation"
KEYWORD_BEZIER = "bezier"
KEYWORD_UNBIND = "unbind"
KEYWORD_ENV = "env"
KEYWORD_EXEC = "exec"
KEYWORD_EXEC_ONCE = "exec-once"
# ``windowrule`` is the Hyprland 0.53+ canonical name. ``windowrulev2`` is
# the 0.48–0.52 spelling — accepted on read (``migrate()`` rewrites to v3)
# but never written.
KEYWORD_WINDOWRULE = "windowrule"
# Pre-0.53 spelling — accepted on read so legacy configs surface in the UI,
# never emitted (``migrate()`` rewrites every v2 line to v3 in-memory).
KEYWORD_WINDOWRULEV2 = "windowrulev2"
KEYWORD_LAYERRULE = "layerrule"

# Non-bind Hyprland keywords settings actively manages a page for. Bind
# variants (``bind``, ``binde``, ``bindm``, …) are checked separately via
# :func:`is_bind_keyword` so future bind flag combinations don't need a
# manual update here.
_MANAGED_NON_BIND_KEYWORDS = frozenset(
    (
        KEYWORD_MONITOR,
        KEYWORD_WORKSPACE,
        KEYWORD_ANIMATION,
        KEYWORD_BEZIER,
        KEYWORD_UNBIND,
        KEYWORD_ENV,
        KEYWORD_EXEC,
        KEYWORD_EXEC_ONCE,
        KEYWORD_WINDOWRULE,
        KEYWORD_WINDOWRULEV2,
        KEYWORD_LAYERRULE,
    )
)


def _is_managed_keyword(name: str) -> bool:
    """True when *name* is a keyword settings owns a section for."""
    return name in _MANAGED_NON_BIND_KEYWORDS or is_bind_keyword(name)


# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------


def read_all_sections(
    path: Path | None = None,
) -> tuple[dict[str, str], dict[str, list[str]], list[Rule]]:
    """Single-pass parse of the managed config file.

    Returns ``(options, sections, rules)``:

    - ``options`` — values for regular option lines (``general:gaps_in``, …).
    - ``sections`` — raw lines per special keyword (``bind``, ``monitor``,
      ``env``, …), in the order they appear on disk.
    - ``rules`` — structured :class:`Rule` nodes for windowrule / layerrule
      entries. Both source shapes (single-line ``windowrule = …`` and
      block-form ``windowrule { … }``) normalise into this list via
      :func:`hyprland_config.migrate`, so consumers iterate matchers /
      effects / name / enabled directly instead of re-parsing strings.

    Deprecated syntax is rewritten in-memory before collection, so
    settings always sees the current shape regardless of the on-disk format.
    """
    path = path or managed_path()
    if not path.exists():
        return {}, {}, []
    doc = load_any(path, follow_sources=False, lenient=True)
    # In-memory only — keeps the UI consistent when the on-disk file still
    # uses legacy syntax. Persisting the migration requires user consent
    # via the deprecation dialog (:mod:`settings.core.deprecations`).
    migrate(doc)
    options: dict[str, str] = {}
    sections: dict[str, list[str]] = {}
    rules: list[Rule] = []
    for line in doc.lines:
        if isinstance(line, Assignment):
            options[line.full_key] = line.value
        elif isinstance(line, Keyword) and _is_managed_keyword(line.key):
            sections.setdefault(line.key, []).append(line.raw.strip())
        elif isinstance(line, Rule):
            rules.append(line)
    return options, sections, rules


def collect_section(sections: dict[str, list[str]], *keys: str) -> list[str]:
    """Extract lines from a pre-parsed sections dict for the given keys."""
    result: list[str] = []
    for key in keys:
        result.extend(sections.get(key, []))
    return result


def collect_bind_section(sections: dict[str, list[str]]) -> list[str]:
    """Extract lines for every bind-variant keyword present in *sections*."""
    result: list[str] = []
    for key, lines in sections.items():
        if is_bind_keyword(key):
            result.extend(lines)
    return result


# ---------------------------------------------------------------------------
# Cached read
# ---------------------------------------------------------------------------
#
# The managed file is owned by settings, so the only writes happen through
# :func:`write_all` and profile snapshot restoration — both invalidate the
# cache explicitly. Pages call :func:`read_cached` instead of re-parsing on
# every rebuild; in Lua mode this matters in particular because parsing
# spawns a Lua subprocess.

_cached_state: tuple[Path, dict[str, str], dict[str, list[str]], list[Rule]] | None = None


def read_cached() -> tuple[dict[str, str], dict[str, list[str]], list[Rule]]:
    """Return the cached ``(options, sections, rules)`` parse of the managed file.

    Re-reads from disk on path change or after :func:`invalidate_cache`.
    Callers that need to react to a fresh write should invalidate first.
    """
    global _cached_state
    path = managed_path()
    if _cached_state is not None and _cached_state[0] == path:
        return _cached_state[1], _cached_state[2], _cached_state[3]
    values, sections, rules = read_all_sections(path)
    _cached_state = (path, values, sections, rules)
    return values, sections, rules


def invalidate_cache() -> None:
    """Drop the memoised parse so the next :func:`read_cached` re-reads."""
    global _cached_state
    _cached_state = None


# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------


def _add_comment(doc: Document, text: str) -> None:
    """Append a ``# text`` comment line to *doc*."""
    doc.lines.append(Comment(raw=f"# {text}\n", text=text))


def _add_blank(doc: Document) -> None:
    """Append a blank line to *doc*."""
    doc.lines.append(BlankLine(raw="\n"))


def _add_section(doc: Document, header: str, section_lines: list[str]) -> None:
    """Append a blank line, a ``# header`` comment, and the parsed section body.

    The header comment serves both formats: in Hyprlang it's a literal
    ``#`` line; in Lua mode the emitter treats it as a topical group
    boundary and renders the body underneath a matching ``-- header``.
    """
    _add_blank(doc)
    _add_comment(doc, header)
    body = "".join(line if line.endswith("\n") else line + "\n" for line in section_lines)
    parsed = parse_string(body, lenient=True)
    migrate(parsed)
    doc.lines.extend(parsed.lines)


def _add_assignment(doc: Document, full_key: str, value: str) -> None:
    """Append a top-level (un-nested) ``full_key = value`` Assignment to *doc*.

    For flat-syntax lines (``decoration:blur_size = 8``) the parser keeps
    ``key == full_key`` so the serialized line preserves the full colon-
    path. Setting ``key`` to just the leaf would round-trip as ``blur_size
    = 8`` and lose the section qualifier.
    """
    doc.lines.append(
        Assignment(
            raw=f"{full_key} = {value}\n",
            key=full_key,
            value=value,
            full_key=full_key,
        )
    )


def _build_document(values: dict[str, str], sections: ConfigSections) -> Document:
    """Construct the outgoing :class:`Document` directly from settings's state.

    Topical sections become :class:`Comment` headers so both serializers
    can preserve the layout — Hyprlang renders ``# Keybinds`` over the
    bind lines, Lua renders ``-- Keybinds`` over the matching ``hl.bind``
    calls. The Document is the canonical handoff to migration and
    serialization; no Hyprlang-text intermediate.
    """
    doc = Document()
    _add_comment(doc, "Generated by Retro Settings")

    if sections.env:
        _add_section(doc, "Environment", sections.env)

    if values:
        # Bare option lines (general:gaps_in, decoration:rounding, …) live
        # under their own header so the Lua emitter — which treats Comments
        # as group boundaries — keeps them in a dedicated ``hl.config(...)``
        # call instead of absorbing them into the preceding section's group.
        _add_section(
            doc,
            "Settings",
            [f"{k} = {v}" for k, v in sorted(values.items())],
        )

    if sections.beziers:
        _add_section(doc, "Bezier curves", sections.beziers)
    if sections.animations:
        _add_section(doc, "Animations", sections.animations)
    if sections.monitors:
        _add_section(doc, "Monitors", sections.monitors)
    if sections.workspaces:
        _add_section(doc, "Workspaces", sections.workspaces)
    if sections.binds:
        _add_section(doc, "Keybinds", sections.binds)
    # Window rules sit before autostart so any rule overrides are in effect
    # before exec'd processes spawn matching windows on reload.
    # Use pre-built Rule nodes when available (bypasses migrate's broken
    # effect filtering for block-form rules); fall back to string lines.
    if sections.window_rules_nodes:
        _add_comment(doc, "Window rules")
        doc.lines.extend(sections.window_rules_nodes)
    elif sections.window_rules:
        _add_section(doc, "Window rules", sections.window_rules)
    if sections.layer_rules_nodes:
        _add_comment(doc, "Layer rules")
        doc.lines.extend(sections.layer_rules_nodes)
    elif sections.layer_rules:
        _add_section(doc, "Layer rules", sections.layer_rules)
    # Autostart last: ``exec`` re-runs on every reload, so config later in
    # the file that affects the exec'd process (env vars, monitor layout)
    # is already in effect by the time the commands run.
    if sections.exec_:
        _add_section(doc, "Autostart", sections.exec_)

    return doc


def _log_deprecations(doc: Document, *, hyprland_version: str | None = None) -> None:
    """Log any deprecated syntax in *doc* without mutating it.

    Save-side rewriting is intentionally not performed here — the schema
    version guard at :func:`settings.core.schema._drop_unavailable` already
    constrains the keys we emit to ones supported by the running Hyprland,
    and a buggy rename rule in hyprland-config (see GitHub issue #34) can
    otherwise corrupt valid output. Persistent migrations are routed
    through the user-confirmed flow in :mod:`settings.core.deprecations`.

    *hyprland_version* gates rules to those that have actually taken
    effect for the running Hyprland — without it, a 0.49 install would
    log "windowrulev2 was deprecated in 0.53" on every save.
    """
    for d in check_deprecated(doc, hyprland_version=hyprland_version):
        log.info("deprecated syntax in outgoing config: %s", d)


def build_content(
    values: dict[str, str],
    sections: ConfigSections,
    *,
    hyprland_version: str | None = None,
) -> str:
    """Build the Hyprlang-format text for the next save."""
    doc = _build_document(values, sections)
    _log_deprecations(doc, hyprland_version=hyprland_version)
    return serialize_hyprlang(doc)


def to_managed_text(
    values: dict[str, str],
    sections: ConfigSections,
    *,
    hyprland_version: str | None = None,
) -> str:
    """Build the next-save content in the format that hits disk.

    Returns Hyprlang text in Hyprlang mode, Lua text in Lua mode. Used by
    :func:`write_all` and the Pending Changes diff so both see the same
    bytes that will land on disk.
    """
    doc = _build_document(values, sections)
    _log_deprecations(doc, hyprland_version=hyprland_version)
    return serialize_any(doc, managed_path())


def write_all(
    values: dict[str, str],
    sections: ConfigSections,
    *,
    hyprland_version: str | None = None,
) -> None:
    """Write the managed file in the active format (Hyprlang or Lua)."""
    atomic_write(
        managed_path(),
        to_managed_text(values, sections, hyprland_version=hyprland_version),
    )
    invalidate_cache()


def write_binds(lines: list[str]) -> None:
    """Write keybind override lines to the keybinds file.

    Handles Retro Lua function dispatchers by emitting proper
    ``hl.bind("KEY", Retro.fn)`` calls in Lua mode, and falling back
    to standard dispatcher format in Hyprlang mode.
    """
    is_lua = keybinds_path().suffix == ".lua"
    header = "-- Generated by Retro Settings\n\n-- Keybinds\n"
    body_parts: list[str] = []

    has_retro = any(
        _p and _p.dispatcher in RETRO_DISPATCHER_MAP
        for _p in (parse_bind_line(l) for l in lines)
    )
    if has_retro and is_lua:
        body_parts.append('local Retro = require("lib.retro")\n')

    for line in lines:
        line = line.rstrip("\n")
        parsed = parse_bind_line(line)

        if parsed and parsed.dispatcher in RETRO_DISPATCHER_MAP:
            if is_lua:
                combo = parsed.format_shortcut()
                fn = RETRO_DISPATCHER_MAP[parsed.dispatcher]
                body_parts.append(f'hl.bind("{combo}", {fn})\n')
            else:
                disp, arg = RETRO_STANDARD_MAP[parsed.dispatcher]
                if arg:
                    body_parts.append(
                        f'{parsed.bind_type} = {parsed.mods_str}, {parsed.key}, {disp}, {arg}\n'
                    )
                else:
                    body_parts.append(
                        f'{parsed.bind_type} = {parsed.mods_str}, {parsed.key}, {disp}\n'
                    )
        else:
            # Standard or unbind line — use library serialization
            doc = Document()
            parsed_line = parse_string(line + "\n", lenient=True)
            doc.lines.extend(parsed_line.lines)
            body_parts.append(serialize_any(doc, keybinds_path()))

    atomic_write(keybinds_path(), header + "".join(body_parts))
