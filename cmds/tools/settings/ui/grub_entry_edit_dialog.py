"""Dialog for editing a single GRUB menu entry (menuentry/submenu block).

Lives outside ``settings/pages/grub.py`` so the page module isn't a
catch-all, matching the existing pattern of reusable dialogs under
``settings/ui/`` (see ``env_var_edit_dialog.py``).

The user edits a title field (structured) and/or the full block text in a
monospace editor (raw). The title field rewrites the quoted title on the
block's first line; the editor is authoritative for the commands.

Apply is gated on:

1. The block passing ``grub-script-check`` (it must remain a valid GRUB
   script fragment), and
2. The block actually differing from the version it was opened with.

A "Revert to template" button removes the manual override for this entry
(visible only when an override already exists).
"""

import os
import re
import subprocess
import tempfile
from collections.abc import Callable

from gi.repository import Adw, Gtk

from settings.ui.dialog import SingletonDialogMixin

# First line: ``menuentry``/``submenu`` keyword, then the quoted title.
_HEADER_TITLE_RE = re.compile(r"^(\s*(?:menuentry|submenu)\s+)([\"'])(.*?)\2")

_MONOSPACE_CSS = "monospace"


def replace_header_title(header: str, new_title: str) -> str:
    """Swap the quoted title in a menuentry/submenu header line.

    Keeps the original quote characters and everything after the closing
    quote (``--class ... {`` etc.) intact.
    """
    match = _HEADER_TITLE_RE.match(header)
    if not match:
        return header
    return header[: match.start(3)] + new_title + header[match.end(3):]


def block_is_valid(block: str) -> bool:
    """Return True if *block* passes ``grub-script-check``."""
    tmp: str | None = None
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".cfg", delete=False) as f:
            f.write(block)
            tmp = f.name
        result = subprocess.run(
            ["grub-script-check", tmp],
            capture_output=True, text=True, timeout=15,
            stdin=subprocess.DEVNULL,
        )
        return result.returncode == 0
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        return False
    finally:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass


class GrubEntryEditDialog(SingletonDialogMixin, Adw.Dialog):
    """Add/edit dialog for one ``menuentry``/``submenu`` block.

    ``entry`` is the parsed block dict from the page (kind/title/id/key/
    text). ``manual`` is the current stored override block, or ``None``
    when the entry is still the template's version. ``on_apply`` receives
    the original ``key`` plus the new block text; ``on_revert`` (optional)
    receives the ``key``.
    """

    def __init__(
        self,
        *,
        entry: dict,
        manual: str | None = None,
        on_apply: Callable[[str, str], None] | None = None,
        on_revert: Callable[[str], None] | None = None,
    ):
        super().__init__()
        self._key = entry["key"]
        self._on_apply_callback = on_apply
        self._on_revert_callback = on_revert
        self._original_block = (manual if manual is not None else entry["text"]).rstrip()
        self._has_override = manual is not None

        self.set_title(f"Edit {entry['kind']} entry")
        self.set_content_width(620)
        self.set_content_height(480)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: self.close())
        header.pack_start(cancel_btn)

        self._apply_btn = Gtk.Button(label="Save")
        self._apply_btn.add_css_class("suggested-action")
        self._apply_btn.connect("clicked", self._on_apply)
        self._apply_btn.set_sensitive(False)
        header.pack_end(self._apply_btn)

        if self._has_override:
            revert_btn = Gtk.Button(label="Revert to template")
            revert_btn.connect("clicked", self._on_revert)
            header.pack_end(revert_btn)
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)

        title_group = Adw.PreferencesGroup(title="Title")
        title_group.set_description("Name shown in the GRUB boot menu")

        self._title_entry = Adw.EntryRow(title="Menu title")
        self._title_entry.set_text(entry["title"])
        self._title_entry.connect("changed", self._on_title_changed)
        title_group.add(self._title_entry)
        content.append(title_group)

        block_group = Adw.PreferencesGroup(
            title="Entry commands",
            description="Full GRUB script block. The first line declares the "
                        "entry; the lines between the braces are the boot commands.",
        )

        self._buffer = Gtk.TextBuffer()
        self._buffer.set_text(self._original_block)
        view = Gtk.TextView()
        view.set_buffer(self._buffer)
        view.set_wrap_mode(Gtk.WrapMode.NONE)
        view.set_monospace(True)
        view.set_editable(True)
        view.add_css_class(_MONOSPACE_CSS)
        view.set_margin_top(8)
        view.set_margin_bottom(8)
        view.set_margin_start(8)
        view.set_margin_end(8)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(view)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(220)

        frame = Gtk.Frame()
        frame.add_css_class("view")
        frame.set_child(scrolled)
        block_group.add(frame)
        self._buffer.connect("changed", self._on_changed)
        content.append(block_group)

        self._error_label = Gtk.Label()
        self._error_label.set_xalign(0)
        self._error_label.set_wrap(True)
        self._error_label.add_css_class("error")
        self._error_label.add_css_class("caption")
        self._error_label.set_visible(False)
        content.append(self._error_label)

        toolbar.set_content(content)
        self.set_child(toolbar)

        self._title_entry.grab_focus()
        self._refresh()

    # ── Refresh / validation ─────────────────────────────────────────

    def _on_title_changed(self, *_args: object) -> None:
        block = self._current_block()
        lines = block.split("\n", 1)
        if lines:
            new_header = replace_header_title(lines[0], self._title_entry.get_text())
            if new_header != lines[0]:
                self._buffer.set_text("\n".join([new_header] + lines[1:]))
        self._refresh()

    def _on_changed(self, *_args: object) -> None:
        self._refresh()

    def _current_block(self) -> str:
        start, end = self._buffer.get_bounds()
        return self._buffer.get_text(start, end, True).rstrip()

    def _refresh(self) -> None:
        block = self._current_block()
        title = self._title_entry.get_text().strip()

        error = None
        if not block:
            error = None  # empty is "in progress", not an error
        elif not title:
            error = "Entry needs a title."
        elif "'" in title or '"' in title:
            error = "Title cannot contain single or double quotes."
        elif not block_is_valid(block):
            error = "This block failed grub-script-check. Check the syntax."

        if error:
            self._error_label.set_label(error)
            self._error_label.set_visible(True)
        else:
            self._error_label.set_visible(False)

        changed = block != self._original_block
        self._apply_btn.set_sensitive(bool(block) and bool(title) and error is None and changed)

    # ── Apply / revert ────────────────────────────────────────────────

    def _on_apply(self, *_args: object) -> None:
        if not self._apply_btn.get_sensitive():
            return
        block = self._current_block()
        if self._on_apply_callback is not None:
            self._on_apply_callback(self._key, block)
        self.close()

    def _on_revert(self, *_args: object) -> None:
        dialog = Adw.AlertDialog(
            heading="Revert to template?",
            body="This entry will go back to the version generated from the "
                 "template on the next regeneration.",
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("revert", "Revert")
        dialog.set_response_appearance("revert", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_response(_dialog, response: str) -> None:
            if response == "revert" and self._on_revert_callback is not None:
                self._on_revert_callback(self._key)
                self.close()

        dialog.connect("response", on_response)
        dialog.present(self)


__all__ = ["GrubEntryEditDialog"]
