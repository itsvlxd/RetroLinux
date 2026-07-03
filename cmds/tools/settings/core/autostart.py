"""Retro startup sequence — system tasks and custom user commands.

The startup sequence is managed by the Retro init system (``load.sh``).
System tasks are hardcoded in this module; custom user commands are
stored in the ``RETRO_CUSTOM_LOAD`` variable as a pipe-separated list.
"""

from dataclasses import dataclass

# System startup tasks — mirroring the fixed tasks in load.sh.
# Each entry is (command, description).
SYSTEM_TASKS: list[tuple[str, str]] = [
    ("retro --setup", "Initializing first boot system setup"),
    ("retro bluetooth restore", "Initializing bluetooth radio cards"),
    ("retro audio easyeffects start", "Initializing audio drivers"),
    ("retro daemon start", "Initializing retro daemon engine and watchers"),
    ("retro polkit start", "Starting auth agent and keyring daemon"),
    ("retro power restore", "Restoring hardware power profiles"),
    ("retro wallpaper restore", "Applying last used wallpaper"),
    ("retro xdg dirs reset", "Ensuring XDG user directories exist"),
    ("retro xdg portal inject", "Injecting session env into XDG portal daemon"),
    ("retro xdg flatpak", "Bridging host MIME defaults into Flatpak sandbox"),
    ("retro benchmark hud load", "Loads mangohud and benchmark variables"),
    ("retro display scale --from-dpi", "Applying display scaling to XWayland DPI"),
    ("wl-paste --type text --watch cliphist store -ignore-secrets", "Starting cliphist text store watcher"),
    ("wl-paste --type image --watch cliphist store -ignore-secrets", "Starting cliphist image store watcher"),
    ("rbw config set sync_interval 1800", "Synchronizing vault refresh interval with global security policy"),
    ("rbw config set lock_timeout 900", "Enforcing automated vault hibernation and session locking"),
]

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
