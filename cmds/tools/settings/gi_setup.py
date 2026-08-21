"""Centralized GI typelib version requirements.

Import this module before any ``from gi.repository import ...`` statements.
All version pins live here, so individual modules don't need to repeat them.
"""
import sys as _sys

def _dbg(msg: str) -> None:
    if "--debug" in _sys.argv or "-d" in _sys.argv:
        print(f"[gi_setup] {msg}", file=_sys.stderr, flush=True)

_dbg("importing gi")
import gi
_dbg(f"gi imported ({gi.__version__})")

gi.require_version("Adw", "1")
_dbg("Adw 1 loaded")
gi.require_version("cairo", "1.0")
_dbg("cairo 1.0 loaded")
gi.require_version("Gdk", "4.0")
_dbg("Gdk 4.0 loaded")

gi.require_version("Gtk", "4.0")
