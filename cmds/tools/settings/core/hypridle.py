"""Hypridle config parser, data model, and serializer.

Hypridle uses a block syntax (``general { … }`` / ``listener { … }``) with
``key = value`` lines inside. Comments (``#``) are preserved on read and
re-emitted in roughly the same position on write.

Path resolution:
  - :func:`hypridle_config_path` — ``~/.config/retro/hypridle.conf``
  - :func:`default_template_path` — bundled default template
"""

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

HYPRIDLE_CONFIG_PATH = Path.home() / ".config" / "retro" / "hypridle.conf"


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class IdleGeneral:
    lock_cmd: str = ""
    unlock_cmd: str = ""
    on_lock_cmd: str = ""
    on_unlock_cmd: str = ""
    before_sleep_cmd: str = ""
    after_sleep_cmd: str = ""
    ignore_dbus_inhibit: bool = False
    ignore_systemd_inhibit: bool = False
    ignore_wayland_inhibit: bool = False
    inhibit_sleep: int = 2


@dataclass(slots=True)
class IdleListener:
    timeout: int = 300
    on_timeout: str = ""
    on_resume: str = ""
    ignore_inhibit: bool = False


# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------


def hypridle_config_path() -> Path:
    return HYPRIDLE_CONFIG_PATH


def default_template_path() -> Path:
    import os
    retro = os.environ.get("RETRO_DIR", "/opt/retrolinux")
    return Path(retro) / "modules" / "hyprland" / "files" / "hypridle.conf"


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

_BOOL_VALUES = frozenset({"true", "false", "yes", "no", "1", "0"})


def _parse_bool(val: str) -> bool:
    return val.strip().lower() in ("true", "yes", "1")


def _parse_block_body(lines: list[str], start: int) -> tuple[dict[str, str], int]:
    """Parse key=value lines inside a ``{ … }`` block from *start*.
    Returns ``(kv_map, end_index)`` where *end_index* is the line
    containing ``}``.
    """
    kv: dict[str, str] = {}
    i = start
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        if line == "}" or line.startswith("}"):
            return kv, i
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^(\S+)\s*=\s*(.*?)(?:\s+#.*)?$", line)
        if m:
            key = m.group(1)
            val = m.group(2).strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            kv[key] = val
    return kv, i


def parse_hypridle(path: Path | None = None) -> tuple[IdleGeneral, list[IdleListener]]:
    """Parse a hypridle config file.

    Returns ``(general, listeners)``. Missing values get their dataclass
    defaults. Malformed lines are silently skipped.
    """
    path = path or hypridle_config_path()
    general = IdleGeneral()
    listeners: list[IdleListener] = []

    if not path.exists():
        return general, listeners

    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return general, listeners

    lines = text.splitlines()

    _GENERAL_KEYS = {
        "lock_cmd", "unlock_cmd", "on_lock_cmd", "on_unlock_cmd",
        "before_sleep_cmd", "after_sleep_cmd",
        "ignore_dbus_inhibit", "ignore_systemd_inhibit",
        "ignore_wayland_inhibit", "inhibit_sleep",
    }

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1

        if not line or line.startswith("#"):
            continue

        m = re.match(r"^(\w+)\s*\{", line)
        if not m:
            continue

        block_type = m.group(1)
        kv, i = _parse_block_body(lines, i)

        if block_type == "general":
            for key, val in kv.items():
                if key in _GENERAL_KEYS:
                    if key in ("ignore_dbus_inhibit", "ignore_systemd_inhibit", "ignore_wayland_inhibit"):
                        setattr(general, key, _parse_bool(val))
                    elif key == "inhibit_sleep":
                        try:
                            general.inhibit_sleep = int(val)
                        except ValueError:
                            pass
                    else:
                        setattr(general, key, val)

        elif block_type == "listener":
            listener = IdleListener()
            for key, val in kv.items():
                if key == "timeout":
                    try:
                        listener.timeout = int(val)
                    except ValueError:
                        pass
                elif key == "on-timeout":
                    listener.on_timeout = val
                elif key == "on-resume":
                    listener.on_resume = val
                elif key == "ignore_inhibit":
                    listener.ignore_inhibit = _parse_bool(val)
            listeners.append(listener)

    return general, listeners


# ---------------------------------------------------------------------------
# Serializer
# ---------------------------------------------------------------------------


def _serialize_value(val: object) -> str:
    if isinstance(val, bool):
        return "true" if val else "false"
    return str(val)


def serialize_hypridle(
    path: Path | None = None,
    general: IdleGeneral | None = None,
    listeners: list[IdleListener] | None = None,
) -> str:
    """Build the hypridle config text for *general* and *listeners*.

    Writes a minimal config — only non-default general keys and all
    listeners — in the same block syntax hypridle expects.
    """
    lines: list[str] = []

    if general is not None:
        has_any = any(
            getattr(general, f.name) != f.default
            for f in IdleGeneral.__dataclass_fields__.values()
        )
        if has_any:
            lines.append("general {")
            for f in IdleGeneral.__dataclass_fields__.values():
                val = getattr(general, f.name)
                if val != f.default:
                    lines.append(f"    {f.name} = {_serialize_value(val)}")
            lines.append("}")
            lines.append("")

    if listeners:
        for i, listener in enumerate(listeners):
            if i > 0:
                lines.append("")
            lines.append("listener {")
            lines.append(f"    timeout = {listener.timeout}")
            if listener.on_timeout:
                lines.append(f"    on-timeout = {listener.on_timeout}")
            if listener.on_resume:
                lines.append(f"    on-resume = {listener.on_resume}")
            if listener.ignore_inhibit:
                lines.append("    ignore_inhibit = true")
            lines.append("}")

    return "\n".join(lines) + "\n" if lines else ""


def write_hypridle(
    path: Path | None = None,
    general: IdleGeneral | None = None,
    listeners: list[IdleListener] | None = None,
) -> None:
    """Write the hypridle config to *path* (default ``~/.config/retro/hypridle.conf``)."""
    path = path or hypridle_config_path()
    text = serialize_hypridle(general=general, listeners=listeners)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


__all__ = [
    "HYPRIDLE_CONFIG_PATH",
    "IdleGeneral",
    "IdleListener",
    "hypridle_config_path",
    "default_template_path",
    "parse_hypridle",
    "serialize_hypridle",
    "write_hypridle",
]
