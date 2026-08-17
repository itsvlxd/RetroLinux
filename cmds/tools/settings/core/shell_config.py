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
import shutil
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
    "showLayoutChanger": True,
    "showPresetsButton": True,
    "showWeatherTemp": False,
    "showDayOfWeek": False,
    "batteryStyle": "arch",
    "showWifiPopup": False,
    "showBluetoothPopup": False,
    "showQuickSharePopup": False,
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
    "quickshareEnabled": False,
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


# ── overview.json ───────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/overview.js``.
OVERVIEW_DEFAULTS: dict = {
    "rows": 2,
    "columns": 5,
    "scale": 0.15,
    "workspaceSpacing": 8,
}


def overview_path() -> Path:
    return shell_config_dir() / "overview.json"


def load_overview() -> dict:
    return load_shell_json("overview", OVERVIEW_DEFAULTS)


def save_overview(data: dict) -> None:
    save_shell_json("overview", data)


# ── dock.json ───────────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/dock.js``.
# Only settings exposed in ShellPanel.qml's Dock section are included;
# ``ignoredAppRegexes`` and ``screenList`` are complex list types the shell
# panel itself exposes via custom widgets — they are left to the QML side.
DOCK_DEFAULTS: dict = {
    "enabled": True,
    "position": "bottom",
    "theme": "default",
    "height": 48,
    "iconSize": 24,
    "spacing": 4,
    "margin": 4,
    "hoverToReveal": True,
    "hoverRegionHeight": 16,
    "pinnedOnStartup": False,
    "showPinButton": True,
    "availableOnFullscreen": False,
    "keepHidden": False,
    "showRunningIndicators": True,
    "showOverviewButton": True,
}


def dock_path() -> Path:
    return shell_config_dir() / "dock.json"


def load_dock() -> dict:
    return load_shell_json("dock", DOCK_DEFAULTS)


def save_dock(data: dict) -> None:
    save_shell_json("dock", data)


# ── desktop.json ────────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/desktop.js``.
DESKTOP_DEFAULTS: dict = {
    "enabled": False,
    "iconSize": 40,
    "spacingVertical": 16,
    "textColor": "overBackground",
}


def desktop_path() -> Path:
    return shell_config_dir() / "desktop.json"


def load_desktop() -> dict:
    return load_shell_json("desktop", DESKTOP_DEFAULTS)


def save_desktop(data: dict) -> None:
    save_shell_json("desktop", data)


# ── system.json (Misc/OCR) ──────────────────────────────────────────────

# OCR defaults from ``modules/retroshell/files/config/defaults/system.js``.
# Only the ``ocr`` sub-object is managed by the Misc page; the rest of
# system.json (idle, pomodoro, disks, …) is preserved untouched via deep
# merge on load and partial update on save.
SYSTEM_OCR_DEFAULTS: dict = {
    "eng": True,
    "spa": True,
    "lat": False,
    "jpn": False,
    "chi_sim": False,
    "chi_tra": False,
    "kor": False,
    "deu": False,
    "fra": False,
    "pol": False,
    "ron": False,
    "swe": False,
}


def system_path() -> Path:
    return shell_config_dir() / "system.json"


def load_system() -> dict:
    """Return the full system.json merged over partial defaults.

    Returns the entire document so callers can reach nested keys like
    ``ocr``, ``idle``, ``pomodoro`` and ``disks``. The ``ocr`` sub-object
    always resolves because ``SYSTEM_OCR_DEFAULTS`` provides it.
    """
    return load_shell_json("system", {"ocr": SYSTEM_OCR_DEFAULTS})


def save_system(data: dict) -> None:
    """Write *data* back to system.json, preserving unknown top-level keys.

    Merges *data* on top of the on-disk file so nested objects the Misc
    page doesn't touch (idle, pomodoro, disks, …) survive the round-trip.
    """
    path = shell_config_dir() / "system.json"
    existing: dict = {}
    try:
        existing = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        pass
    if not isinstance(existing, dict):
        existing = {}
    save_shell_json("system", _deep_merge(existing, data))


# ── weather.json ────────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/weather.js``.
WEATHER_DEFAULTS: dict = {
    "location": "",
    "unit": "C",
}


def weather_path() -> Path:
    return shell_config_dir() / "weather.json"


def load_weather() -> dict:
    return load_shell_json("weather", WEATHER_DEFAULTS)


def save_weather(data: dict) -> None:
    save_shell_json("weather", data)


# ── performance.json ───────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/performance.js``.
PERFORMANCE_DEFAULTS: dict = {
    "blurTransition": True,
    "windowPreview": True,
    "wavyLine": True,
    "rotateCoverArt": True,
    "dashboardPersistTabs": True,
    "dashboardMaxPersistentTabs": 2,
}


def performance_path() -> Path:
    return shell_config_dir() / "performance.json"


def load_performance() -> dict:
    return load_shell_json("performance", PERFORMANCE_DEFAULTS)


def save_performance(data: dict) -> None:
    save_shell_json("performance", data)


# ── presets ─────────────────────────────────────────────────────────────

# Mirrors ``PresetsService.qml`` preset file handling.
# Bundled presets ship at ``modules/retroshell/files/assets/presets/``;
# user presets live under the shell config dir at ``presets/``.
_PRESET_FILES = (
    "bar.json",
    "desktop.json",
    "dock.json",
    "compositor.json",
    "lockscreen.json",
    "notch.json",
    "overview.json",
    "performance.json",
    "theme.json",
    "workspaces.json",
)

_BUNDLED_PRESETS_DIR = Path("/opt/retrolinux/modules/retroshell/files/assets/presets")


def _resolve_retro_dir() -> Path:
    """Best-effort resolution of the RetroLinux install root."""
    candidate = os.environ.get("RETRO_DIR", "/opt/retrolinux")
    return Path(candidate)


def user_presets_dir() -> Path:
    return shell_config_dir() / "presets"


def active_preset_file() -> Path:
    return user_presets_dir() / "active_preset"


def read_active_preset() -> str:
    """Return the currently active preset name, or empty string."""
    path = active_preset_file()
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def _read_info(preset_dir: Path) -> dict:
    info = preset_dir / "info.json"
    try:
        data = json.loads(info.read_text())
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        return {}


def _has_config_files(preset_dir: Path) -> bool:
    return any((preset_dir / f).exists() for f in _PRESET_FILES)


def scan_presets() -> list[dict]:
    """Return sorted list of ``{name, path, is_official, info}`` dicts."""
    presets: list[dict] = []
    seen: set[str] = set()

    # Bundled (official) presets
    bundled = _BUNDLED_PRESETS_DIR
    if bundled.is_dir():
        for d in sorted(bundled.iterdir()):
            if d.is_dir() and _has_config_files(d):
                seen.add(d.name)
                presets.append({
                    "name": d.name,
                    "path": str(d),
                    "is_official": True,
                    "info": _read_info(d),
                })

    # User presets
    user = user_presets_dir()
    if user.is_dir():
        for d in sorted(user.iterdir()):
            if d.is_dir() and _has_config_files(d) and d.name not in seen:
                presets.append({
                    "name": d.name,
                    "path": str(d),
                    "is_official": False,
                    "info": _read_info(d),
                })

    return presets


def apply_preset(preset: dict) -> None:
    """Copy all config files from *preset*'s dir into the shell config dir."""
    src = Path(preset["path"])
    dst = shell_config_dir()
    for f in _PRESET_FILES:
        s = src / f
        if s.exists():
            shutil.copy2(s, dst / f)
    # Mark as active
    af = active_preset_file()
    af.parent.mkdir(parents=True, exist_ok=True)
    af.write_text(preset["name"] + "\n")


def save_preset(name: str, author: str = "", author_url: str = "") -> None:
    """Create a new user preset from the current shell config."""
    dst_dir = user_presets_dir() / name
    dst_dir.mkdir(parents=True, exist_ok=True)
    src_dir = shell_config_dir()
    for f in _PRESET_FILES:
        s = src_dir / f
        if s.exists():
            shutil.copy2(s, dst_dir / f)
    info = dst_dir / "info.json"
    info.write_text(
        json.dumps(
            {"author": author or "User", "authorUrl": author_url or ""},
            indent=2,
        )
        + "\n"
    )


def delete_preset(name: str) -> None:
    """Delete a user preset directory."""
    d = user_presets_dir() / name
    if d.is_dir():
        shutil.rmtree(d)
    # Clear active if it was the deleted one
    if read_active_preset() == name:
        af = active_preset_file()
        try:
            af.unlink()
        except OSError:
            pass


def rename_preset(old_name: str, new_name: str) -> None:
    """Rename a user preset directory."""
    old = user_presets_dir() / old_name
    new = user_presets_dir() / new_name
    if old.is_dir():
        old.rename(new)
    if read_active_preset() == old_name:
        af = active_preset_file()
        af.write_text(new_name + "\n")


def update_preset(preset: dict) -> None:
    """Overwrite a user preset's files with current shell config."""
    dst = Path(preset["path"])
    src = shell_config_dir()
    for f in _PRESET_FILES:
        s = src / f
        if s.exists() and (dst / f).exists():
            shutil.copy2(s, dst / f)


def clone_official_preset(name: str) -> None:
    """Copy an official preset into user presets (allows updates)."""
    bundled = _BUNDLED_PRESETS_DIR / name
    dst = user_presets_dir() / name
    # Block re-cloning if it already exists as user preset
    if not dst.exists():
        shutil.copytree(str(bundled), str(dst))


# ── lockscreen.json ─────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/lockscreen.js``.
LOCK_DEFAULTS: dict = {
    "clockFont": "League Gothic",
    "clockFontSize": 240,
    "clockColor": "primaryFixed",
    "clockMinutesColor": "outline",
    "clockDateFontSize": 14,
    "clockDateColor": "primaryFixedDim",
    "clockPosition": "center",
    "clockStyle": "split",
    "passwordPosition": "bottom",
    "musicPosition": "bottom-left",
    "weatherPosition": "bottom-left",
    "powerPosition": "bottom-right",
}


def lockscreen_path() -> Path:
    return shell_config_dir() / "lockscreen.json"


def load_lockscreen() -> dict:
    return load_shell_json("lockscreen", LOCK_DEFAULTS)


def save_lockscreen(data: dict) -> None:
    save_shell_json("lockscreen", data)


# ── tools.json ────────────────────────────────────────────────────────────

TOOLS_DEFAULTS: dict = {
    "screenshotCountdown": 5,
    "previewCountdown": True,
    "screenshotTimerEnabled": False,
    "screenshotsDir": "",
    "recordingsDir": "",
    "recordingResolution": "auto",
    "recordingFps": 60,
    "recordingPortalEnabled": False,
    "emojiShowRecent": True,
    "wallpaperAnimatedPreview": True,
}


def tools_path() -> Path:
    return shell_config_dir() / "tools.json"


def load_tools() -> dict:
    return load_shell_json("tools", TOOLS_DEFAULTS)


def save_tools(data: dict) -> None:
    save_shell_json("tools", data)
