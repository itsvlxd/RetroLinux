"""Minimal ANSI color helper. Disabled globally via disable(), which
--no-color wires up; also auto-disables when stderr isn't a TTY so piped
output stays clean."""

from __future__ import annotations

import sys
import unicodedata

_ENABLED = sys.stderr.isatty()

_CODES = {
    "reset": "0",
    "bold": "1",
    "dim": "2",
    "italic": "3",
    "underline": "4",
    # standard
    "black": "30",
    "red": "31",
    "green": "32",
    "yellow": "33",
    "blue": "34",
    "magenta": "35",
    "cyan": "36",
    "white": "37",
    # bright
    "bright_black": "90",
    "bright_red": "91",
    "bright_green": "92",
    "bright_yellow": "93",
    "bright_blue": "94",
    "bright_magenta": "95",
    "bright_cyan": "96",
    "bright_white": "97",
}


def disable() -> None:
    global _ENABLED
    _ENABLED = False


def sanitize(text: str) -> str:
    """Strip terminal control characters (ANSI escapes, backspace, carriage
    return, etc.) from a string before printing it. Use this on any value
    that came from the peer -- a device name (mdns/discover.py), a filename
    (IntroductionFrame.file_metadata) -- since those are attacker-controlled
    and would otherwise let a malicious device manipulate our terminal output
    (clear the screen, overwrite prior lines, spoof a fake prompt) via
    embedded escape sequences. Printable Unicode (accents, emoji, CJK, etc.)
    is preserved; only the Unicode "Cc" (control) and "Cf" (format, e.g.
    bidi overrides) categories are removed. Not needed for values we
    generate ourselves (our own device name, error messages)."""
    return "".join(ch for ch in text if unicodedata.category(ch) not in ("Cc", "Cf"))


def _wrap(text: str, *codes: str) -> str:
    if not _ENABLED:
        return text
    prefix = "".join(f"\033[{_CODES[c]}m" for c in codes)
    return f"{prefix}{text}\033[{_CODES['reset']}m"


def bold(text: str) -> str:
    return _wrap(text, "bold")


def dim(text: str) -> str:
    return _wrap(text, "dim")


def italic(text: str) -> str:
    return _wrap(text, "italic")


def underline(text: str) -> str:
    return _wrap(text, "underline")


def black(text: str) -> str:
    return _wrap(text, "black")


def red(text: str) -> str:
    return _wrap(text, "red")


def green(text: str) -> str:
    return _wrap(text, "green")


def yellow(text: str) -> str:
    return _wrap(text, "yellow")


def blue(text: str) -> str:
    return _wrap(text, "blue")


def magenta(text: str) -> str:
    return _wrap(text, "magenta")


def cyan(text: str) -> str:
    return _wrap(text, "cyan")


def white(text: str) -> str:
    return _wrap(text, "white")


def bright_black(text: str) -> str:
    return _wrap(text, "bright_black")


def bright_red(text: str) -> str:
    return _wrap(text, "bright_red")


def bright_green(text: str) -> str:
    return _wrap(text, "bright_green")


def bright_yellow(text: str) -> str:
    return _wrap(text, "bright_yellow")


def bright_blue(text: str) -> str:
    return _wrap(text, "bright_blue")


def bright_magenta(text: str) -> str:
    return _wrap(text, "bright_magenta")


def bright_cyan(text: str) -> str:
    return _wrap(text, "bright_cyan")


def bright_white(text: str) -> str:
    return _wrap(text, "bright_white")
