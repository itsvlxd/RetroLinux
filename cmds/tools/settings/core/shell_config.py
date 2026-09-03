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

# Toolbox items shown in the shell's ToolsMenu (``ToolsMenu.qml``).
# ``package`` names the binary whose presence enables the tool; when it is
# missing the tool greys out in the settings page (but stays draggable) and
# the shell skips it until the package is installed.
TOOLBOX_ITEMS: dict = {
    "screenshot": ("Screenshot", "Capture the whole screen", "camera-photo-symbolic", None),
    "screenshots": ("Open Screenshots", "Browse the screenshots folder", "image-x-generic-symbolic", None),
    "recorder": ("Screen Recorder", "Record the screen", "media-record-symbolic", None),
    "recordings": ("Open Recordings", "Browse the recordings folder", "video-x-generic-symbolic", None),
    "colorpicker": ("Color Picker", "Pick a color from the screen", "color-select-symbolic", None),
    "ocr": ("OCR", "Recognize text on screen", "text-x-generic-symbolic", "tesseract"),
    "qr": ("QR Code", "Scan a QR code", "view-barcode-symbolic", "zbarimg"),
    "lens": ("Google Lens", "Reverse image search", "system-search-symbolic", None),
    "shazam": ("Shazam", "Recognize playing music", "shazam-symbolic", "songrec"),
    "webcam": ("Webcam Overlay", "Floating webcam preview", "camera-video-symbolic", None),
    "docker": ("Docker Manager", "Monitor and manage Docker containers", "utilities-system-monitor-symbolic", "docker"),
}

# Default toolbox order mirrors the current hardcoded layout in ToolsMenu.qml.
TOOLBOX_DEFAULT_ORDER: list = [
    "screenshot", "screenshots", "separator",
    "recorder", "recordings", "separator",
    "colorpicker", "ocr", "qr", "lens", "shazam", "webcam", "docker",
]

TOOLBOX_MIN_ITEMS = 5

# Sections inside the clock ("Time, Weather & Calendar") popup. Rendered in
# the order listed by ``Clock.qml``; ``clockOrder`` in bar.json controls the
# popup section order. Each id maps to one section component in Clock.qml.
CLOCK_ITEMS: dict = {
    "clock": ("Time & Calendar", "Time and date card with the month calendar", "clock-symbolic"),
    "weather": ("Weather", "Live conditions and the 7-day forecast", "weather-clear-symbolic"),
    "pomodoro": ("Pomodoro", "Focus timer", "hourglass-symbolic"),
}

# Default order mirrors the hardcoded layout in Clock.qml's popup.
CLOCK_DEFAULT_ORDER: list = ["clock", "weather", "pomodoro"]

CLOCK_MIN_ITEMS = 1

# Bar items that can be reordered / shown-hide on each side of the shell bar.
# Mirrors the components rendered in ``BarContent.qml``. Weather is part of the
# Clock widget (symbol + temperature), so it is not a standalone item.
BAR_LEFT_ITEMS: dict = {
    "launcher": ("Launcher", "Open the app launcher", "start-here-symbolic"),
    "workspaces": ("Workspaces", "Switch between workspaces", "view-grid-symbolic"),
    "layout": ("Layout Selector", "Change the tiling layout", "view-list-symbolic"),
    "pin": ("Pin Button", "Pin or unpin the bar", "pin-symbolic"),
}

BAR_RIGHT_ITEMS: dict = {
    "presets": ("Presets", "Open the presets manager", "emblem-system-symbolic"),
    "tools": ("Toolbox", "Open the tools menu", "applications-utilities-symbolic"),
    "tray": ("System Tray", "Show StatusNotifier tray icons", "emblem-system-symbolic"),
    "wifi": ("Wi-Fi", "Open the Wi-Fi panel", "network-wireless-symbolic"),
    "bluetooth": ("Bluetooth", "Open the Bluetooth panel", "bluetooth-symbolic"),
    "quickshare": ("Quick Share", "Open the Quick Share panel", "emblem-shared-symbolic"),
    "controls": ("Audio Controls", "Volume, brightness and microphone", "audio-speakers-symbolic"),
    "battery": ("Battery", "Show battery level", "battery-symbolic"),
    "clock": ("Time, Weather & Calendar", "Time, date, calendar and weather", "clock-symbolic"),
    "power": ("Power Button", "Open the power menu", "system-shutdown-symbolic"),
    "typingSounds": ("Typing Sounds", "Mechanical keyboard typing sounds", "input-keyboard-symbolic"),
    "docker": ("Docker", "Monitor and manage Docker containers", "utilities-system-monitor-symbolic"),
}

# Unified catalog of every reorderable bar item (left + right), so an item keeps
# its title/description/icon no matter which side it is dragged onto.
BAR_ITEMS: dict = {**BAR_LEFT_ITEMS, **BAR_RIGHT_ITEMS}

# Default left/right order mirrors the hardcoded layout in BarContent.qml.
# The layout selector, presets and quick share items are hidden by default
# (but still addable via the settings UI).
BAR_LEFT_DEFAULT_ORDER: list = ["launcher", "workspaces", "pin"]
BAR_RIGHT_DEFAULT_ORDER: list = [
    "tools", "tray", "wifi", "bluetooth",
    "controls", "battery", "clock", "power",
]

BAR_MIN_ITEMS = 0

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
    "scale": 1.0,
    "barPaddingTop": 4,
    "barPaddingRight": 4,
    "barPaddingBottom": 4,
    "barPaddingLeft": 4,
    "showWeatherTemp": False,
    "showDayOfWeek": False,
    "batteryStyle": "arch",
    "toolboxOrder": list(TOOLBOX_DEFAULT_ORDER),
    "clockOrder": list(CLOCK_DEFAULT_ORDER),
    "barLeftOrder": list(BAR_LEFT_DEFAULT_ORDER),
    "barRightOrder": list(BAR_RIGHT_DEFAULT_ORDER),
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
    "emojiFont": "Noto Color Emoji",
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
    "enabled": True,
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
    "scale": 1.0,
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
    "showIcons": True,
    "iconSize": 40,
    "spacingVertical": 16,
    "textColor": "overBackground",
    "editMode": False,
    "perMonitor": False,
    "widgetOrder": [],
    "widgets": [],
}

# Catalog of desktop widgets the user can add/remove.
# ``id`` -> (label, description, icon). Extend this list to add more widgets.
DESKTOP_WIDGET_CATALOG: dict = {
    "calendar": ("Calendar 4x4", "Large square month calendar", "x-office-calendar-symbolic"),
    "calendar2x4": ("Calendar 2x4", "Wide compact month calendar", "x-office-calendar-symbolic"),
    "weather": ("Weather", "Animated weather scene with 7-day forecast", "weather-clear-symbolic"),
    "weather2x4": ("Weather 2x4", "Wide weather card with condition disc and forecast", "weather-clear-symbolic"),
    "weather2x2": ("Weather 2x2", "Simple square animated weather card", "weather-clear-symbolic"),
    "music2x2": ("Music Player 2x2", "Square music player with artwork and controls", "multimedia-player-symbolic"),
    "music2x4": ("Music Player 2x4", "Tall music player with circular seek disc and controls", "multimedia-player-symbolic"),
    "clockdigital": ("Digital Clock", "Big time and date", "appointment-new-symbolic"),
    "clockanalog": ("Analog Clock", "Circular clock face with hands", "appointment-new-symbolic"),
    "worldclock": ("World Clock", "Up to 4 timezones side by side", "appointment-new-symbolic"),
    "storage": ("Device Storage", "Apple-style storage breakdown card", "drive-harddisk-symbolic"),
    "storage2x4": ("Device Storage 2x4", "Wide storage card with per-category sizes", "drive-harddisk-symbolic"),
    "network": ("Network Monitor", "Live bandwidth, sparkline and IPs", "network-wireless-symbolic"),
    "network2x4": ("Network Monitor 2x4", "Wide bandwidth card with big sparkline", "network-wireless-symbolic"),
    "network1x4": ("Network Monitor Slim", "Slim horizontal bandwidth strip", "network-wireless-symbolic"),
    "network1x3": ("Network Monitor 1x3", "Compact strip with speeds and toggle", "network-wireless-symbolic"),
    "power": ("Power & Performance", "Power draw, thermals and profile switcher", "battery-level-80-symbolic"),
    "power1x3": ("Power & Performance 1x3", "Slim strip with profile switcher", "battery-level-80-symbolic"),
    "bluetooth": ("Bluetooth", "Connected devices, battery and quick pair", "bluetooth-symbolic"),
    "note": ("Note", "Pinned editable note on the desktop", "text-x-generic-symbolic"),
    "batteryring": ("Battery Rings", "Apple-style circular battery gauge", "battery-symbolic"),
    "batteryring2x4": ("Battery Rings 2x4", "Battery rings for up to 4 devices", "battery-symbolic"),
    "feed": ("Dev Feed", "Full-cover article feed (DEV.to / Hacker News / daily.dev)", "globe-symbolic"),
    "sysmonitor": ("System Monitor", "CPU, RAM and disk usage", "utilities-system-monitor-symbolic"),
    "sysmonitor2x4": ("System Monitor 2x4", "CPU/GPU/RAM sparkline graph", "utilities-system-monitor-symbolic"),
    "battery": ("Battery", "Battery level and charging state", "battery-symbolic"),
    "photo": ("Photo 2x2", "Display an image on your desktop", "image-x-generic-symbolic"),
    "photo2x4": ("Photo 2x4", "Display a wide image on your desktop", "image-x-generic-symbolic"),
    "photo4x2": ("Photo 4x2", "Display a portrait image on your desktop", "image-x-generic-symbolic"),
}

# Fixed default size (px) for each widget type, used when none is stored.
DESKTOP_WIDGET_SIZES: dict = {
    "calendar": (320, 320),
    "calendar2x4": (320, 160),
    "weather": (320, 240),
    "weather2x4": (320, 160),
    "weather2x2": (160, 160),
    "music2x2": (160, 160),
    "music2x4": (320, 160),
    "clockdigital": (160, 160),
    "clockanalog": (160, 160),
    "worldclock": (320, 160),
    "storage": (160, 160),
    "storage2x4": (320, 160),
    "network": (160, 160),
    "network2x4": (320, 160),
    "network1x4": (320, 80),
    "network1x3": (240, 80),
    "power": (160, 160),
    "power1x3": (240, 80),
    "bluetooth": (160, 160),
    "note": (160, 160),
    "batteryring": (160, 160),
    "batteryring2x4": (320, 160),
    "feed": (320, 160),
    "sysmonitor": (160, 160),
    "sysmonitor2x4": (320, 160),
    "battery": (160, 160),
    "photo": (160, 160),
    "photo2x4": (320, 160),
    "photo4x2": (160, 320),
}

DESKTOP_MIN_WIDGETS = 0


def desktop_path() -> Path:
    return shell_config_dir() / "desktop.json"


def load_desktop() -> dict:
    return load_shell_json("desktop", DESKTOP_DEFAULTS)


def save_desktop(data: dict) -> None:
    save_shell_json("desktop", data)


# ── desktop_widgets.json ────────────────────────────────────────────────
# Dedicated file for desktop widget instances. Kept separate from
# desktop.json because Quickshell's JsonAdapter does not load top-level
# array properties; the shell's DesktopWidgets reads/writes this file with
# manual JSON so the widget list/positions round-trip reliably.

def desktop_widgets_path() -> Path:
    return shell_config_dir() / "desktop_widgets.json"


def load_desktop_widgets() -> list[dict]:
    """Return the list of desktop widget instances ``[{id,type,x,y,width,height}]``."""
    try:
        data = json.loads(desktop_widgets_path().read_text())
    except (json.JSONDecodeError, OSError):
        return []
    if isinstance(data, dict) and isinstance(data.get("widgets"), list):
        return data["widgets"]
    return []


def save_desktop_widgets(widgets: list[dict]) -> None:
    """Atomically write the desktop widget instances to desktop_widgets.json."""
    path = desktop_widgets_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".desktop_widgets.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"widgets": widgets}, fh, indent=1)
            fh.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


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
    "showCoverArt": True,
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
    "dashboard.json",
    "desktop.json",
    "dock.json",
    "compositor.json",
    "lockscreen.json",
    "notch.json",
    "overview.json",
    "performance.json",
    "theme.json",
    "tools.json",
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
        for d in sorted(bundled.iterdir(), key=lambda p: (p.name != "RetroLinux", p.name)):
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
    """Overwrite a user preset's files with current shell config.

    Copies every managed file present in the live config into the preset,
    creating any that the preset doesn't already have (e.g. a newly-added
    config file such as ``dashboard.json``) so presets stay complete and in
    sync after the list of managed files grows.
    """
    dst = Path(preset["path"])
    src = shell_config_dir()
    dst.mkdir(parents=True, exist_ok=True)
    for f in _PRESET_FILES:
        s = src / f
        if s.exists():
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


# ── dashboard.json ───────────────────────────────────────────────────────

# Mirrors ``modules/retroshell/files/config/defaults/dashboard.js`` and the
# JsonAdapter defaults in ``Config.qml``. Controls the dashboard launcher
# tab: the horizontal order of the widget groups and the QuickControls
# hot-action buttons. Groups are all reorderable but never removable; the
# QuickControls buttons can be added/removed down to DASHBOARD_MIN_CONTROLS.
DASHBOARD_WIDGET_IDS = ("player", "quickactions", "notifications", "controls")
DASHBOARD_CONTROL_IDS = ("wifi", "bluetooth", "quickshare", "caffeine", "typingSounds", "darkmode", "nightlight")
DASHBOARD_MIN_CONTROLS = 5

DASHBOARD_DEFAULTS: dict = {
    "widgetOrder": list(DASHBOARD_WIDGET_IDS),
    "controlOrder": list(DASHBOARD_CONTROL_IDS),
}


def dashboard_path() -> Path:
    return shell_config_dir() / "dashboard.json"


def load_dashboard() -> dict:
    return load_shell_json("dashboard", DASHBOARD_DEFAULTS)


def save_dashboard(data: dict) -> None:
    save_shell_json("dashboard", data)


# ── notifications.json ─────────────────────────────────────────────────

NOTIFICATIONS_DEFAULTS: dict = {
    "soundEnabled": True,
    "soundFile": "retro-default.mp3",
    "soundVolume": 40,
}


def notifications_path() -> Path:
    return shell_config_dir() / "notifications.json"


def load_notifications() -> dict:
    return load_shell_json("notifications", NOTIFICATIONS_DEFAULTS)


def save_notifications(data: dict) -> None:
    save_shell_json("notifications", data)


# ── typing_sounds.json ────────────────────────────────────────────────

# Bundled sound pack directory inside the retroshell module.
TYPING_SOUNDS_PACKS_DIR = Path("/opt/retrolinux/modules/retroshell/files/assets/typing-sounds-soundpacks")

# Catalog of bundled sound packs: id -> display name.
# Scanned dynamically at runtime; this dict provides fallback names.
TYPING_SOUNDS_PACK_NAMES: dict = {
    "nk-cream": "NK Cream",
    "cherrymx-black-abs": "Cherry MX Black (ABS)",
    "cherrymx-black-pbt": "Cherry MX Black (PBT)",
    "cherrymx-blue-abs": "Cherry MX Blue (ABS)",
    "cherrymx-blue-pbt": "Cherry MX Blue (PBT)",
    "cherrymx-brown-abs": "Cherry MX Brown (ABS)",
    "cherrymx-brown-pbt": "Cherry MX Brown (PBT)",
    "cherrymx-red-abs": "Cherry MX Red (ABS)",
    "cherrymx-red-pbt": "Cherry MX Red (PBT)",
    "cream-travel": "Cream Travel",
    "eg-crystal-purple": "EG Crystal Purple",
    "eg-oreo": "EG Oreo",
    "holy-pandas": "Holy Pandas",
    "mxblack-travel": "MX Black Travel",
    "mxblue-travel": "MX Blue Travel",
    "mxbrown-travel": "MX Brown Travel",
    "topre-purple-hybrid-pbt": "Topre Purple Hybrid (PBT)",
    "turquoise": "Turquoise",
}

TYPING_SOUNDS_DEFAULTS: dict = {
    "enabled": False,
    "volume": 100,
    "mouseEnabled": False,
    "selectedPackId": "nk-cream",
    "selectedDevicePath": "all",
}


def typing_sounds_path() -> Path:
    return shell_config_dir() / "typing_sounds.json"


def load_typing_sounds() -> dict:
    return load_shell_json("typing_sounds", TYPING_SOUNDS_DEFAULTS)


def save_typing_sounds(data: dict) -> None:
    save_shell_json("typing_sounds", data)


def scan_typing_sound_packs() -> list[dict]:
    """Return list of {id, name} for every bundled sound pack."""
    packs: list[dict] = []
    if not TYPING_SOUNDS_PACKS_DIR.is_dir():
        return packs
    for d in sorted(TYPING_SOUNDS_PACKS_DIR.iterdir()):
        if not d.is_dir():
            continue
        config_file = d / "config.json"
        if config_file.exists():
            try:
                import json
                cfg = json.loads(config_file.read_text())
                name = cfg.get("name", d.name)
            except (json.JSONDecodeError, OSError):
                name = TYPING_SOUNDS_PACK_NAMES.get(d.name, d.name)
        else:
            name = TYPING_SOUNDS_PACK_NAMES.get(d.name, d.name)
        packs.append({"id": d.name, "name": name})
    return packs
