"""Shell Presets page — manage and apply configuration presets.

Presets are directories of JSON config files that can be applied in one click.
Official presets ship with the system; user presets live under
``~/.config/retro/shell/presets/``.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk, Pango

from settings.core.pending import PendingChange
from settings.core.shell_config import (
    apply_preset, delete_preset, read_active_preset,
    rename_preset, save_preset, scan_presets, update_preset,
)
from settings.ui import make_page_layout
from settings.ui.icons import PRESETS_ICON

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow


class _PresetRow(Gtk.ListBoxRow):
    def __init__(self, preset: dict, is_active: bool,
                 on_apply=None, on_rename=None, on_update=None, on_delete=None):
        super().__init__()
        self._preset = preset
        is_official = preset["is_official"]
        author = preset.get("info", {}).get("author", "")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(8)
        box.set_margin_end(8)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        text_box.set_hexpand(True)

        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        name_lbl = Gtk.Label(label=preset["name"])
        name_lbl.set_halign(Gtk.Align.START)
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        name_box.append(name_lbl)

        if is_active:
            badge = Gtk.Label(label="ACTIVE")
            badge.add_css_class("badge")
            name_box.append(badge)
        if is_official:
            badge = Gtk.Label(label="OFFICIAL")
            badge.add_css_class("badge")
            badge.set_opacity(0.7)
            name_box.append(badge)

        text_box.append(name_box)

        sub_lbl = Gtk.Label(label=f"by {author}" if author else ("Custom" if not is_official else ""))
        sub_lbl.set_halign(Gtk.Align.START)
        sub_lbl.add_css_class("dim-label")
        sub_lbl.add_css_class("caption")
        text_box.append(sub_lbl)

        box.append(text_box)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        btn_box.set_valign(Gtk.Align.CENTER)

        if not is_active and on_apply:
            ab = Gtk.Button(icon_name="emblem-default-symbolic")
            ab.set_tooltip_text("Apply preset")
            ab.add_css_class("suggested-action")
            ab.connect("clicked", lambda _b: on_apply(preset))
            btn_box.append(ab)

        if not is_official:
            if on_rename:
                rb = Gtk.Button(icon_name="document-edit-symbolic")
                rb.set_tooltip_text("Rename")
                rb.connect("clicked", lambda _b: on_rename(preset))
                btn_box.append(rb)
            if on_update:
                ub = Gtk.Button(icon_name="view-refresh-symbolic")
                ub.set_tooltip_text("Update from current config")
                ub.connect("clicked", lambda _b: on_update(preset))
                btn_box.append(ub)
            if on_delete:
                db = Gtk.Button(icon_name="user-trash-symbolic")
                db.set_tooltip_text("Delete preset")
                db.add_css_class("destructive-action")
                db.connect("clicked", lambda _b: on_delete(preset))
                btn_box.append(db)

        box.append(btn_box)
        self.set_child(box)


class ShellPresetsPage:
    """Shell preset management."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None
        self._active: str = ""
        self._presets: list[dict] = []
        self._content_box: Gtk.Box | None = None
        self._official_list: Gtk.ListBox | None = None
        self._user_list: Gtk.ListBox | None = None

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_tooltip_text("Save current configuration as a preset")
        add_btn.connect("clicked", self._on_save)
        header.pack_start(add_btn)

        self._active = read_active_preset()
        self._presets = scan_presets()

        # Official Presets
        og = Adw.PreferencesGroup(title="Official Presets")
        self._official_list = Gtk.ListBox()
        self._official_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self._official_list.add_css_class("boxed-list")
        og.add(self._official_list)
        self._content_box.append(og)

        # User Presets
        ug = Adw.PreferencesGroup(title="User Presets")
        self._user_list = Gtk.ListBox()
        self._user_list.set_selection_mode(Gtk.SelectionMode.NONE)
        self._user_list.add_css_class("boxed-list")
        ug.add(self._user_list)
        self._content_box.append(ug)

        self._refresh_lists()

        return toolbar_view

    def _refresh_lists(self):
        for lst in (self._official_list, self._user_list):
            if not lst:
                continue
            while c := lst.get_first_child():
                lst.remove(c)

        official = [p for p in self._presets if p["is_official"]]
        user = [p for p in self._presets if not p["is_official"]]

        for p in official:
            if self._official_list:
                self._official_list.append(
                    _PresetRow(p, p["name"] == self._active,
                               on_apply=self._apply_preset))
        for p in user:
            if self._user_list:
                self._user_list.append(
                    _PresetRow(p, p["name"] == self._active,
                               on_apply=self._apply_preset,
                               on_rename=self._rename_preset,
                               on_update=self._update_preset,
                               on_delete=self._delete_preset))

    def _reload(self):
        self._active = read_active_preset()
        self._presets = scan_presets()
        self._refresh_lists()

    def _apply_preset(self, p):
        apply_preset(p)
        self._reload()

    def _update_preset(self, p):
        update_preset(p)
        self._reload()

    def _on_save(self, *_):
        d = Adw.Dialog(title="Save Current Configuration as Preset")
        d.set_content_width(380)
        d.set_content_height(180)
        tb = Adw.ToolbarView()
        hb = Adw.HeaderBar()
        hb.set_show_title(False)
        tb.add_top_bar(hb)
        bx = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        bx.set_margin_top(24)
        bx.set_margin_start(24)
        bx.set_margin_end(24)
        bx.set_margin_bottom(24)
        e = Gtk.Entry(placeholder_text="My Preset", hexpand=True)
        bx.append(e)
        bb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bb.set_halign(Gtk.Align.END)
        bb.append(Gtk.Button(label="Cancel", clicked=lambda _: d.close()))
        sb = Gtk.Button(label="Save")
        sb.add_css_class("suggested-action")
        sb.connect("clicked", lambda _: (save_preset(e.get_text().strip()) if e.get_text().strip() else None, self._reload(), d.close()))
        bb.append(sb)
        bx.append(bb)
        tb.set_content(bx)
        d.set_child(tb)
        d.present(self._window)

    def _rename_preset(self, preset):
        d = Adw.Dialog(title=f"Rename \"{preset['name']}\"")
        d.set_content_width(380)
        d.set_content_height(180)
        tb = Adw.ToolbarView()
        hb = Adw.HeaderBar()
        hb.set_show_title(False)
        tb.add_top_bar(hb)
        bx = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        bx.set_margin_top(24)
        bx.set_margin_start(24)
        bx.set_margin_end(24)
        bx.set_margin_bottom(24)
        e = Gtk.Entry(text=preset["name"], hexpand=True)
        bx.append(e)
        bb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bb.set_halign(Gtk.Align.END)
        bb.append(Gtk.Button(label="Cancel", clicked=lambda _: d.close()))
        rb = Gtk.Button(label="Rename")
        rb.add_css_class("suggested-action")
        rb.connect("clicked", lambda _: (
            rename_preset(preset["name"], e.get_text().strip()) if e.get_text().strip() and e.get_text().strip() != preset["name"] else None,
            self._reload(), d.close(),
        ))
        bb.append(rb)
        bx.append(bb)
        tb.set_content(bx)
        d.set_child(tb)
        d.present(self._window)

    def _delete_preset(self, preset):
        d = Adw.Dialog(title=f"Delete \"{preset['name']}\"?")
        d.set_content_width(360)
        d.set_content_height(160)
        tb = Adw.ToolbarView()
        hb = Adw.HeaderBar()
        hb.set_show_title(False)
        tb.add_top_bar(hb)
        bx = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        bx.set_margin_top(24)
        bx.set_margin_start(24)
        bx.set_margin_end(24)
        bx.set_margin_bottom(24)
        bx.append(Gtk.Label(label="This preset will be permanently deleted.", wrap=True))
        bb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bb.set_halign(Gtk.Align.END)
        bb.append(Gtk.Button(label="Cancel", clicked=lambda _: d.close()))
        db = Gtk.Button(label="Delete")
        db.add_css_class("destructive-action")
        db.connect("clicked", lambda _: (delete_preset(preset["name"]), self._reload(), d.close()))
        bb.append(db)
        bx.append(bb)
        tb.set_content(bx)
        d.set_child(tb)
        d.present(self._window)

    def is_dirty(self) -> bool: return False
    def mark_saved(self) -> None: pass
    def discard(self) -> None: pass

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return []

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_presets:presets", "label": "Presets",
             "description": "Save, apply, rename and delete configuration presets",
             "_group_id": "shell_presets", "_group_label": "Presets", "_section_label": "Presets"},
        ]


__all__ = ["ShellPresetsPage"]
