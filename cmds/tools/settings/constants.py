"""Application-wide constants shared across modules.

Pulling these into one module avoids hard-coded duplication across
``main``, ``window``, ``ui.about``, the window-rule self-target gate,
and the GSettings schema.
"""

# Retro Settings's Flatpak-style application id. Must stay in sync with:
# - ``data/applications/io.github.bluemancz.settings.desktop`` (Icon,
#   StartupWMClass, file basename).
# - ``data/metainfo/io.github.bluemancz.settings.metainfo.xml``.
# - ``settings/data/io.github.bluemancz.settings.gschema.xml`` (schema id +
#   path-derived directory).
# It doubles as the GSettings schema id and the value Hyprland reports
# as ``class`` for our window (used by :func:`matches_settings` to gate
# self-targeting window rules behind a confirmation dialog).
APPLICATION_ID: str = "io.github.retrolinux.settings"

import os
from pathlib import Path


def settings_pkg_dir() -> Path:
    """Absolute path to the settings package directory.
    Works from source tree, zipapp, and installed packages.
    """
    retro = os.environ.get("RETRO_DIR")
    if retro:
        return Path(retro) / "cmds" / "tools" / "settings"
    return Path(__file__).resolve().parent
