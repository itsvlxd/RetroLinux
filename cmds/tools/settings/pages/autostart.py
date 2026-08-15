"""Autostart page — Retro startup sequence and custom commands.

Shows the system startup tasks (hardcoded from load.sh) as read-only,
and custom user commands from the ``RETRO_CUSTOM_LOAD`` variable as
editable entries. No Hyprland ``exec``/``exec-once`` involvement.
"""

import os
import threading
from html import escape as html_escape

from gi.repository import Adw, GLib, Gtk

from settings.core.autostart import (
    RetroStartupData,
    XdgAutostartEntry,
    clean_xdg_autostart,
    delete_xdg_autostart,
    get_system_tasks,
    list_xdg_autostart,
    parse_retro_startup,
    serialize_retro_startup,
    toggle_xdg_autostart,
)
from settings.pages.section import SavedListSectionPage
from settings.ui import clear_children, make_inline_hint, make_page_layout
from settings.ui.icons import AUTOSTART_ICON
from settings.ui.empty_state import EmptyState
from settings.ui.reorder import RowReorderController


def update_autostart_sidebar(window) -> None:
    """Update the Autostart sidebar row with custom command count."""
    try:
        sidebar = getattr(window, "_sidebar", None)
        if sidebar is None:
            return
        row = sidebar._rows_by_id.get("autostart")
        if row is None:
            return
        if not hasattr(row, "_as_sidebar_label"):
            lbl = Gtk.Label()
            lbl.set_valign(Gtk.Align.CENTER)
            lbl.add_css_class("badge")
            row.add_suffix(lbl)
            row._as_sidebar_label = lbl
        from lib.python.variable import get_var
        raw = get_var("RETRO_CUSTOM_LOAD", "")
        count = len([e for e in raw.split("|") if e.strip()])
        row._as_sidebar_label.set_visible(count > 0)
        if count:
            row._as_sidebar_label.set_label(str(count))
    except Exception:
        pass


class AutostartPage(SavedListSectionPage[RetroStartupData]):
    """Retro startup sequence page."""

    _page_attr = "_autostart_page"
    _pending_category = "Autostart"
    _pending_navigate_to = "autostart"
    _pending_icon = AUTOSTART_ICON

    def __init__(
        self,
        window,
        on_dirty_changed=None,
        push_undo=None,
        saved_sections: dict[str, list[str]] | None = None,
    ):
        super().__init__(window, on_dirty_changed, push_undo)
        self._content_box: Gtk.Box
        self._scrolled: Gtk.ScrolledWindow
        self._retro_rows: list[Gtk.Widget] = []
        self._xdg_group: Adw.PreferencesGroup | None = None
        self._spinner_box: Gtk.Box | None = None
        self._pending_loads = 0
        self._reorder = RowReorderController(
            move=self._move_retro_item,
            iter_rows=lambda: self._retro_rows,
        )
        self._load(saved_sections)

    # ── Loading ──

    def _load(self, saved_sections: dict[str, list[str]] | None = None) -> None:
        del saved_sections
        from lib.python.variable import get_var
        raw = get_var("RETRO_CUSTOM_LOAD", "")
        items = parse_retro_startup(raw)
        self._retro_owned: list[RetroStartupData] = items
        self._retro_saved = list(items)
        self._system_tasks: list[tuple[str, str]] = []
        self._xdg_entries: list[XdgAutostartEntry] = []
        self._pending_loads = 2
        self._xdg_load_seq = getattr(self, "_xdg_load_seq", 0) + 1
        self._xdg_async(lambda: (get_system_tasks(),), self._on_system_tasks_loaded)
        self._xdg_async(
            lambda: (self._xdg_load_seq, list_xdg_autostart()), self._on_xdg_list_loaded
        )

    def _on_system_tasks_loaded(self, tasks: list[tuple[str, str]]) -> None:
        self._system_tasks = tasks
        self._load_step_done()

    def _on_xdg_list_loaded(self, seq: int, entries: list[XdgAutostartEntry]) -> None:
        if seq == self._xdg_load_seq:
            self._xdg_entries = entries
        self._load_step_done()

    def _load_step_done(self) -> None:
        self._pending_loads -= 1
        if self._pending_loads > 0:
            return
        if self._content_box is None:
            return
        if self._spinner_box is not None:
            try:
                self._content_box.remove(self._spinner_box)
            except Exception:
                pass
            self._spinner_box = None
        self._rebuild_list()

    def _build_spinner(self) -> Gtk.Box:
        spinner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        spinner_box.set_valign(Gtk.Align.CENTER)
        spinner_box.set_halign(Gtk.Align.CENTER)
        spinner_box.set_margin_top(48)
        spinner = Gtk.Spinner()
        spinner.set_size_request(32, 32)
        spinner.start()
        spinner_box.append(spinner)
        lbl = Gtk.Label(label="Loading autostart entries\u2026")
        lbl.add_css_class("dim-label")
        spinner_box.append(lbl)
        self._spinner_box = spinner_box
        return spinner_box

    # ── Build ──

    def build(self, header: Adw.HeaderBar | None = None) -> Adw.ToolbarView:
        page_header = header or Adw.HeaderBar()

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh from variables")
        refresh_btn.connect("clicked", lambda _b: self._on_refresh())
        page_header.pack_start(refresh_btn)

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_tooltip_text("Add startup command")
        add_btn.connect("clicked", lambda _b: self._on_add_retro())
        page_header.pack_start(add_btn)

        toolbar_view, _, self._content_box, self._scrolled = make_page_layout(header=page_header)

        if self._pending_loads > 0:
            self._content_box.append(self._build_spinner())
        else:
            self._rebuild_list()
        return toolbar_view

    # ── List rendering ──

    def _build_system_group(self) -> list[Gtk.Widget]:
        group = Adw.PreferencesGroup(title="System Startup Sequence")
        group.set_description(f"{len(self._system_tasks)} system tasks")
        for cmd, desc in self._system_tasks:
            row = Adw.ActionRow(title=html_escape(cmd), subtitle=html_escape(desc))
            row.set_title_lines(1)
            row.set_subtitle_lines(1)
            row.add_css_class("option-default")
            row.set_opacity(0.65)

            prefix = Gtk.Image.new_from_icon_name("computer-symbolic")
            prefix.set_opacity(0.4)
            prefix.set_pixel_size(22)
            row.add_prefix(prefix)

            lock_icon = Gtk.Image.new_from_icon_name("changes-prevent-symbolic")
            lock_icon.set_opacity(0.4)
            lock_icon.set_valign(Gtk.Align.CENTER)
            row.add_suffix(lock_icon)
            group.add(row)
        return [group] if self._system_tasks else []

    def _build_custom_group(self) -> list[Gtk.Widget]:
        group = Adw.PreferencesGroup(title="Startup Commands")
        n = len(self._retro_owned)
        group.set_description(
            f"{n} command{'s' if n != 1 else ''}" if n else "No commands yet"
        )

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text("Add startup command")
        add_btn.connect("clicked", lambda _b: self._on_add_retro())
        group.set_header_suffix(add_btn)

        for idx, item in enumerate(self._retro_owned):
            group.add(self._make_retro_row(idx, item))
        return [group]

    def _build_xdg_group(self) -> list[Gtk.Widget]:
        if not self._xdg_entries:
            return []
        self._xdg_group = self._make_xdg_group_widget(self._xdg_entries)
        return [self._xdg_group]

    def _make_xdg_group_widget(self, entries: list[XdgAutostartEntry]) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup(title="Application Autostart")
        n = len(entries)
        group.set_description(
            f"{n} app{'s' if n != 1 else ''} launching at login"
        )

        clean_btn = Gtk.Button(icon_name="user-trash-symbolic")
        clean_btn.set_valign(Gtk.Align.CENTER)
        clean_btn.add_css_class("flat")
        clean_btn.set_tooltip_text("Remove stale autostart entries (missing binary)")
        clean_btn.connect("clicked", lambda _b: self._on_clean_xdg())
        group.set_header_suffix(clean_btn)

        for entry in entries:
            group.add(self._make_xdg_row(entry))
        return group

    def _make_xdg_row(self, entry: XdgAutostartEntry) -> Adw.SwitchRow:
        scope = "System" if entry.scope == "system" else "User"
        subtitle = f"{scope} · {os.path.basename(entry.path)}"
        if not entry.binary_exists:
            subtitle += " · binary missing"

        row = Adw.SwitchRow(title=html_escape(entry.name), subtitle=subtitle)
        row.set_active(entry.enabled)
        row.connect("notify::active", lambda r, _pspec, e=entry: self._on_xdg_toggle(r, e))
        if not entry.binary_exists:
            row.add_css_class("option-default")
            row.set_opacity(0.7)

        delete_btn = Gtk.Button(icon_name="user-trash-symbolic")
        delete_btn.set_valign(Gtk.Align.CENTER)
        delete_btn.add_css_class("flat")
        delete_btn.set_tooltip_text("Remove this autostart entry")
        delete_btn.connect("clicked", lambda _b, e=entry: self._on_delete_xdg(e))
        row.add_suffix(delete_btn)
        return row

    def _on_xdg_toggle(self, row: Adw.SwitchRow, entry: XdgAutostartEntry) -> None:
        action = "enable" if row.get_active() else "disable"
        desktop = os.path.basename(entry.path)
        self._xdg_load_seq += 1

        def worker() -> tuple[bool, list[XdgAutostartEntry]]:
            return toggle_xdg_autostart(desktop, action), list_xdg_autostart()

        self._xdg_async(worker, self._on_xdg_toggle_done, row, action)

    def _on_xdg_toggle_done(self, row: Adw.SwitchRow, action: str, ok: bool, entries: list[XdgAutostartEntry]) -> None:
        if not ok:
            self._window.show_toast("Failed to update autostart entry", timeout=4)
        self._refresh_xdg_group(entries)

    def _on_delete_xdg(self, entry: XdgAutostartEntry) -> None:
        desktop = os.path.basename(entry.path)
        self._xdg_load_seq += 1

        def worker() -> tuple[bool, list[XdgAutostartEntry]]:
            return delete_xdg_autostart(desktop), list_xdg_autostart()

        self._xdg_async(worker, self._on_xdg_delete_done, entry)

    def _on_xdg_delete_done(self, entry: XdgAutostartEntry, ok: bool, entries: list[XdgAutostartEntry]) -> None:
        if ok:
            self._window.show_toast(f"Removed {entry.name} from autostart", timeout=4)
        else:
            self._window.show_toast("Nothing to remove — entry is system-owned", timeout=4)
        self._refresh_xdg_group(entries)

    def _on_clean_xdg(self) -> None:
        self._xdg_load_seq += 1

        def worker() -> tuple[int, list[XdgAutostartEntry]]:
            return clean_xdg_autostart(), list_xdg_autostart()

        self._xdg_async(worker, self._on_xdg_clean_done)

    def _on_xdg_clean_done(self, cleaned: int, entries: list[XdgAutostartEntry]) -> None:
        if cleaned:
            self._window.show_toast(f"Removed {cleaned} stale autostart entr{'y' if cleaned == 1 else 'ies'}", timeout=4)
        else:
            self._window.show_toast("No stale autostart entries found", timeout=3)
        self._refresh_xdg_group(entries)

    def _xdg_async(self, work, on_done, *on_done_args) -> None:
        def runner() -> None:
            try:
                result = work()
            except Exception:
                result = None
            GLib.idle_add(self._dispatch_xdg_result, on_done, on_done_args, result)

        threading.Thread(target=runner, daemon=True).start()

    @staticmethod
    def _dispatch_xdg_result(on_done, on_done_args, result) -> bool:
        if result is not None:
            on_done(*on_done_args, *result)
        return False

    def _refresh_xdg_group(self, entries: list[XdgAutostartEntry] | None = None) -> None:
        if entries is None:
            entries = list_xdg_autostart()
        self._xdg_entries = entries

        if self._xdg_group is None or self._content_box is None:
            self._rebuild_list()
            return

        new_group = self._make_xdg_group_widget(entries)
        prev = self._xdg_group.get_prev_sibling()
        self._content_box.remove(self._xdg_group)
        if prev is not None:
            self._content_box.insert_child_after(new_group, prev)
        else:
            self._content_box.prepend(new_group)
        self._xdg_group = new_group

    def _rebuild_list(self) -> None:
        clear_children(self._content_box)

        if len(self._retro_owned) >= 2:
            self._content_box.append(make_inline_hint(
                "Reorder with Alt+↑ / Alt+↓ on a focused row, or drag by the handle."
            ))

        self._retro_rows = [None] * len(self._retro_owned)
        for w in self._build_custom_group():
            self._content_box.append(w)
        self._xdg_group = None
        for w in self._build_xdg_group():
            self._content_box.append(w)
        for w in self._build_system_group():
            self._content_box.append(w)

        if not self._retro_owned and not self._system_tasks and not self._xdg_entries:
            self._content_box.append(self._build_empty_state())

    def _build_empty_state(self) -> EmptyState:
        return EmptyState(
            title="No Startup Commands",
            description="Add commands to run during the Retro startup sequence.",
            icon_name=AUTOSTART_ICON,
            primary_action=("Add Command…", self._on_add_retro),
        )

    # ── Base-class overrides ──

    def is_dirty(self) -> bool:
        return self._retro_owned != self._retro_saved

    def mark_saved(self) -> None:
        from lib.python.variable import set_var
        raw = serialize_retro_startup(self._retro_owned)
        set_var("RETRO_CUSTOM_LOAD", raw)
        self._retro_saved = list(self._retro_owned)
        self._rebuild_list()

    def discard(self) -> None:
        self._retro_owned = list(self._retro_saved)
        self._rebuild_list()

    def pending_change_count(self) -> int:
        if not self.is_dirty():
            return 0
        count = 0
        for item in self._retro_owned:
            if item not in self._retro_saved:
                count += 1
        for item in self._retro_saved:
            if item not in self._retro_owned:
                count += 1
        return count

    # ── Custom startup rows ──

    def _make_retro_row(self, idx: int, item: RetroStartupData) -> Adw.ActionRow:
        row = Adw.ActionRow(title=html_escape(item.command))
        row.set_title_lines(2)

        prefix = Gtk.Image.new_from_icon_name("emblem-system-symbolic")
        prefix.set_opacity(0.6)
        prefix.set_pixel_size(28)
        row.add_prefix(prefix)

        self._reorder.attach(row, idx)
        if idx < len(self._retro_rows):
            self._retro_rows[idx] = row

        delete_btn = Gtk.Button(icon_name="user-trash-symbolic")
        delete_btn.set_valign(Gtk.Align.CENTER)
        delete_btn.add_css_class("flat")
        delete_btn.set_tooltip_text("Remove this command")
        delete_btn.connect("clicked", lambda _b, i=idx: self._on_delete_retro_at(i))
        row.add_suffix(delete_btn)

        run_btn = Gtk.Button(icon_name="system-run-symbolic")
        run_btn.set_valign(Gtk.Align.CENTER)
        run_btn.add_css_class("flat")
        run_btn.set_tooltip_text("Run this command now")
        run_btn.connect("clicked", lambda _b, e=item: self._run_now(e))
        row.add_suffix(run_btn)

        row.set_activatable(True)
        row.connect("activated", lambda _r, i=idx: self._on_edit_retro_at(i))
        row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
        return row

    def _move_retro_item(self, src: int, dst: int) -> bool:
        if src == dst or not (0 <= src < len(self._retro_owned) and 0 <= dst < len(self._retro_owned)):
            return False
        item = self._retro_owned.pop(src)
        self._retro_owned.insert(dst, item)
        self._notify_dirty()
        self._rebuild_list()
        return True

    # ── Add / Edit / Remove ──

    def _on_add_retro(self) -> None:
        dialog = Adw.Dialog(title="Add Startup Command")
        dialog.set_content_width(480)
        dialog.set_content_height(200)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: dialog.close())
        header.pack_start(cancel_btn)
        apply_btn = Gtk.Button(label="Apply")
        apply_btn.add_css_class("suggested-action")
        apply_btn.set_sensitive(False)
        header.pack_end(apply_btn)
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)

        group = Adw.PreferencesGroup(title="Command")
        group.set_description(
            "Type a shell command to run during the Retro startup sequence."
        )
        cmd_entry = Adw.EntryRow(title="Command line")
        cmd_entry.connect("changed", lambda *_: apply_btn.set_sensitive(bool(cmd_entry.get_text().strip())))
        cmd_entry.connect("entry-activated", lambda _e: apply_btn.emit("clicked"))
        group.add(cmd_entry)
        content.append(group)
        toolbar.set_content(content)
        dialog.set_child(toolbar)
        cmd_entry.grab_focus()

        def on_apply(_b=None):
            cmd = cmd_entry.get_text().strip()
            if not cmd:
                return
            self._retro_owned.append(RetroStartupData(command=cmd))
            self._notify_dirty()
            self._rebuild_list()
            dialog.close()

        apply_btn.connect("clicked", on_apply)
        dialog.present(self._window)

    def _on_edit_retro_at(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._retro_owned):
            return
        current = self._retro_owned[idx]

        dialog = Adw.Dialog(title="Edit Startup Command")
        dialog.set_content_width(480)
        dialog.set_content_height(200)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: dialog.close())
        header.pack_start(cancel_btn)
        apply_btn = Gtk.Button(label="Apply")
        apply_btn.add_css_class("suggested-action")
        header.pack_end(apply_btn)
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)

        group = Adw.PreferencesGroup(title="Command")
        cmd_entry = Adw.EntryRow(title="Command line")
        cmd_entry.set_text(current.command)
        cmd_entry.connect("changed", lambda *_: apply_btn.set_sensitive(bool(cmd_entry.get_text().strip())))
        cmd_entry.connect("entry-activated", lambda _e: apply_btn.emit("clicked"))
        group.add(cmd_entry)
        content.append(group)
        toolbar.set_content(content)
        dialog.set_child(toolbar)
        cmd_entry.grab_focus()

        def on_apply(_b=None):
            cmd = cmd_entry.get_text().strip()
            if not cmd or cmd == current.command:
                dialog.close()
                return
            self._retro_owned[idx] = RetroStartupData(command=cmd)
            self._notify_dirty()
            self._rebuild_list()
            dialog.close()

        apply_btn.connect("clicked", on_apply)
        dialog.present(self._window)

    def _on_delete_retro_at(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._retro_owned):
            return
        del self._retro_owned[idx]
        self._notify_dirty()
        self._rebuild_list()

    def _on_refresh(self) -> None:
        self._load(None)
        self._rebuild_list()

    # ── Run-now ──

    def _run_now(self, item: RetroStartupData) -> None:
        import shlex, subprocess
        cmd = item.command.strip()
        if not cmd:
            return
        try:
            tokens = shlex.split(cmd)
        except ValueError as e:
            self._window.show_toast(f"Couldn't parse command: {e}", timeout=4, copy=True)
            return
        try:
            subprocess.Popen(
                tokens,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except (OSError, FileNotFoundError) as e:
            self._window.show_toast(f"Failed to run: {e}", timeout=5, copy=True)
            return
        self._window.show_toast(f"Started: {cmd}")


__all__ = ["AutostartPage"]
