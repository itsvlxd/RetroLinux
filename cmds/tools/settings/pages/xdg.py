"""Default Apps page — XDG default applications, MIME manager, directories, portals."""

import os
import re
import subprocess
import threading
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gdk, GdkPixbuf, Gio, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_XDG_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "xdg_core.sh")
_XDG_ICON = "preferences-desktop-apps-symbolic"
_MIMEAPPS = os.path.expanduser("~/.config/mimeapps.list")

_APP_DIRS = [
    "/usr/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
]

_CATEGORIES = [
    ("Web Browser", "x-scheme-handler/http"),
    ("File Manager", "inode/directory"),
    ("Editor", "text/plain"),
    ("Image Viewer", "image/png"),
    ("Video Player", "video/mp4"),
    ("Terminal", "x-scheme-handler/terminal"),
]

_DIRS = ["DESKTOP", "DOWNLOAD", "DOCUMENTS", "MUSIC", "PICTURES", "VIDEOS", "TEMPLATES", "PUBLICSHARE"]

_DIR_ICONS = {
    "DESKTOP": "folder-desktop",
    "DOWNLOAD": "folder-download",
    "DOCUMENTS": "folder-documents",
    "MUSIC": "folder-music",
    "PICTURES": "folder-pictures",
    "VIDEOS": "folder-videos",
    "TEMPLATES": "folder-templates",
    "PUBLICSHARE": "folder-publicshare",
}

_PAPIRUS_THEMES = [
    "/usr/share/icons/Papirus",
    "/usr/share/icons/Papirus-Dark",
    "/usr/share/icons/Papirus-Light",
]


def _folder_icon(name: str, size: int = 24) -> Gtk.Image:
    """Colored Papirus folder icon, loaded straight from the SVG files.

    Wallpaper managers all use these; prefer the SVG on disk over the
    active icon theme so the colors are consistent regardless of theme.
    """
    for theme in _PAPIRUS_THEMES:
        path = os.path.join(theme, "24x24", "places", f"{name}.svg")
        if os.path.isfile(path):
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, size, size, True)
                img = Gtk.Image.new_from_paintable(Gdk.Texture.new_for_pixbuf(pb))
                img.set_pixel_size(size)
                return img
            except Exception:
                break
    img = Gtk.Image.new_from_icon_name(name)
    img.set_pixel_size(size)
    return img


def _run(args: list[str], timeout: int = 15) -> str:
    try:
        r = subprocess.run(
            ["bash", _XDG_CORE, *args],
            capture_output=True, text=True, timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _list_all_apps() -> list[dict]:
    """Scan system + user application dirs for .desktop entries."""
    seen: dict[str, dict] = {}
    for d in _APP_DIRS:
        if not os.path.isdir(d):
            continue
        try:
            for name in os.listdir(d):
                if not name.endswith(".desktop"):
                    continue
                if name in seen:
                    continue
                path = os.path.join(d, name)
                display, icon = _desktop_info_from_path(path, name)
                if display:
                    seen[name] = {"desktop": name, "name": display, "icon": icon}
        except OSError:
            continue
    return sorted(seen.values(), key=lambda a: a["name"].casefold())


def _desktop_info_from_path(path: str, desktop: str) -> tuple[str, str]:
    """Return (display name, icon name) from a .desktop file."""
    fallback = desktop.replace(".desktop", "")
    name, icon, got_name = fallback, "", False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if not got_name and line.startswith("Name="):
                    name = line.strip()[5:]
                    got_name = True
                elif line.startswith("Icon="):
                    icon = line.strip()[5:]
    except OSError:
        pass
    return (name or fallback), icon


def _desktop_name_from_path(path: str, desktop: str) -> str:
    return _desktop_info_from_path(path, desktop)[0]


def _desktop_name(desktop: str) -> str:
    for d in _APP_DIRS:
        path = os.path.join(d, desktop)
        if os.path.isfile(path):
            n = _desktop_name_from_path(path, desktop)
            if n:
                return n
    return desktop.replace(".desktop", "")


def _desktop_icon(desktop: str) -> str:
    for d in _APP_DIRS:
        path = os.path.join(d, desktop)
        if os.path.isfile(path):
            return _desktop_info_from_path(path, desktop)[1]
    return ""


def _app_icon(icon: str) -> Gtk.Image:
    """App icon image with themed-name, absolute-path and generic fallback."""
    img = Gtk.Image()
    img.set_pixel_size(24)
    name = icon.rsplit("/", 1)[-1] if icon else ""
    display = Gdk.Display.get_default()
    if name and display is not None:
        theme = Gtk.IconTheme.get_for_display(display)
        if theme.has_icon(name):
            img.set_from_icon_name(name)
            return img
        if icon.startswith("/") and os.path.isfile(icon):
            try:
                img.set_from_paintable(Gdk.Texture.new_from_filename(icon))
                return img
            except GLib.Error:
                pass
    img.set_from_icon_name("application-x-executable-symbolic")
    return img


def _load_defaults() -> list[dict]:
    out = _run(["--list-defaults"])
    rows = []
    for line in out.splitlines():
        parts = line.split("|")
        if len(parts) >= 3:
            rows.append({"mime": parts[0], "desktop": parts[1], "app": parts[2]})
    return rows


def _load_dirs() -> list[dict]:
    out = _run(["--list-dirs"])
    rows = []
    for line in out.splitlines():
        parts = line.split("|")
        if len(parts) >= 3:
            rows.append({"name": parts[0], "path": parts[1], "exists": parts[2]})
    return rows


def _mimeapps_entries() -> list[dict]:
    """Read mimeapps.list directly for full MIME management."""
    if not os.path.isfile(_MIMEAPPS):
        return []
    entries = []
    in_section = False
    try:
        with open(_MIMEAPPS, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    in_section = line == "[Default Applications]"
                    continue
                if in_section and "=" in line and not line.startswith("#"):
                    mime, _, desktop = line.partition("=")
                    desktop = desktop.split(";", 1)[0]
                    entries.append({
                        "mime": mime.strip(),
                        "desktop": desktop.strip(),
                        "app": _desktop_name(desktop.strip()),
                    })
    except OSError:
        return []
    return entries


class XdgPage:
    """Default applications, MIME manager, XDG directories, portals."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._spinner_box = None
        self._mime_list: Gtk.ListBox | None = None
        self._mime_search: Gtk.SearchEntry | None = None
        self._mime_entries: list[dict] = []
        self._all_apps: list[dict] = []
        self._pending_ops: list[dict] = []
        self._visible_pickers: list[dict] = []
        self._default_rows: dict[str, Adw.ActionRow] = {}
        self._dir_rows: dict[str, Adw.ActionRow] = {}
        self._dirty = False
        self._on_dirty_changed = None

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh XDG configuration")
        refresh_btn.connect("clicked", lambda _b: self._full_refresh())
        header.pack_start(refresh_btn)

        add_mime_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_mime_btn.set_tooltip_text("Add custom MIME type")
        add_mime_btn.connect("clicked", lambda _b: self._show_add_mime_dialog())
        header.pack_start(add_mime_btn)

        spinner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        spinner_box.set_valign(Gtk.Align.CENTER)
        spinner_box.set_halign(Gtk.Align.CENTER)
        spinner_box.set_margin_top(48)
        spinner = Gtk.Spinner()
        spinner.set_size_request(32, 32)
        spinner.start()
        spinner_box.append(spinner)
        lbl = Gtk.Label(label="Loading XDG configuration\u2026")
        lbl.add_css_class("dim-label")
        spinner_box.append(lbl)
        self._spinner_box = spinner_box
        self._content_box.append(spinner_box)

        self._load_data()
        return toolbar

    def _load_data(self) -> None:
        def worker():
            defaults = _load_defaults()
            dirs = _load_dirs()
            entries = _mimeapps_entries()
            apps = _list_all_apps()
            portal = _run(["--portal-status"])
            health = _run(["--health"])
            GLib.idle_add(self._on_data_loaded, defaults, dirs, entries, apps, portal, health)

        threading.Thread(target=worker, daemon=True).start()

    def _on_data_loaded(self, defaults, dirs, entries, apps, portal, health) -> None:
        if self._spinner_box is not None and self._content_box is not None:
            self._content_box.remove(self._spinner_box)
            self._spinner_box = None

        self._all_apps = apps
        if self._visible_pickers:
            for state in list(self._visible_pickers):
                if state["popover"].get_visible():
                    self._fill_picker_list(state, self._all_apps)
        self._mime_entries = entries
        self._build_defaults(defaults)
        self._build_mime_manager(entries)
        self._build_dirs(dirs)
        self._build_status(portal, health)

    # ── Searchable app picker (a dedicated popover per dropdown) ──

    def _app_picker(self, current_desktop: str, on_change) -> Gtk.Widget:
        """A searchable dropdown listing every installed .desktop app.

        Each row gets its own popover (bound to its own button) — a single
        reparented popover glitches when opened from different buttons.
        """
        label = _desktop_name(current_desktop) if current_desktop else "Choose\u2026"
        btn = Gtk.Button()
        btn.set_valign(Gtk.Align.CENTER)
        btn.set_tooltip_text("Choose application\u2026")
        if current_desktop:
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            icon = _app_icon(_desktop_icon(current_desktop))
            icon.set_pixel_size(18)
            hbox.append(icon)
            lbl = Gtk.Label(label=label)
            hbox.append(lbl)
            btn.set_child(hbox)
        else:
            btn.set_label(label)

        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search apps\u2026")
        search.set_margin_top(8)
        search.set_margin_start(8)
        search.set_margin_end(8)
        search.set_margin_bottom(4)

        picker_list = Gtk.ListBox()
        picker_list.set_selection_mode(Gtk.SelectionMode.SINGLE)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(picker_list)
        scrolled.set_min_content_height(200)
        scrolled.set_max_content_height(320)
        scrolled.set_vexpand(True)

        browse_btn = Gtk.Button(icon_name="document-open-symbolic")
        browse_btn.set_valign(Gtk.Align.CENTER)
        browse_btn.set_tooltip_text("Browse for a .desktop file\u2026")

        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        search_box.set_margin_top(8)
        search_box.set_margin_start(8)
        search_box.set_margin_end(8)
        search_box.set_margin_bottom(4)
        search_box.append(search)
        search_box.append(browse_btn)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        vbox.set_size_request(280, -1)
        vbox.append(search_box)
        vbox.append(scrolled)

        popover = Gtk.Popover()
        popover.set_parent(btn)
        popover.set_child(vbox)

        state = {
            "search": search,
            "list": picker_list,
            "popover": popover,
            "btn": btn,
            "on_change": on_change,
        }

        search.connect("search-changed", self._on_picker_search, state)
        picker_list.connect("row-activated", self._on_picker_activated, state)
        browse_btn.connect("clicked", self._on_picker_browse, state)
        btn.connect("clicked", self._on_picker_clicked, current_desktop, state)
        popover.connect("closed", self._on_picker_closed, state)
        return btn

    def _set_picker_button(self, btn: Gtk.Button, app: dict) -> None:
        """Rebuild a picker button's child to show the app icon + name."""
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        icon = _app_icon(_desktop_icon(app["desktop"]))
        icon.set_pixel_size(18)
        hbox.append(icon)
        lbl = Gtk.Label(label=app["name"])
        hbox.append(lbl)
        btn.set_child(hbox)

    def _on_picker_clicked(self, btn: Gtk.Button, current_desktop: str, state: dict) -> None:
        search = state["search"]
        search.set_text("")
        self._fill_picker_list(state, self._all_apps)
        # Highlight the current app.
        if current_desktop:
            picker_list = state["list"]
            for i, a in enumerate(self._all_apps):
                if a["desktop"] == current_desktop:
                    picker_list.select_row(picker_list.get_row_at_index(i))
                    break
        if state["popover"] not in self._visible_pickers:
            self._visible_pickers.append(state)
        state["popover"].popup()

    def _on_picker_search(self, entry, state: dict) -> None:
        q = entry.get_text().strip().lower()
        if not q:
            self._fill_picker_list(state, self._all_apps)
            return
        filtered = [a for a in self._all_apps if q in a["name"].lower() or q in a["desktop"].lower()]
        self._fill_picker_list(state, filtered)

    def _fill_picker_list(self, state: dict, apps: list[dict]) -> None:
        picker_list = state["list"]
        while child := picker_list.get_first_child():
            picker_list.remove(child)
        for a in apps:
            row = Adw.ActionRow(title=a["name"], subtitle=a["desktop"])
            row.add_prefix(_app_icon(a.get("icon", "")))
            row.set_activatable(True)
            picker_list.append(row)

    def _on_picker_activated(self, _list, row: Gtk.ListBoxRow, state: dict) -> None:
        idx = row.get_index()
        q = state["search"].get_text().strip().lower()
        apps = self._all_apps if not q else [
            a for a in self._all_apps if q in a["name"].lower() or q in a["desktop"].lower()
        ]
        if 0 <= idx < len(apps):
            app = apps[idx]
            self._set_picker_button(state["btn"], app)
            on_change = state.get("on_change")
            if on_change is not None:
                on_change(app)
        state["popover"].popdown()

    def _on_picker_closed(self, _popover, state: dict) -> None:
        state["search"].set_text("")
        if state in self._visible_pickers:
            self._visible_pickers.remove(state)

    def _on_picker_browse(self, _btn, state: dict) -> None:
        dialog = Gtk.FileDialog.new()
        dialog.set_title("Select a .desktop file")
        filt = Gtk.FileFilter()
        filt.add_pattern("*.desktop")
        filt.set_name("Desktop entries")
        filters = Gio.ListStore.new(Gtk.FileFilter)
        filters.append(filt)
        dialog.set_filters(filters)

        def on_chosen(_dlg, result):
            try:
                gfile = _dlg.open_finish(result)
            except GLib.Error:
                return
            if not gfile:
                return
            path = gfile.get_path()
            if not path:
                return
            desktop = os.path.basename(path)
            app = {
                "desktop": desktop,
                "name": _desktop_name_from_path(path, desktop),
                "icon": "",
            }
            self._set_picker_button(state["btn"], app)
            on_change = state.get("on_change")
            if on_change is not None:
                on_change(app)
            state["popover"].popdown()

        dialog.open(self._window, None, on_chosen)

    # ── Default Applications ──

    def _build_defaults(self, defaults) -> None:
        group = Adw.PreferencesGroup(
            title="Default Applications",
            description="Choose which app opens each type of content. Changes apply when you save.",
        )

        by_mime = {d["mime"]: d for d in defaults}

        for label, mime in _CATEGORIES:
            current = by_mime.get(mime)
            current_app = current["app"] if current else "None"
            current_desktop = current["desktop"] if current else ""

            row = Adw.ActionRow(title=label, subtitle=current_app)
            if current_desktop:
                row.add_prefix(_app_icon(_desktop_icon(current_desktop)))
            row.add_suffix(self._app_picker(current_desktop, self._make_default_handler(mime, row)))
            self._default_rows[mime] = row

            group.add(row)

        reset_btn = Gtk.Button(label="Reset to defaults")
        reset_btn.set_valign(Gtk.Align.CENTER)
        reset_btn.connect("clicked", lambda _b: self._reset_defaults())
        reset_row = Adw.ActionRow(title="Reset Defaults", subtitle="Regenerate mimeapps.list from current settings")
        reset_row.add_suffix(reset_btn)
        group.add(reset_row)

        self._content_box.append(group)

    def _make_default_handler(self, mime: str, row: Adw.ActionRow):
        def handler(app: dict):
            self._set_default(mime, app["desktop"], row, None)
        return handler

    def _set_default(self, mime: str, desktop: str, row: Adw.ActionRow, dd: Gtk.DropDown) -> None:
        new_name = _desktop_name(desktop)
        self._pending_ops.append({"kind": "set-default", "mime": mime, "desktop": desktop})
        # Optimistic UI: show the chosen app immediately; it persists on Save.
        if row is not None:
            row.set_subtitle(new_name)
        self._mark_dirty()
        self._window.show_toast(f"Staged: {mime} \u2192 {new_name}. Save to apply.")


    # ── MIME Type Manager ──

    def _build_mime_manager(self, entries) -> None:
        group = Adw.PreferencesGroup(
            title=f"MIME Types ({len(entries)})",
            description="Every MIME association — search, change which app opens it, or remove.",
        )

        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search MIME types\u2026")
        search.set_hexpand(True)
        search.connect("search-changed", lambda e: self._rebuild_mime_list())
        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.set_tooltip_text("Add custom MIME type")
        add_btn.connect("clicked", lambda _b: self._show_add_mime_dialog())
        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        search_box.append(search)
        search_box.append(add_btn)
        search_row = Adw.ActionRow(title="")
        search_row.set_activatable(False)
        search_row.set_child(search_box)
        group.add(search_row)
        self._mime_search = search

        self._mime_list = Gtk.ListBox()
        self._mime_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(self._mime_list)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(200)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

        self._content_box.append(group)
        self._rebuild_mime_list()

    def _rebuild_mime_list(self) -> None:
        if self._mime_list is None:
            return
        while child := self._mime_list.get_first_child():
            self._mime_list.remove(child)

        q = (self._mime_search.get_text() if self._mime_search else "").strip().lower()
        for entry in sorted(self._mime_entries, key=lambda e: e["mime"]):
            if q and q not in entry["mime"].lower() and q not in entry["app"].lower():
                continue
            row = Adw.ActionRow(title=entry["mime"], subtitle=entry["app"])
            row.add_prefix(_app_icon(_desktop_icon(entry["desktop"])))
            row.add_suffix(self._app_picker(entry["desktop"], self._make_mime_handler(entry, row)))

            del_btn = Gtk.Button(icon_name="user-trash-symbolic")
            del_btn.set_valign(Gtk.Align.CENTER)
            del_btn.set_tooltip_text("Remove this MIME association")
            del_btn.connect("clicked", lambda _b, e=entry: self._remove_mime(e))
            row.add_suffix(del_btn)

            self._mime_list.append(row)

        if not self._mime_entries:
            empty_lbl = Gtk.Label(label="No MIME types configured yet")
            empty_lbl.set_margin_top(16)
            empty_lbl.set_margin_bottom(16)
            empty_lbl.add_css_class("dim-label")
            empty_lbl.set_halign(Gtk.Align.CENTER)
            self._mime_list.append(empty_lbl)

    def _make_mime_handler(self, entry: dict, row: Adw.ActionRow):
        def handler(app: dict):
            self._set_default(entry["mime"], app["desktop"], row, None)
        return handler

    def _remove_mime(self, entry: dict) -> None:
        mime = entry["mime"]
        self._pending_ops.append({"kind": "remove-mime", "mime": mime})
        # Optimistic UI: drop the row now; the file edit happens on Save.
        self._mime_entries = [e for e in self._mime_entries if e["mime"] != mime]
        self._rebuild_mime_list()
        self._mark_dirty()
        self._window.show_toast(f"Staged: remove {mime}. Save to apply.")

    def _show_add_mime_dialog(self) -> None:
        mime_entry = Gtk.Entry()
        mime_entry.set_placeholder_text("e.g. application/x-myformat")
        mime_entry.set_margin_bottom(4)

        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        extra.append(mime_entry)

        dialog = Adw.AlertDialog(
            heading="Add MIME Type",
            body="Enter a MIME type. You can pick the app from the list after adding.",
        )
        dialog.set_extra_child(extra)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("add", "Add")
        dialog.set_response_appearance("add", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_resp(_d, resp: str):
            if resp != "add":
                return
            mime = mime_entry.get_text().strip()
            if not mime or not re.match(r"^[\w.+-]+/[\w.+-]+$", mime):
                self._window.show_toast("Invalid MIME type", timeout=5)
                return
            self._add_mime(mime)

        dialog.connect("response", on_resp)
        dialog.present(self._window)

    def _add_mime(self, mime: str) -> None:
        self._pending_ops = [
            op for op in self._pending_ops
            if not (op["kind"] == "set-default" and op["mime"] == mime)
        ]
        self._pending_ops.append({"kind": "set-default", "mime": mime, "desktop": ""})
        # Optimistic UI: show the new association now; the app can be picked
        # from the list and persists on Save.
        self._mime_entries = [e for e in self._mime_entries if e["mime"] != mime]
        self._mime_entries.append({"mime": mime, "desktop": "", "app": "Not set"})
        self._rebuild_mime_list()
        self._mark_dirty()
        self._window.show_toast(f"Staged: add {mime}. Pick an app from the list, then save.")

    # ── XDG Directories ──

    def _build_dirs(self, dirs) -> None:
        group = Adw.PreferencesGroup(
            title="User Directories",
            description="Set where each type of file is stored.",
        )

        by_name = {d["name"]: d for d in dirs}
        for name in _DIRS:
            entry = by_name.get(name, {"name": name, "path": "—", "exists": "no"})
            title = name[:1] + name[1:].lower()
            row = Adw.ActionRow(title=title, subtitle=entry["path"])
            folder = _folder_icon(_DIR_ICONS.get(name, "folder"))
            row.add_prefix(folder)

            badge = Gtk.Label(label="Exists" if entry["exists"] == "yes" else "Missing")
            badge.add_css_class("success" if entry["exists"] == "yes" else "error")
            badge.set_valign(Gtk.Align.CENTER)
            row.add_suffix(badge)

            move_btn = Gtk.Button(label="Move\u2026")
            move_btn.set_valign(Gtk.Align.CENTER)
            move_btn.connect("clicked", lambda _b, n=name: self._move_dir(n))
            row.add_suffix(move_btn)

            self._dir_rows[name] = row
            group.add(row)

        ensure_btn = Gtk.Button(label="Ensure dirs")
        ensure_btn.set_valign(Gtk.Align.CENTER)
        ensure_btn.connect("clicked", lambda _b: self._ensure_dirs())
        ensure_row = Adw.ActionRow(title="Ensure Directories", subtitle="Create any missing user directories")
        ensure_row.add_suffix(ensure_btn)
        group.add(ensure_row)

        self._content_box.append(group)

    def _move_dir(self, name: str) -> None:
        dialog = Gtk.FileDialog.new()
        dialog.set_title(f"Select new {name.lower()} folder")
        dialog.select_folder(self._window, None, lambda _d, result: self._on_dir_chosen(_d, name, result))

    def _on_dir_chosen(self, dialog, name: str, result) -> None:
        try:
            folder = dialog.select_folder_finish(result)
        except GLib.Error:
            return
        path = folder.get_path() if folder else None
        if not path:
            return

        self._pending_ops.append({"kind": "set-dir", "name": name, "path": path})
        row = self._dir_rows.get(name)
        if row is not None:
            row.set_subtitle(path)
        self._mark_dirty()
        self._window.show_toast(f"Staged: {name} \u2192 {path}. Save to apply.")

    def _ensure_dirs(self) -> None:
        self._pending_ops.append({"kind": "ensure-dirs"})
        self._mark_dirty()
        self._window.show_toast("Staged: ensure directories. Save to apply.")

    # ── Status / Portals ──

    def _build_status(self, portal: str, health: str) -> None:
        group = Adw.PreferencesGroup(
            title="Portals and Health",
            description="Desktop portal backend and default-app health.",
        )

        backend = "hyprland"
        if "backend=" in portal:
            backend = portal.split("backend=", 1)[1].split("|", 1)[0]
        options = ["Auto", "Hyprland", "GTK"]
        values = ["auto", "hyprland", "gtk"]
        model = Gtk.StringList.new(options)
        dd = Gtk.DropDown(model=model)
        dd.set_valign(Gtk.Align.CENTER)
        try:
            dd.set_selected(values.index(backend))
        except ValueError:
            dd.set_selected(0)
        dd.connect("notify::selected", self._on_portal_selected, values)
        portal_row = Adw.ActionRow(title="Portal Backend", subtitle="Which portal provides file/screen sharing")
        portal_row.add_suffix(dd)
        group.add(portal_row)

        summary = "No health data"
        if "total=" in health:
            total = health.split("total=", 1)[1].split("|", 1)[0]
            ghost = health.split("ghost_desktop=", 1)[1].split("|", 1)[0] if "ghost_desktop=" in health else "0"
            summary = f"{total} defaults, {ghost} broken"
        health_lbl = Gtk.Label(label=summary)
        health_lbl.add_css_class("dim-label")
        health_lbl.set_valign(Gtk.Align.CENTER)
        health_row = Adw.ActionRow(title="Health Check", subtitle="Missing or broken default applications")
        health_row.add_suffix(health_lbl)
        group.add(health_row)

        self._content_box.append(group)

    def _on_portal_selected(self, dd: Gtk.DropDown, _pspec, values: list[str]) -> None:
        idx = dd.get_selected()
        if idx < 0 or idx >= len(values):
            return
        backend = values[idx]
        if backend == "auto":
            return
        self._pending_ops.append({"kind": "portal-set", "backend": backend})
        self._mark_dirty()
        self._window.show_toast(f"Staged: portal backend \u2192 {backend}. Save to apply.")

    # ── Refresh ──

    def _full_refresh(self) -> None:
        for child in list(self._content_box):
            self._content_box.remove(child)
        spinner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        spinner_box.set_valign(Gtk.Align.CENTER)
        spinner_box.set_halign(Gtk.Align.CENTER)
        spinner_box.set_margin_top(48)
        spinner = Gtk.Spinner()
        spinner.set_size_request(32, 32)
        spinner.start()
        spinner_box.append(spinner)
        lbl = Gtk.Label(label="Loading XDG configuration\u2026")
        lbl.add_css_class("dim-label")
        spinner_box.append(lbl)
        self._spinner_box = spinner_box
        self._content_box.append(spinner_box)
        self._load_data()

    # ── Lifecycle (staged, applied on Save) ──

    def _mark_dirty(self) -> None:
        if not self._dirty:
            self._dirty = True
            if self._on_dirty_changed:
                self._on_dirty_changed()

    def _apply_remove_mime(self, mime: str) -> None:
        """Write the mimeapps.list line removal for a staged op."""
        if not os.path.isfile(_MIMEAPPS):
            return
        try:
            lines = open(_MIMEAPPS, encoding="utf-8", errors="replace").readlines()
        except OSError:
            return
        with open(_MIMEAPPS, "w", encoding="utf-8") as f:
            for line in lines:
                if line.strip().startswith(f"{mime}="):
                    continue
                f.write(line)

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        ops = list(self._pending_ops)
        self._pending_ops.clear()
        self._dirty = False
        if not ops:
            return

        def worker():
            for op in ops:
                kind = op["kind"]
                if kind == "set-default":
                    _run(["--set-default", op["mime"], op["desktop"]], timeout=20)
                elif kind == "remove-mime":
                    self._apply_remove_mime(op["mime"])
                elif kind == "reset-defaults":
                    _run(["--reset-defaults"], timeout=30)
                elif kind == "set-dir":
                    _run(["--set-dir", op["name"], op["path"]], timeout=20)
                elif kind == "ensure-dirs":
                    _run(["--ensure-dirs"], timeout=30)
                elif kind == "portal-set":
                    _run(["--portal-set", op["backend"]], timeout=30)
            GLib.idle_add(self._after_apply)

        threading.Thread(target=worker, daemon=True).start()

    def _after_apply(self) -> None:
        self._window.show_toast("XDG changes applied", timeout=5)
        self._full_refresh()

    def discard(self) -> None:
        self._pending_ops.clear()
        self._dirty = False
        self._full_refresh()

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        for op in list(self._pending_ops):
            kind = op["kind"]
            if kind == "set-default":
                title = op["mime"]
                subtitle = f"Default app \u2192 {_desktop_name(op['desktop'])}"
            elif kind == "remove-mime":
                title = op["mime"]
                subtitle = "Remove MIME association"
            elif kind == "reset-defaults":
                title = "Default Applications"
                subtitle = "Reset to defaults"
            elif kind == "set-dir":
                title = op["name"]
                subtitle = f"Move to {op['path']}"
            elif kind == "ensure-dirs":
                title = "User Directories"
                subtitle = "Ensure directories exist"
            elif kind == "portal-set":
                title = "Portal Backend"
                subtitle = f"Set to {op['backend']}"
            else:
                continue
            yield PendingChange(
                category="Default Apps",
                title=title,
                subtitle=subtitle,
                kind="modified" if kind != "remove-mime" else "removed",
                revert=self.discard,
                navigate_to="xdg",
                icon=_XDG_ICON,
            )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "xdg:apps", "label": "Default Applications",
             "description": "Choose default browser, editor, file manager, image/video apps",
             "_group_id": "xdg", "_group_label": "Default Apps", "_section_label": "Applications"},
            {"key": "xdg:mime", "label": "MIME Types",
             "description": "Search, change, or add MIME type associations",
             "_group_id": "xdg", "_group_label": "Default Apps", "_section_label": "MIME Types"},
            {"key": "xdg:dirs", "label": "User Directories",
             "description": "Relocate Desktop, Documents, Downloads, Pictures and more",
             "_group_id": "xdg", "_group_label": "Default Apps", "_section_label": "Directories"},
            {"key": "xdg:portal", "label": "Portals & Health",
             "description": "Desktop portal backend and default-app health check",
             "_group_id": "xdg", "_group_label": "Default Apps", "_section_label": "Portals & Health"},
        ]


__all__ = ["XdgPage"]
