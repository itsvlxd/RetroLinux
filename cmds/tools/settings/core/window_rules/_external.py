"""Read-only loader for window rules from outside settings's managed file.

The Window Rules page surfaces these so users see the full picture of
what's affecting their windows — but read-only. Hyprland has no
``unwindowrule`` IPC, so we can't offer the override action the Binds
page uses; the source path + line number are preserved so the UI can
point users at the file they need to edit by hand.
"""

from dataclasses import dataclass
from pathlib import Path

from settings.core import config
from settings.core.external import load_external_rule_entries
from settings.core.window_rules._model import WindowRule
from settings.core.window_rules._parse import from_rule_node


@dataclass(frozen=True, slots=True)
class ExternalWindowRule:
    """A windowrule from a config file outside settings's managed file."""

    rule: WindowRule
    source_path: Path
    lineno: int


def load_external_window_rules(
    root_path: Path,
    managed_path: Path,
) -> list[ExternalWindowRule]:
    """Walk *root_path* and its sourced files for windowrule entries
    that don't live in *managed_path*.

    *root_path* is typically ``~/.config/hypr/hyprland.conf`` (the
    file Hyprland actually loads); *managed_path* is whichever file
    settings owns — the path is user-configurable via the
    ``settings.config-path`` setting, so the loader takes it as a
    parameter rather than assuming a fixed filename. Lines are returned
    in document order — the order Hyprland evaluates them, which
    matters because the last matching rule wins for a given effect.

    Hyprland reads our managed file via ``source = …`` after
    everything in *root_path*, so anything in this list is
    semantically "earlier" than the user's settings-authored rules:
    a competing rule in our managed list silently wins. The UI
    documents this so users debugging a non-applying rule know to
    check what's already been "won" against.

    Failures (root file missing, parse errors, OS errors) return an
    empty list — external rules are advisory display, not load-bearing,
    so failing silently is safer than blocking the page on a flaky
    config.
    """
    entries = load_external_rule_entries(root_path, managed_path, (config.KEYWORD_WINDOWRULE,))
    external: list[ExternalWindowRule] = []
    for entry in entries:
        wr = from_rule_node(entry.rule)
        if wr is None:
            continue
        external.append(
            ExternalWindowRule(
                rule=wr,
                source_path=entry.source_path,
                lineno=entry.lineno,
            )
        )
    return external
