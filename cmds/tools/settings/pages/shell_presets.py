"""Shell Presets page — manage and apply configuration presets.

Mirrors the ``PresetsService`` + ``PresetsTab`` in the QML shell. Presets
are directories of JSON config files (bar, theme, compositor, …) that can
be applied in one click.  Official presets are bundled; user presets live
under ``~/.config/retro/shell/presets/``.

Applying a preset copies its files into the shell config directory; the
shell's ``FileView`` watcher picks up the changes and reloads live.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gio, GLib, Gtk, Pango

from settings.core.pending import PendingChange
from settings.core.shell_config import (
    apply_preset,
    delete_preset,
    read_active_preset,
    rename_preset,
    save_preset,
    scan_presets,
    update_preset,
)
from settings.ui import make_page_layout
from settings.ui.icons import PRESETS_ICON

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow


class ShellPresetsPage:
    """Shell preset management — apply, save, rename, delete presets."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None
        self._list_stack: Gtk.Stack | None = None
        self._listbox: Gtk.ListBox | None = None
        self._active: str = ""
        self._presets: list[dict] = []

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._active = read_active_preset()
        self._presets = scan_presets()

        # ── Header bar actions ──
        create_btn = Gtk.Button(label="Save Current as Preset")
        create_btn.add_css_class("pill")
        create_btn.set_valign(Gtk.Align.CENTER)
        create_btn.connect("clicked", self._on_save_current)
        header.pack_start(create_btn)

        # ── Split layout: list on left, actions on right ──
        split = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        split.set_vexpand(True)

        # Left: scrollable list
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        scrolled.set_hexpand(True)
        scrolled.set_size_request(240, -1)
        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.SINGLE)
        listbox.add_css_class("navigation-sidebar")
        listbox.connect("row-selected", self._on_row_selected)
        self._listbox = listbox
        scrolled.set_child(listbox)
        split.append(scrolled)

        # Right: action panel
        right_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        right_panel.set_margin_start(24)
        right_panel.set_margin_end(24)
        right_panel.set_margin_top(12)
        right_panel.set_margin_bottom(12)
        right_panel.set_vexpand(True)
        right_panel.set_halign(Gtk.Align.FILL)

        self._stack = Gtk.Stack()
        self._stack.set_vexpand(True)
        self._build_placeholder()
        right_panel.append(self._stack)
        split.append(right_panel)

        content_box.append(split)
        self._populate_list()
        return toolbar

    def _build_placeholder(self) -> None:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_valign(Gtk.Align.CENTER)
        box.set_halign(Gtk.Align.CENTER)
        icon = Gtk.Image.new_from_icon_name(PRESETS_ICON)
        icon.set_pixel_size(64)
        icon.set_opacity(0.3)
        box.append(icon)
        label = Gtk.Label(label="Select a preset from the list")
        label.add_css_class("dim-label")
        box.append(label)
        self._stack.add_named(box, "placeholder")
        self._stack.set_visible_child_name("placeholder")

    def _populate_list(self) -> None:
        if self._listbox is None:
            return
        # Clear
        row = self._listbox.get_first_child()
        while row is not None:
            nxt = row.get_next_sibling()
            self._listbox.remove(row)
            row = nxt

        official = [p for p in self._presets if p["is_official"]]
        user = [p for p in self._presets if not p["is_official"]]

        if official:
            hdr = Gtk.Label(label="Official", xalign=0)
            hdr.add_css_class("sidebar-category-header")
            hdr.set_margin_start(8)
            hdr.set_margin_top(8)
            self._listbox.append(hdr)
            for p in official:
                self._listbox.append(self._make_row(p))

        if user:
            hdr = Gtk.Label(label="User", xalign=0)
            hdr.add_css_class("sidebar-category-header")
            hdr.set_margin_start(8)
            hdr.set_margin_top(8)
            self._listbox.append(hdr)
            for p in user:
                self._listbox.append(self._make_row(p))

    def _make_row(self, preset: dict) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row._preset = preset
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        name_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        name_label = Gtk.Label(label=preset["name"], xalign=0, hexpand=True)
        name_label.set_ellipsize(Pango.EllipsizeMode.END)
        name_row.append(name_label)

        if preset["name"] == self._active:
            active_badge = Gtk.Label(label="Active")
            active_badge.add_css_class("accent")
            active_badge.set_halign(Gtk.Align.END)
            name_row.append(active_badge)

        if preset["is_official"]:
            off_badge = Gtk.Label(label="Official")
            off_badge.add_css_class("dim-label")
            off_badge.set_halign(Gtk.Align.END)
            name_row.append(off_badge)

        box.append(name_row)

        author = preset.get("info", {}).get("author", "")
        if author:
            sub = Gtk.Label(label=f"by {author}", xalign=0)
            sub.add_css_class("dim-label")
            sub.add_css_class("caption")
            box.append(sub)
        elif not preset["is_official"]:
            sub = Gtk.Label(label="Custom preset", xalign=0)
            sub.add_css_class("dim-label")
            sub.add_css_class("caption")
            box.append(sub)

        row.set_child(box)
        return row

    def _on_row_selected(self, _listbox, row) -> None:
        if row is None:
            self._stack.set_visible_child_name("placeholder")
            return
        preset = getattr(row, "_preset", None)
        if preset is None:
            self._stack.set_visible_child_name("placeholder")
            return
        self._build_detail(preset)

    def _build_detail(self, preset: dict) -> None:
        name = "detail_" + preset["name"]
        existing = self._stack.get_child_by_name(name)
        if existing is not None:
            self._stack.set_visible_child_name(name)
            return

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_valign(Gtk.Align.START)

        # Title
        title = Gtk.Label(label=preset["name"])
        title.add_css_class("title-1")
        title.set_xalign(0)
        box.append(title)

        info = preset.get("info", {})
        author = info.get("author", "")
        if author:
            sub = Gtk.Label(label=f"by {author}")
            sub.add_css_class("dim-label")
            sub.set_xalign(0)
            box.append(sub)

        is_active = preset["name"] == self._active

        # Apply button
        apply_btn = Gtk.Button(label="Use This Preset" if not is_active else "✓ Currently Active")
        apply_btn.add_css_class("pill")
        apply_btn.add_css_class("suggested-action" if not is_active else "")
        apply_btn.set_sensitive(not is_active)
        apply_btn.set_halign(Gtk.Align.START)
        apply_btn.connect("clicked", lambda *a, p=preset: self._on_apply(p))
        box.append(apply_btn)

        if not preset["is_official"]:
            sep = Gtk.Separator()
            box.append(sep)
            heading = Gtk.Label(label="Manage Preset", xalign=0)
            heading.add_css_class("heading")
            box.append(heading)

            rename_btn = Gtk.Button(label="Rename")
            rename_btn.add_css_class("pill")
            rename_btn.set_halign(Gtk.Align.START)
            rename_btn.connect("clicked", lambda *a, p=preset: self._on_rename(p))
            box.append(rename_btn)

            update_btn = Gtk.Button(label="Update From Current Config")
            update_btn.add_css_class("pill")
            update_btn.set_halign(Gtk.Align.START)
            update_btn.connect("clicked", lambda *a, p=preset: self._on_update(p))
            box.append(update_btn)

            delete_btn = Gtk.Button(label="Delete Preset")
            delete_btn.add_css_class("pill")
            delete_btn.add_css_class("destructive-action")
            delete_btn.set_halign(Gtk.Align.START)
            delete_btn.connect("clicked", lambda *a, p=preset: self._on_delete(p))
            box.append(delete_btn)

        self._stack.add_named(box, name)
        self._stack.set_visible_child_name(name)

    def _refresh(self) -> None:
        self._active = read_active_preset()
        self._presets = scan_presets()
        self._populate_list()
        # Remove cached detail pages so they rebuild
        for name in ["detail_" + p["name"] for p in self._presets]:
            child = self._stack.get_child_by_name(name) if self._stack else None
            if child is not None:
                self._stack.remove(child)

    def _on_apply(self, preset: dict) -> None:
        apply_preset(preset)
        self._refresh()

    def _on_save_current(self, *_args) -> None:
        dialog = Adw.MessageDialog.new(
            self._window,
            "Save Current Configuration as Preset",
            "Enter a name for the new preset:",
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("save", "Save")
        dialog.set_response_appearance("save", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_close_response("cancel")

        entry = Gtk.Entry()
        entry.set_placeholder_text("My Preset")
        entry.set_margin_top(8)
        entry.set_margin_bottom(8)
        dialog.set_extra_child(entry)

        dialog.connect("response", lambda d, resp: self._on_save_response(resp, entry.get_text().strip(), d))
        dialog.present()

    def _on_save_response(self, response: str, name: str, dialog: Adw.MessageDialog) -> None:
        if response != "save" or not name:
            return
        save_preset(name)
        self._refresh()

    def _on_rename(self, preset: dict) -> None:
        dialog = Adw.MessageDialog.new(
            self._window,
            f"Rename \"{preset['name']}\"",
            "Enter a new name:",
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("rename", "Rename")
        dialog.set_response_appearance("rename", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_close_response("cancel")

        entry = Gtk.Entry()
        entry.set_text(preset["name"])
        entry.set_margin_top(8)
        entry.set_margin_bottom(8)
        dialog.set_extra_child(entry)

        dialog.connect("response", lambda d, resp, p=preset, e=entry: self._on_rename_response(resp, e.get_text().strip(), p, d))
        dialog.present()

    def _on_rename_response(self, response: str, new_name: str, preset: dict, dialog: Adw.MessageDialog) -> None:
        if response != "rename" or not new_name or new_name == preset["name"]:
            return
        rename_preset(preset["name"], new_name)
        self._refresh()

    def _on_update(self, preset: dict) -> None:
        update_preset(preset)
        self._refresh()

    def _on_delete(self, preset: dict) -> None:
        dialog = Adw.MessageDialog.new(
            self._window,
            f"Delete \"{preset['name']}\"?",
            "This preset will be permanently deleted.",
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("delete", "Delete")
        dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_close_response("cancel")
        dialog.connect("response", lambda d, resp, p=preset: self._on_delete_response(resp, p, d))
        dialog.present()

    def _on_delete_response(self, response: str, preset: dict, dialog: Adw.MessageDialog) -> None:
        if response != "delete":
            return
        delete_preset(preset["name"])
        self._refresh()

    def is_dirty(self) -> bool:
        return False

    def mark_saved(self) -> None:
        pass

    def discard(self) -> None:
        pass

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return []

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_presets:presets", "label": "Presets",
             "description": "Save, apply, rename and delete configuration presets",
             "_group_id": "shell_presets", "_group_label": "Presets", "_section_label": "Presets"},
        ]


__all__ = ["ShellPresetsPage"]
