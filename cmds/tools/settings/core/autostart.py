"""Retro startup sequence — system tasks and custom user commands.

The startup sequence is managed by the Retro init system (``load.sh``).
System tasks are read dynamically from ``load.sh list-raw``; custom user
commands are stored in the ``RETRO_CUSTOM_LOAD`` variable as a
pipe-separated list.
"""

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
