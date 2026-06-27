"""Shared helpers for loading external (read-only) keyword entries.

These loaders are advisory UI data only: any load/parse failure degrades to
an empty list instead of surfacing an error to users.
"""

from dataclasses import dataclass
from pathlib import Path

import hyprland_config
from hyprland_config import Rule


@dataclass(frozen=True, slots=True)
class ExternalKeywordEntry:
    """One keyword occurrence from outside settings's managed config file."""

    key: str
    value: str
    source_path: Path
    lineno: int


def load_external_keyword_entries(
    root_path: Path,
    managed_path: Path,
    keywords: tuple[str, ...],
    *,
    migrate_doc: bool = False,
) -> list[ExternalKeywordEntry]:
    """Load keyword entries from *root_path* + sources, excluding *managed_path*.

    Set ``migrate_doc=True`` when callers need ``hyprland_config.migrate`` to
    normalize deprecated syntax before parsing individual lines.
    """
    if not root_path.exists():
        return []
    try:
        doc = hyprland_config.load_any(root_path, follow_sources=True, lenient=True)
    except (OSError, hyprland_config.ParseError, hyprland_config.SourceCycleError):
        return []

    if migrate_doc:
        hyprland_config.migrate(doc)

    # ``doc.find_all`` reports source paths in their resolved form
    # (symlinks followed) but ``managed_path`` may carry a user-style
    # path through ``~/.config`` that resolves to a dotfiles checkout.
    # Compare resolved forms so the managed file isn't accidentally
    # surfaced as "external".
    try:
        managed_resolved = managed_path.resolve()
    except OSError:
        managed_resolved = managed_path
    external: list[ExternalKeywordEntry] = []
    for keyword in keywords:
        for entry in doc.find_all(keyword):
            entry_path = Path(entry.source_name)
            try:
                entry_resolved = entry_path.resolve()
            except OSError:
                entry_resolved = entry_path
            if entry_resolved == managed_resolved:
                continue
            external.append(
                ExternalKeywordEntry(
                    key=entry.key,
                    value=entry.value,
                    source_path=entry_path,
                    lineno=entry.lineno,
                )
            )
    return external


@dataclass(frozen=True, slots=True)
class ExternalRuleEntry:
    """One structured :class:`Rule` occurrence from outside settings's managed file."""

    rule: Rule
    source_path: Path
    lineno: int


def load_external_rule_entries(
    root_path: Path,
    managed_path: Path,
    kinds: tuple[str, ...],
) -> list[ExternalRuleEntry]:
    """Load structured :class:`Rule` nodes from *root_path* + sources,
    excluding *managed_path*.

    ``kinds`` is the tuple of rule kinds to surface (``("windowrule",)``
    or ``("layerrule",)``). The document is migrated in-memory so the
    Rule nodes carry the canonical post-migration shape; on parse
    failure the loader returns an empty list to keep the page populated
    rather than blocking on a flaky external config.
    """
    if not root_path.exists():
        return []
    try:
        doc = hyprland_config.load_any(root_path, follow_sources=True, lenient=True)
    except (OSError, hyprland_config.ParseError, hyprland_config.SourceCycleError):
        return []

    hyprland_config.migrate(doc)

    try:
        managed_resolved = managed_path.resolve()
    except OSError:
        managed_resolved = managed_path

    kinds_set = frozenset(kinds)
    external: list[ExternalRuleEntry] = []
    for _owning_doc, line in doc.iter_lines(recursive=True):
        if not isinstance(line, Rule) or line.kind not in kinds_set:
            continue
        entry_path = Path(line.source_name)
        try:
            entry_resolved = entry_path.resolve()
        except OSError:
            entry_resolved = entry_path
        if entry_resolved == managed_resolved:
            continue
        external.append(ExternalRuleEntry(rule=line, source_path=entry_path, lineno=line.lineno))
    return external
