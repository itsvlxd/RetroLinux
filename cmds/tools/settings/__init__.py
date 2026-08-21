"""Retro Settings — GTK4/libadwaita configuration tool for Hyprland."""

import sys as _sys

def _dbg(msg: str) -> None:
    if "--debug" in _sys.argv or "-d" in _sys.argv:
        print(f"[settings.__init__] {msg}", file=_sys.stderr, flush=True)

_dbg("Package init starting")
import settings.gi_setup  # noqa: F401
_dbg("gi_setup imported")
