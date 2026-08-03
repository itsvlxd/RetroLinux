"""Data layer for the Retro Shell's per-module JSON config files.

The shell keeps one JSON file per module under
``(XDG_CONFIG_HOME || ~/.config)/retro/shell/`` (bar.json, theme.json, …).
Each file is watched by a ``FileView`` in ``config/Config.qml`` with
``watchChanges: true`` and ``atomicWrites: true``; on an external write
the shell reloads the file (the ``onFileChanged`` handler briefly sets
``pauseAutoSave`` to avoid a feedback loop). That means a writer like
Retro Settings can simply write the JSON and the shell picks it up live —
no restart or signal needed.

Reads are a deep merge of the bundled defaults (mirroring
``modules/retroshell/files/config/defaults/bar.js``) with whatever is on
disk, so missing keys always resolve and unknown keys are preserved.
Writes are atomic (temp file + ``os.replace``) to match the shell's
``atomicWrites`` expectation.
"""

import json
import os
import tempfile
from pathlib import Path


def shell_config_dir() -> Path:
    """Absolute path to the shell's config directory (creates nothing)."""
    base = os.environ.get("XDG_CONFIG_HOME")
    if not base:
        base = os.path.join(os.path.expanduser("~"), ".config")
    return Path(base) / "retro" / "shell"


def _deep_merge(base: dict, override: dict) -> dict:
    """Return a new dict with *override* layered on top of *base*."""
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def _read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def load_shell_json(name: str, defaults: dict) -> dict:
    """Load *name*.json from the shell config dir merged over *defaults*."""
    return _deep_merge(defaults, _read_json(shell_config_dir() / f"{name}.json"))


def save_shell_json(name: str, data: dict) -> None:
    """Atomically write *name*.json in the shell config dir."""
    path = shell_config_dir() / f"{name}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=1)
            fh.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ── bar.json ────────────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/bar.js`` and the
# JsonAdapter defaults in ``Config.qml`` (lines ~528-549).
BAR_DEFAULTS: dict = {
    "position": "top",
    "launcherIcon": "",
    "launcherIconTint": True,
    "launcherIconFullTint": True,
    "launcherIconSize": 24,
    "pillStyle": "default",
    "screenList": [],
    "enableFirefoxPlayer": False,
    "barColor": [["surface", 0.0]],
    "frameEnabled": False,
    "frameThickness": 6,
    # Auto-hide settings
    "pinnedOnStartup": True,
    "hoverToReveal": True,
    "hoverRegionHeight": 8,
    "showPinButton": True,
    "availableOnFullscreen": False,
    "use12hFormat": False,
    "containBar": False,
    "keepBarShadow": False,
    "keepBarBorder": False,
}


def bar_path() -> Path:
    return shell_config_dir() / "bar.json"


def load_bar() -> dict:
    return load_shell_json("bar", BAR_DEFAULTS)


def save_bar(data: dict) -> None:
    save_shell_json("bar", data)


# ── theme.json ──────────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/theme.js``.
#
# Each ``sr*`` entry is a "variant" surface (Background, Pane, Primary, …)
# described by ``label`` plus a gradient/border/opacity stack. The defaults
# below mirror ``theme.js`` verbatim so a fresh install (or a deeply-merged
# read) always resolves every key the shell expects.


def _variant_defaults(label: str, gradient, **extra) -> dict:
    """Build a theme variant default sharing the common property set."""
    base = {
        "label": label,
        "gradient": gradient,
        "gradientType": "linear",
        "gradientAngle": 0,
        "gradientCenterX": 0.5,
        "gradientCenterY": 0.5,
        "halftoneDotMin": 0.0,
        "halftoneDotMax": 2.0,
        "halftoneStart": 0.0,
        "halftoneEnd": 1.0,
        "halftoneDotColor": "surface",
        "halftoneBackgroundColor": "background",
        "border": ["surfaceBright", 0],
        "itemColor": "overBackground",
        "opacity": 1.0,
    }
    base.update(extra)
    return base


def _surface_variant(label: str, border: list, *, dot: str = "surface",
                     item: str = "overBackground", opacity: float = 1.0) -> dict:
    return _variant_defaults(
        label,
        [["background", 0.0]],
        halftoneDotColor=dot,
        halftoneBackgroundColor="background",
        border=border,
        itemColor=item,
        opacity=opacity,
    )


def _linear_variant(label: str, gradient, *, dot: str = "surface",
                    dot_bg: str = "surface", border: list | None = None,
                    item: str = "overBackground", opacity: float = 1.0) -> dict:
    return _variant_defaults(
        label,
        gradient,
        halftoneDotColor=dot,
        halftoneBackgroundColor=dot_bg,
        border=border if border is not None else ["surfaceBright", 0],
        itemColor=item,
        opacity=opacity,
    )


# The exact variant stack from ``theme.js``. Keys match the shell's
# ``srNameToId`` mapping (e.g. ``srBarBg`` → variant id ``barbg``).
THEME_VARIANTS: dict = {
    "srBg": _linear_variant("Background", [["background", 0.0]],
                            dot="surface", dot_bg="background"),
    "srPopup": _linear_variant("Popup", [["background", 0.0]],
                               dot="surface", dot_bg="background",
                               border=["surfaceBright", 2]),
    "srInternalBg": _linear_variant("Internal BG", [["background", 0.0]],
                                    dot="surface", dot_bg="background"),
    "srBarBg": _linear_variant("Bar BG", [["surfaceDim", 0.0]],
                               dot="surface", dot_bg="surfaceDim",
                               border=["surfaceBright", 0], opacity=0.0),
    "srPane": _linear_variant("Pane", [["surface", 0.0]],
                              dot="surfaceBright", dot_bg="surface"),
    "srCommon": _linear_variant("Common", [["surface", 0.0]],
                                dot="background", dot_bg="surface"),
    "srFocus": _linear_variant("Focus", [["surfaceBright", 0.0]],
                               dot="surfaceVariant", dot_bg="surfaceBright"),
    "srPrimary": _linear_variant("Primary", [["primary", 0.0]],
                                 dot="overPrimaryContainer", dot_bg="primary",
                                 border=["primary", 0], item="overPrimary"),
    "srPrimaryFocus": _linear_variant("Primary Focus", [["overPrimaryContainer", 0.0]],
                                      dot="primary", dot_bg="overPrimaryContainer",
                                      border=["overBackground", 0], item="overPrimary"),
    "srOverPrimary": _linear_variant("Over Primary", [["overPrimary", 0.0]],
                                     dot="primaryContainer", dot_bg="overPrimary",
                                     border=["overPrimary", 0], item="primary"),
    "srSecondary": _linear_variant("Secondary", [["secondary", 0.0]],
                                   dot="overSecondaryContainer", dot_bg="secondary",
                                   border=["secondary", 0], item="overSecondary"),
    "srSecondaryFocus": _linear_variant("Secondary Focus", [["overSecondaryContainer", 0.0]],
                                        dot="secondary", dot_bg="overSecondaryContainer",
                                        border=["overBackground", 0], item="overSecondary"),
    "srOverSecondary": _linear_variant("Over Secondary", [["overSecondary", 0.0]],
                                       dot="secondaryContainer", dot_bg="overSecondary",
                                       border=["overSecondary", 0], item="secondary"),
    "srTertiary": _linear_variant("Tertiary", [["tertiary", 0.0]],
                                  dot="overTertiaryContainer", dot_bg="tertiary",
                                  border=["tertiary", 0], item="overTertiary"),
    "srTertiaryFocus": _linear_variant("Tertiary Focus", [["overTertiaryContainer", 0.0]],
                                       dot="tertiary", dot_bg="overTertiaryContainer",
                                       border=["overBackground", 0], item="overTertiary"),
    "srOverTertiary": _linear_variant("Over Tertiary", [["overTertiary", 0.0]],
                                      dot="tertiaryContainer", dot_bg="overTertiary",
                                      border=["overTertiary", 0], item="tertiary"),
    "srError": _linear_variant("Error", [["error", 0.0]],
                               dot="overErrorContainer", dot_bg="error",
                               border=["error", 0], item="overError"),
    "srErrorFocus": _linear_variant("Error Focus", [["overBackground", 0.0]],
                                    dot="error", dot_bg="overErrorContainer",
                                    border=["overBackground", 0], item="overError"),
    "srOverError": _linear_variant("Over Error", [["overError", 0.0]],
                                   dot="errorContainer", dot_bg="overError",
                                   border=["overError", 0], item="error"),
}

# Top-level theme keys from ``theme.js``.
THEME_DEFAULTS: dict = {
    "oledMode": False,
    "lightMode": False,
    "roundness": 16,
    "font": "Roboto Condensed",
    "fontSize": 14,
    "monoFont": "Iosevka Nerd Font Mono",
    "monoFontSize": 14,
    "tintIcons": False,
    "enableCorners": True,
    "animDuration": 300,
    "shadowOpacity": 0.5,
    "shadowColor": "shadow",
    "shadowXOffset": 0,
    "shadowYOffset": 0,
    "shadowBlur": 1,
    **THEME_VARIANTS,
}


def theme_path() -> Path:
    return shell_config_dir() / "theme.json"


def load_theme() -> dict:
    return load_shell_json("theme", THEME_DEFAULTS)


def save_theme(data: dict) -> None:
    save_shell_json("theme", data)


# ── ai.json ──────────────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/ai.js`` and the
# JsonAdapter defaults in ``Config.qml`` (lines ~1174-1181). The Sidebar
# settings page only edits the ``sidebar*`` keys, but the full schema is
# kept here so a load-then-save round trip preserves the unrelated keys
# (systemPrompt, tool, extraModels, defaultModel).
AI_DEFAULTS: dict = {
    "systemPrompt": "You are a helpful assistant running on a Linux system. You have access to some tools to control the system.",
    "tool": "none",
    "extraModels": [],
    "defaultModel": "gemini-2.0-flash",
    "sidebarWidth": 400,
    "sidebarPosition": "right",
    "sidebarPinnedOnStartup": False,
}


def ai_path() -> Path:
    return shell_config_dir() / "ai.json"


def load_ai() -> dict:
    return load_shell_json("ai", AI_DEFAULTS)


def save_ai(data: dict) -> None:
    save_shell_json("ai", data)


# ── notch.json ──────────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/notch.js`` and the
# JsonAdapter defaults in ``Config.qml`` (lines ~672-680).
NOTCH_DEFAULTS: dict = {
    "position": "top",
    "theme": "default",
    "hoverRegionHeight": 8,
    "keepHidden": False,
    "disableHoverExpansion": True,
    "noMediaDisplay": "userHost",
    "customText": "RetroLinux",
}


def notch_path() -> Path:
    return shell_config_dir() / "notch.json"


def load_notch() -> dict:
    return load_shell_json("notch", NOTCH_DEFAULTS)


def save_notch(data: dict) -> None:
    save_shell_json("notch", data)


# ── workspaces.json ─────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/workspaces.js`` and the
# JsonAdapter defaults in ``Config.qml`` (lines ~587-593).
WORKSPACES_DEFAULTS: dict = {
    "shown": 10,
    "showAppIcons": True,
    "alwaysShowNumbers": False,
    "showNumbers": False,
    "dynamic": False,
}


def workspaces_path() -> Path:
    return shell_config_dir() / "workspaces.json"


def load_workspaces() -> dict:
    return load_shell_json("workspaces", WORKSPACES_DEFAULTS)


def save_workspaces(data: dict) -> None:
    save_shell_json("workspaces", data)
