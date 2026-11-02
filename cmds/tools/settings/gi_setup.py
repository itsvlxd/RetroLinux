"""Centralized GI typelib version requirements.

Import this module before any ``from gi.repository import ...`` statements.
All version pins live here, so individual modules don't need to repeat them.
"""
import os as _os
import sys as _sys

# GTK 4.24 binds the ext-background-effect-v1 Wayland protocol on every
# toplevel and only asks the compositor to blur when CSS says
# `backdrop-filter`. Hyprland 0.56 honors that client decision, so blur
# silently disappears from every GTK app (hyprwm/Hyprland#16507). Setting
# this before GTK opens the display restores the pre-4.24 behaviour where
# the compositor decides (decoration:blur + window opacity). Do NOT switch
# to `backdrop-filter` CSS instead: on the default Vulkan GSK renderer it
# makes NVIDIA fail vkAllocateMemory() and GTK segfaults. setdefault keeps
# a user-provided value (including an intentional empty string) intact.
_os.environ.setdefault("GDK_WAYLAND_DISABLE", "ext_background_effect_manager_v1")

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
