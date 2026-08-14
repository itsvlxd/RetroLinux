"""Retro startup sequence — system tasks and custom user commands.

The startup sequence is managed by the Retro init system (``load.sh``).
System tasks are read dynamically from ``load.sh list-raw``; custom user
commands are stored in the ``RETRO_CUSTOM_LOAD`` variable as a
pipe-separated list.
"""

import os
import re
import subprocess
from dataclasses import dataclass


def get_system_tasks() -> list[tuple[str, str]]:
    """Run ``retro --load list-raw`` and parse ``command|description`` lines.

    This is the single source of truth — the same list ``retro --load``
    runs on startup.
    """
    try:
        result = subprocess.run(
            ["retro", "--load", "list-raw"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode != 0:
            return []
        tasks: list[tuple[str, str]] = []
        for line in result.stdout.strip().splitlines():
            line = line.strip()
            if not line or "|" not in line:
                continue
            cmd, _, desc = line.partition("|")
            tasks.append((cmd.strip(), desc.strip()))
        return tasks
    except (OSError, subprocess.TimeoutExpired):
        return []

# ---------------------------------------------------------------------------
# Custom user startup entries (variable-backed, not in settings.lua)
# ---------------------------------------------------------------------------

RETRO_STARTUP_VAR = "RETRO_CUSTOM_LOAD"


@dataclass(slots=True)
class RetroStartupData:
    """A single retro custom startup command."""

    command: str


def parse_retro_startup(raw: str) -> list[RetroStartupData]:
    """Parse a ``RETRO_CUSTOM_LOAD`` pipe-separated string into entries."""
    if not raw or raw.strip() in ("", "null"):
        return []
    items: list[RetroStartupData] = []
    for part in raw.split("|"):
        cmd = part.strip()
        if cmd:
            items.append(RetroStartupData(command=cmd))
    return items


def serialize_retro_startup(items: list[RetroStartupData]) -> str:
    """Join retro startup entries into a pipe-separated string."""
    return "|".join(item.command for item in items)


# ---------------------------------------------------------------------------
# XDG application autostart (wraps scripts/xdg_core.sh)
# ---------------------------------------------------------------------------

_XDG_CORE = os.path.join(
    os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "xdg_core.sh"
)


@dataclass(slots=True)
class XdgAutostartEntry:
    """A single XDG autostart ``.desktop`` entry (user or system scope)."""

    name: str
    path: str
    enabled: bool
    binary_exists: bool
    scope: str


def _run_xdg(args: list[str], timeout: int = 15) -> str:
    try:
        r = subprocess.run(
            ["bash", _XDG_CORE, *args],
            capture_output=True, text=True, timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def list_xdg_autostart() -> list[XdgAutostartEntry]:
    """List all XDG autostart entries (user scope wins over system).

    The underlying script emits ``name|desktop_file|enabled|binary_exists|scope``
    lines, scanning user then system autostart dirs. A user override shadows the
    system entry of the same filename, so we dedupe by ``.desktop`` basename.
    """
    out = _run_xdg(["--autostart-list"])
    entries: list[XdgAutostartEntry] = []
    seen: set[str] = set()
    for line in out.splitlines():
        parts = line.split("|")
        if len(parts) < 5:
            continue
        name, path, enabled, binary, scope = parts[:5]
        basename = os.path.basename(path)
        if basename in seen:
            continue
        seen.add(basename)
        entries.append(XdgAutostartEntry(
            name=name,
            path=path,
            enabled=(enabled == "true"),
            binary_exists=(binary == "yes"),
            scope=scope,
        ))
    entries.sort(key=lambda e: (0 if e.scope == "user" else 1, e.name.lower()))
    return entries


def toggle_xdg_autostart(desktop: str, action: str = "toggle") -> bool:
    """Enable/disable an XDG autostart entry by ``.desktop`` filename."""
    return _run_xdg(["--autostart-toggle", desktop, action]).startswith("OK")


def delete_xdg_autostart(desktop: str) -> bool:
    """Remove a user XDG autostart entry (or its override) by filename."""
    return _run_xdg(["--autostart-delete", desktop]).startswith("OK")


def clean_xdg_autostart() -> int:
    """Remove stale user autostart entries whose binary is missing."""
    out = _run_xdg(["--autostart-clean"])
    m = re.search(r"cleaned=(\d+)", out)
    return int(m.group(1)) if m else 0
