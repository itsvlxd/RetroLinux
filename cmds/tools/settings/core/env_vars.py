"""Parsing and serialization helpers for ``env = NAME,value`` entries.

Env vars are stored in ``~/.config/retro/env.lua`` as ``hl.env("NAME", "value")``
calls, sourced from ``hyprland.lua``. The ``XCURSOR_THEME`` / ``XCURSOR_SIZE`` /
``HYPRCURSOR_THEME`` / ``HYPRCURSOR_SIZE`` names are owned by the Cursor page.
"""

from dataclasses import dataclass
from pathlib import Path

import hyprland_config

from settings.core import config
from settings.core.external import load_external_keyword_entries

ENV_LUA_PATH: Path = config.RETRO_SETTINGS_DIR / "env.lua"

# Names whose env lines are owned by ``settings.pages.cursor.CursorPage``.
# The Env Variables page skips these on read so the cursor theme/size is
# only editable in one place. Order is irrelevant — this is a membership
# check, not a sequence.
RESERVED_NAMES: frozenset[str] = frozenset(
    {
        "XCURSOR_THEME",
        "XCURSOR_SIZE",
        "HYPRCURSOR_THEME",
        "HYPRCURSOR_SIZE",
    }
)


def is_reserved(name: str) -> bool:
    """True if *name* is owned by another page (currently the Cursor page).

    The check is case-sensitive — POSIX environment variable names are
    case-sensitive, and Hyprland forwards them verbatim.
    """
    return name in RESERVED_NAMES


@dataclass(slots=True)
class EnvVar:
    """A single ``env = NAME,value`` entry.

    *value* is preserved verbatim including any commas — Hyprland only
    splits on the *first* comma, so ``GDK_BACKEND,wayland,x11`` is a
    single entry whose value is ``wayland,x11``.
    """

    name: str
    value: str

    def to_line(self) -> str:
        """Serialize as a single ``env = NAME,value`` config line."""
        return f"{config.KEYWORD_ENV} = {self.name},{self.value}"


def parse_env_line(line: str) -> EnvVar | None:
    """Parse a single ``env = NAME,value`` line into an :class:`EnvVar`.

    Returns ``None`` when the line is missing the ``env`` keyword, the
    ``=`` separator, the ``,`` between name and value, or the name
    itself. Whitespace around the keyword, name, and value is stripped.

    The value preserves embedded commas — only the first comma after
    the keyword's ``=`` is treated as the separator (Hyprland uses the
    same rule). Use :func:`parse_env_lines` for a tolerant batch
    parser that drops unparseable lines.
    """
    head, sep, tail = line.partition("=")
    if not sep:
        return None
    if head.strip() != config.KEYWORD_ENV:
        return None
    body = tail.strip()
    if not body:
        return None
    name, comma, value = body.partition(",")
    if not comma:
        # Hyprland 0.54 rejects ``env = NAME`` with no value, but lenient
        # parsers in the wild sometimes accept it. We don't — emitting
        # such a line would be a runtime error, so we drop it instead.
        return None
    name = name.strip()
    value = value.strip()
    if not name or not value:
        # Empty name (``env = ,value``) is rejected unconditionally.
        # Empty value (``env = NAME,``) is also rejected because Hyprland
        # 0.54 errors out on it; the dialog's apply gate ensures we never
        # emit such a line, so seeing one means the file was edited by
        # hand and is broken.
        return None
    return EnvVar(name=name, value=value)


def parse_env_lines(lines: list[str]) -> list[EnvVar]:
    """Parse multiple raw env lines, dropping anything unparseable.

    Order is preserved. Lines that don't match the ``env`` keyword or
    are syntactically broken are silently skipped — the caller has
    already filtered ``sections`` by keyword, so a mismatch here is a
    sign of corruption rather than user error and shouldn't block
    loading the rest of the page.

    Names in :data:`RESERVED_NAMES` are *not* filtered here — the page
    is responsible for that, since the parser is also used by the
    pending-changes diff which needs to see every env line for an
    accurate save preview.
    """
    result = []
    for raw in lines:
        parsed = parse_env_line(raw)
        if parsed is not None:
            result.append(parsed)
    return result


def serialize(items: list[EnvVar]) -> list[str]:
    """Serialize a list of :class:`EnvVar` back to config lines.

    Items are emitted in the order they appear in *items* — the page
    is responsible for any reordering before calling this.
    """
    return [item.to_line() for item in items]


# ---------------------------------------------------------------------------
# External loader (env vars from outside our managed file)
# ---------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class ExternalEnvVar:
    """An ``env = NAME,value`` entry from a config file outside settings's.

    Surfaced as a locked row on the Env Variables page so users can see
    what's already exported from their own ``hyprland.conf`` (or any file
    it sources). Click the override button on the row to add a managed
    entry with the same name — Hyprland reads source files in order and
    "last write wins," so our managed file (sourced from
    ``hyprland.conf`` by Retro Settings's first-run setup) wins by virtue of
    being last.

    Mirrors :class:`settings.core.layer_rules.ExternalLayerRule` for
    consistency with the other read-only-external displays.
    """

    var: EnvVar
    source_path: Path
    lineno: int


def load_external_env_vars(
    root_path: Path,
    managed_path: Path,
) -> list[ExternalEnvVar]:
    """Walk *root_path* and its sourced files for env entries outside
    *managed_path*.

    Skips :data:`RESERVED_NAMES` so cursor-managed vars don't double-up
    on this page (the Cursor page already surfaces them).

    Errors return an empty list (advisory display only; failing
    silently is safer than blocking the page on a flaky config).
    """
    # Env lines need no schema migration pass; we parse ``env = NAME,value``
    # directly and then apply cursor-owned-name filtering.
    entries = load_external_keyword_entries(
        root_path,
        managed_path,
        (config.KEYWORD_ENV,),
    )
    external: list[ExternalEnvVar] = []
    for entry in entries:
        line = f"{entry.key} = {entry.value}"
        parsed = parse_env_line(line)
        if parsed is None:
            continue
        if parsed.name in RESERVED_NAMES:
            # Cursor page owns these names; surfacing them here too
            # would split the UX of one logical setting across two
            # pages.
            continue
        external.append(
            ExternalEnvVar(
                var=parsed,
                source_path=entry.source_path,
                lineno=entry.lineno,
            )
        )
    return external


def overridden_external_names(
    external: list[ExternalEnvVar],
    owned: list[EnvVar],
) -> set[str]:
    """Return the set of external-var names that an owned var overrides.

    "Overrides" here means same name — Hyprland evaluates env lines in
    source order with last-write-wins semantics, so an owned line and
    an external line sharing a name yield the owned value. The page
    uses this to render overridden externals with a muted "Overridden"
    badge and to suppress the override button on already-overridden
    rows.
    """
    owned_names = {e.name for e in owned}
    return {ext.var.name for ext in external if ext.var.name in owned_names}


# ---------------------------------------------------------------------------
# env.lua reader / writer
# ---------------------------------------------------------------------------


def parse_env_lua_file(path: Path) -> list[EnvVar]:
    """Parse ``hl.env("NAME", "value")`` calls from *path* into :class:`EnvVar` list."""
    if not path.exists():
        return []
    try:
        doc = hyprland_config.load_any(path, follow_sources=False, lenient=True)
    except Exception:
        return []
    result: list[EnvVar] = []
    for _odoc, line in doc.iter_lines():
        if not isinstance(line, hyprland_config.Rule) and not isinstance(line, hyprland_config.Keyword):
            continue
        kind = getattr(line, 'kind', None) or getattr(line, 'key', '')
        value = getattr(line, 'value', '')
        if not kind or not value:
            continue
        # Reconstruct and parse as a config line
        parsed = parse_env_line(f"{kind} = {value}")
        if parsed is not None:
            result.append(parsed)
    return result


def serialize_env_lua(items: list[EnvVar]) -> str:
    """Serialize env vars to ``hl.env()`` Lua format."""
    lines = [
        "-- This file has been generated by Retro Settings",
        "",
    ]
    for item in items:
        # Escape double quotes inside the value
        name = item.name.replace('"', '\\"')
        value = item.value.replace('"', '\\"')
        lines.append(f'hl.env("{name}", "{value}")')
    lines.append("")
    return "\n".join(lines)


__all__ = [
    "ENV_LUA_PATH",
    "RESERVED_NAMES",
    "EnvVar",
    "ExternalEnvVar",
    "is_reserved",
    "load_external_env_vars",
    "overridden_external_names",
    "parse_env_line",
    "parse_env_lines",
    "parse_env_lua_file",
    "serialize",
    "serialize_env_lua",
]
