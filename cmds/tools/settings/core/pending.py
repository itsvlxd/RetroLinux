"""Shared data shape for unsaved-change entries.

:class:`PendingChange` is what section pages yield from
``iter_pending_changes()`` and what :mod:`settings.pages.pending` renders
in the per-category groups. Lives in :mod:`settings.core` so section
pages can depend on the data shape without pulling in the rendering page.
"""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Literal

ChangeKind = Literal["modified", "added", "removed"]


@dataclass(slots=True)
class PendingChange:
    """A single unsaved item surfaced in the pending-changes list."""

    category: str
    title: str
    subtitle: str
    revert: Callable[[], None]
    navigate_to: str | None = None
    icon: str = "preferences-system-symbolic"
    kind: ChangeKind = "modified"
    # Schema option key to focus and flash on navigation, when applicable.
    target_key: str | None = None
