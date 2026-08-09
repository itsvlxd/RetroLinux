"""Font management page — active fonts, list, and install via package manager."""

import os
import shlex
import subprocess
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gio, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import clear_children, make_page_layout
from settings.ui.managed_row import make_combo_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_RETRO_DIR = os.environ.get("RETRO_DIR", "/opt/retrolinux")
_FONT_CORE = os.path.join(_RETRO_DIR, "scripts", "font_core.sh")

_FONT_CATEGORIES = [
    ("main", "Main Font", "RETRO_FONT_MAIN", "Default system UI font"),
    ("nerd", "Nerd Font", "RETRO_FONT_NERD", "Monospace font for terminals and code"),
    ("emoji", "Emoji Font", "RETRO_FONT_EMOJI", "Emoji and icon font"),
]

_FONT_ICON = "preferences-desktop-font-symbolic"

_SYSTEM_FONT_PKGS = {
    "gsfonts", "ttf-dejavu", "noto-fonts", "texlive-fontsextra",
    "texlive-core", "adobe-source-code-pro-fonts", "ttf-liberation",
}


def update_fonts_sidebar(window) -> None:
    """Update the Fonts sidebar row with installed font count."""
    try:
        sidebar = getattr(window, "_sidebar", None)
        if sidebar is None:
            return
        row = sidebar._rows_by_id.get("fonts")
        if row is None:
            return
        if not hasattr(row, "_fonts_sidebar_label"):
            lbl = Gtk.Label()
            lbl.set_valign(Gtk.Align.CENTER)
            lbl.add_css_class("badge")
            row.add_suffix(lbl)
            row._fonts_sidebar_label = lbl
        result = subprocess.run(
            ["bash", _FONT_CORE, "--list-installed"],
            capture_output=True, text=True, timeout=10,
            stdin=subprocess.DEVNULL,
        )
        count = len([l for l in result.stdout.strip().splitlines() if l.strip()])
        row._fonts_sidebar_label.set_visible(count > 0)
        if count:
            row._fonts_sidebar_label.set_label(f"{count} fonts")
    except Exception:
        pass


class FontsPage:
    """Font management — active fonts, installable list, package install."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._fonts: list[str] = []
        self._active: dict[str, str] = {"main": "", "nerd": "", "emoji": ""}
        self._orig_active: dict[str, str] = {}
        self._fonts_dirty = False
        self._on_dirty_changed = None
        self._suppress_combo = False

        self._combo_rows: dict[str, Adw.ComboRow] = {}
        self._font_list: Gtk.ListBox
        self._search_entry: Gtk.SearchEntry
        self._selected: set[str] = set()
        self._bulk_delete_row: Adw.ActionRow

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh font list")
        refresh_btn.connect("clicked", lambda _b: self._full_refresh())
        header.pack_start(refresh_btn)

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_tooltip_text("Add font")
        add_btn.connect("clicked", lambda _b: self._show_add_dialog())
        header.pack_start(add_btn)

        self._load_data()

        active_group = Adw.PreferencesGroup(title="Active Fonts")
        self._populate_combo_rows(active_group)
        self._content_box.append(active_group)

        list_group = Adw.PreferencesGroup(
            title=f"Installed Fonts ({len(self._fonts)})",
            description="Click a font to set it as active",
        )
        self._populate_font_list(list_group)
        self._content_box.append(list_group)

        update_fonts_sidebar(self._window)

        return toolbar_view

    # ── Data ──

    def _load_data(self) -> None:
        self._fonts = []
        try:
            result = subprocess.run(
                ["bash", _FONT_CORE, "--list-installed"],
                capture_output=True, text=True, timeout=15,
                stdin=subprocess.DEVNULL,
            )
            if result.returncode == 0:
                self._fonts = sorted(
                    l.strip() for l in result.stdout.strip().splitlines() if l.strip()
                )
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass

        from lib.python.variable import get_var
        self._active = {
            "main": get_var("RETRO_FONT_MAIN") or "",
            "nerd": get_var("RETRO_FONT_NERD") or "",
            "emoji": get_var("RETRO_FONT_EMOJI") or "",
        }
        self._orig_active = dict(self._active)
        self._fonts_dirty = False

        # Sort: active fonts first (main → nerd → emoji), then alphabetical
        self._fonts.sort(key=lambda f: (
            0 if f.lower() == self._active.get("main", "").lower() else
            1 if f.lower() == self._active.get("nerd", "").lower() else
            2 if f.lower() == self._active.get("emoji", "").lower() else 3,
            f.lower(),
        ))

    def _full_refresh(self) -> None:
        self._load_data()
        self._refresh_combo_rows()
        self._rebuild_font_list()
        update_fonts_sidebar(self._window)

    # ── Active Fonts (Adw.ComboRow) ──

    def _populate_combo_rows(self, group: Adw.PreferencesGroup) -> None:
        self._combo_rows = {}
        for cat_id, label, _var_name, desc in _FONT_CATEGORIES:
            model = Gtk.StringList.new(self._fonts) if self._fonts else Gtk.StringList.new([])
            current = self._active.get(cat_id, "")
            idx = 0
            if current:
                for i, f in enumerate(self._fonts):
                    if f.lower() == current.lower():
                        idx = i
                        break
            row = make_combo_row(label, subtitle=desc, model=model, selected=idx)
            row.connect("notify::selected", self._on_combo_changed, cat_id)
            group.add(row)
            self._combo_rows[cat_id] = row

    def _on_combo_changed(self, row: Adw.ComboRow, _pspec, cat_id: str) -> None:
        if self._suppress_combo:
            return
        idx = row.get_selected()
        if 0 <= idx < len(self._fonts):
            self._active[cat_id] = self._fonts[idx]
        else:
            self._active[cat_id] = ""
        self._fonts_dirty = any(
            self._active[k] != self._orig_active.get(k, "") for k in self._active
        )
        if self._on_dirty_changed:
            self._on_dirty_changed()
        self._rebuild_font_list()

    def _refresh_combo_rows(self) -> None:
        self._suppress_combo = True
        try:
            for cat_id, row in self._combo_rows.items():
                current = self._active.get(cat_id, "")
                model = Gtk.StringList.new(self._fonts) if self._fonts else Gtk.StringList.new([])
                row.set_model(model)
                if current:
                    for i, f in enumerate(self._fonts):
                        if f.lower() == current.lower():
                            row.set_selected(i)
                            break
                else:
                    row.set_selected(0)
        finally:
            self._suppress_combo = False

    # ── Installed Fonts ──

    def _populate_font_list(self, group: Adw.PreferencesGroup) -> None:
        self._search_entry = Gtk.SearchEntry()
        self._search_entry.set_placeholder_text("Search fonts\u2026")
        self._search_entry.set_hexpand(True)

        self._bulk_delete_btn = Gtk.Button(label="Delete Selected")
        self._bulk_delete_btn.add_css_class("destructive-action")
        self._bulk_delete_btn.set_valign(Gtk.Align.CENTER)
        self._bulk_delete_btn.connect("clicked", lambda _b: self._bulk_delete())
        self._bulk_delete_btn.set_visible(False)

        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        search_box.append(self._search_entry)
        search_box.append(self._bulk_delete_btn)

        search_row = Adw.ActionRow(title="")
        search_row.set_activatable(False)
        search_row.set_child(search_box)
        self._search_entry.connect("search-changed", lambda e: self._rebuild_font_list())
        group.add(search_row)
        self._bulk_delete_row = search_row

        self._font_list = Gtk.ListBox()
        self._font_list.set_selection_mode(Gtk.SelectionMode.NONE)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(self._font_list)
        scrolled.set_vexpand(True)
        scrolled.set_min_content_height(210)

        frame = Gtk.Frame()
        frame.set_child(scrolled)
        list_row = Adw.ActionRow(title="")
        list_row.set_activatable(False)
        list_row.set_child(frame)
        group.add(list_row)

        self._rebuild_font_list()

    def _rebuild_font_list(self) -> None:
        while child := self._font_list.get_first_child():
            self._font_list.remove(child)

        self._bulk_delete_btn.set_visible(len(self._selected) > 0)

        q = self._search_entry.get_text().lower().strip() if hasattr(self, '_search_entry') else ""
        for font in self._fonts:
            if q and q not in font.lower():
                continue
            is_main = font.lower() == self._active.get("main", "").lower()
            is_nerd = font.lower() == self._active.get("nerd", "").lower()
            is_emoji = font.lower() == self._active.get("emoji", "").lower()
            row = Adw.ActionRow(title=font)

            check = Gtk.CheckButton()
            check.set_valign(Gtk.Align.CENTER)
            if font in self._selected:
                check.set_active(True)
            check.connect("toggled", lambda _c, f=font: self._toggle_select(f, _c.get_active()))
            row.add_prefix(check)

            if is_main or is_nerd or is_emoji:
                tags = []
                if is_main:
                    tags.append("Main")
                if is_nerd:
                    tags.append("Nerd")
                if is_emoji:
                    tags.append("Emoji")
                lbl = Gtk.Label(label=" + ".join(tags))
                lbl.add_css_class("badge")
                lbl.set_valign(Gtk.Align.CENTER)
                row.add_suffix(lbl)

            edit_btn = Gtk.Button(icon_name="document-edit-symbolic")
            edit_btn.set_valign(Gtk.Align.CENTER)
            edit_btn.set_tooltip_text("Assign category")
            edit_btn.connect("clicked", lambda _b, f=font: self._show_font_assign_dialog(f))
            row.add_suffix(edit_btn)

            delete_btn = Gtk.Button(icon_name="user-trash-symbolic")
            delete_btn.set_valign(Gtk.Align.CENTER)
            delete_btn.set_tooltip_text(f"Delete {font}")
            delete_btn.connect("clicked", lambda _b, f=font: self._delete_font(f))
            row.add_suffix(delete_btn)

            self._font_list.append(row)

    def _show_font_assign_dialog(self, font_name: str) -> None:
        dialog = Adw.AlertDialog(heading=font_name, body="Set as which font category?")
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("emoji", "Emoji Font")
        dialog.add_response("nerd", "Nerd Font")
        dialog.add_response("main", "Main Font")
        dialog.set_response_appearance("main", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_resp(_d, resp: str):
            if resp != "cancel" and resp in self._combo_rows:
                combo = self._combo_rows[resp]
                for i, f in enumerate(self._fonts):
                    if f == font_name:
                        combo.set_selected(i)
                        break

        dialog.connect("response", on_resp)
        dialog.present(self._window)

    def _toggle_select(self, font: str, selected: bool) -> None:
        if selected:
            self._selected.add(font)
        else:
            self._selected.discard(font)
        n = len(self._selected)
        self._bulk_delete_btn.set_visible(n > 0)
        if n:
            self._bulk_delete_btn.set_label(f"Delete Selected ({n})")

    def _bulk_delete(self) -> None:
        if not self._selected:
            return
        from settings.ui import confirm

        def do_all():
            fonts = list(self._selected)
            self._selected.clear()
            self._bulk_delete_btn.set_visible(False)

            all_paths = []
            for font in fonts:
                all_paths.extend(self._get_font_files(font))

            deleted = 0
            remaining = []
            for path in all_paths:
                try:
                    os.remove(path)
                    deleted += 1
                except OSError:
                    remaining.append(path)

            if deleted:
                self._window.show_toast(f"Deleted {deleted} font file(s)")

            if deleted:
                try:
                    subprocess.run(["fc-cache", "-f"], capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
                    subprocess.run(["retro", "font", "regenerate"], capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
                except Exception:
                    pass
                self._full_refresh()

            if remaining:
                args = " ".join(shlex.quote(p) for p in remaining)
                self._launch_kitty(
                    f"sudo rm -f {args} && retro font regenerate"
                )
                self._window.show_toast(
                    "Deleting in terminal \u2014 will refresh when done",
                    timeout=3,
                )
                GLib.timeout_add(60000, self._full_refresh)

        confirm(
            self._window,
            heading=f"Delete {len(self._selected)} font(s)?",
            body="Removing font files from the system and regenerating the cache.",
            label="Delete All",
            on_confirm=do_all,
        )

    def _delete_font(self, font_name: str) -> None:
        pkg = self._family_to_pkg(font_name)
        if pkg and pkg.lower() not in _SYSTEM_FONT_PKGS:
            from settings.ui import confirm
            confirm(
                self._window,
                heading=f"Uninstall {pkg}?",
                body=f"The font \u201c{font_name}\u201d is owned by {pkg}. "
                     "A terminal window will open to remove it.",
                label="Uninstall",
                on_confirm=lambda: (
                    self._launch_kitty(f"{self._helper()} -Rns {pkg}"),
                    GLib.timeout_add(3000, self._full_refresh),
                ),
            )
            return

        from settings.ui import confirm
        confirm(
            self._window,
            heading=f"Delete {font_name}?",
            body="Remove font files from the system and regenerate the cache.",
            label="Delete",
            on_confirm=lambda: self._delete_files(font_name),
        )

    def _delete_files(self, font_name: str) -> None:
        paths = self._get_font_files(font_name)
        deleted = 0
        for path in paths:
            try:
                os.remove(path)
                deleted += 1
            except OSError:
                pass
        if deleted:
            try:
                subprocess.run(
                    ["fc-cache", "-f"],
                    capture_output=True, text=True, timeout=30,
                    stdin=subprocess.DEVNULL,
                )
                subprocess.run(
                    ["retro", "font", "regenerate"],
                    capture_output=True, text=True, timeout=30,
                    stdin=subprocess.DEVNULL,
                )
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
                pass
            self._window.show_toast(f"Deleted {deleted} font file(s)")
            self._full_refresh()
        elif paths:
            args = " ".join(shlex.quote(p) for p in paths)
            self._launch_kitty(
                f"sudo rm -f {args} && retro font regenerate"
            )
            self._window.show_toast("Attempting deletion with elevated permissions\u2026")
        else:
            self._window.show_toast("No font files found", timeout=5)

    @staticmethod
    def _family_to_pkg(font_name: str) -> str:
        try:
            result = subprocess.run(
                ["bash", _FONT_CORE, "--family-to-pkg", font_name],
                capture_output=True, text=True, timeout=10,
                stdin=subprocess.DEVNULL,
            )
            return result.stdout.strip()
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            return ""

    @staticmethod
    def _get_font_files(font_name: str) -> list[str]:
        paths = []
        try:
            result = subprocess.run(
                ["fc-list", f":family={font_name}", "file"],
                capture_output=True, text=True, timeout=10,
                stdin=subprocess.DEVNULL,
            )
            for line in result.stdout.strip().splitlines():
                path = line.strip().split(":")[0] if ":" in line else line.strip()
                if path:
                    paths.append(os.path.expanduser(path))
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
        return paths

    @staticmethod
    def _helper() -> str:
        from lib.python.variable import get_var
        return get_var("PKG_HELPER") or "yay"

    @staticmethod
    def _launch_kitty(command: str) -> None:
        cmd = f"kitty -- bash -c '{command}; echo; echo Press Enter to close.; read'"
        lua = f'hl.dsp.exec_cmd("{cmd}", {{ float = true, size = {{ 800, 500 }}, center = true }})'
        subprocess.Popen(
            ["hyprctl", "dispatch", lua],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    # ── Add Font dialog ──

    def _show_add_dialog(self) -> None:
        SearchFontDialog(self._window, self._on_font_installed, self._pick_font_file).present(self._window)

    def _pick_font_file(self) -> None:
        dialog = Gtk.FileDialog()
        dialog.set_title("Select font files to install")
        filt = Gtk.FileFilter()
        for ext in ("*.ttf", "*.otf", "*.woff", "*.woff2", "*.ttc"):
            filt.add_pattern(ext)
        filt.set_name("Font files")
        filters = Gio.ListStore.new(Gtk.FileFilter)
        filters.append(filt)
        dialog.set_filters(filters)
        dialog.open_multiple(self._window, None, self._on_files_chosen)

    def _on_files_chosen(self, _dlg, result) -> None:
        try:
            gfiles = _dlg.open_multiple_finish(result)
        except GLib.Error:
            return
        if not gfiles:
            return

        total_installed = 0
        total_overwritten = 0
        for gfile in gfiles:
            path = gfile.get_path()
            if not path:
                continue
            try:
                res = subprocess.run(
                    ["bash", _FONT_CORE, "--install-file", path],
                    capture_output=True, text=True, timeout=30,
                    stdin=subprocess.DEVNULL,
                )
                for line in res.stdout.strip().splitlines():
                    if line.startswith("RESULT|"):
                        for part in line.split("|"):
                            if part.startswith("installed="):
                                total_installed += int(part.split("=", 1)[1])
                            elif part.startswith("overwritten="):
                                total_overwritten += int(part.split("=", 1)[1])
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError, ValueError):
                pass

        if total_installed or total_overwritten:
            self._window.show_toast(f"Installed {total_installed} font(s), overwritten {total_overwritten}")
            self._full_refresh()
        else:
            self._window.show_toast("No new fonts installed \u2014 check file format", timeout=5)

    def _on_font_installed(self) -> None:
        self._full_refresh()

    # ── Save lifecycle ──

    def is_dirty(self) -> bool:
        return self._fonts_dirty

    def mark_saved(self) -> None:
        if not self._fonts_dirty:
            return
        from lib.python.variable import set_var
        for cat_id, _, var_name, _desc in _FONT_CATEGORIES:
            set_var(var_name, self._active.get(cat_id, ""))
        try:
            subprocess.run(
                ["bash", _FONT_CORE, "--sync"],
                capture_output=True, text=True, timeout=30,
                stdin=subprocess.DEVNULL,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
        subprocess.run(
            ["retro", "app", "all", "refresh"],
            capture_output=True, text=True, timeout=30,
            stdin=subprocess.DEVNULL,
        )
        self._orig_active = dict(self._active)
        self._fonts_dirty = False
        self._full_refresh()

    def discard(self) -> None:
        self._active = dict(self._orig_active)
        for cat_id, combo in self._combo_rows.items():
            current = self._active.get(cat_id, "")
            if current:
                for i, f in enumerate(self._fonts):
                    if f.lower() == current.lower():
                        combo.set_selected(i)
                        break
            else:
                combo.set_selected(0)
        self._fonts_dirty = False
        self._rebuild_font_list()

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._fonts_dirty:
            yield PendingChange(
                category="Fonts",
                title="Active Fonts",
                subtitle="Main, Nerd, or Emoji font changed",
                navigate_to="fonts",
                icon=_FONT_ICON,
                kind="modified",
                revert=self.discard,
            )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        n = len(self._fonts)
        return [
            {"key": "fonts:active", "label": "Active Fonts",
             "description": "Set main, nerd, and emoji fonts",
             "_group_id": "fonts", "_group_label": "Fonts", "_section_label": "Active Fonts"},
            {"key": "fonts:list", "label": f"Installed Fonts ({n})",
             "description": f"{n} font families available",
             "_group_id": "fonts", "_group_label": "Fonts", "_section_label": "Installed Fonts"},
            {"key": "fonts:install", "label": "Add Font",
             "description": "Import font files or search font packages",
             "_group_id": "fonts", "_group_label": "Fonts", "_section_label": "Add Font"},
        ]


class SearchFontDialog(Adw.Dialog):
    """Dialog to search remote font packages and install them, or import from file."""

    def __init__(self, window: "RetroSettingsWindow", on_installed, on_file=None):
        super().__init__()
        self._window = window
        self._on_installed = on_installed
        self._on_file = on_file
        self.set_title("Search Font Packages")
        self.set_content_width(550)
        self.set_content_height(400)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()

        if on_file:
            file_btn = Gtk.Button(label="Import file\u2026")
            file_btn.connect("clicked", lambda _b: (on_file(), self.close()))
            header.pack_start(file_btn)

        toolbar.add_top_bar(header)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(550)
        clamp.set_tightening_threshold(450)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self._search_entry = Gtk.SearchEntry()
        self._search_entry.set_placeholder_text("e.g. jetbrains")
        self._search_entry.set_hexpand(True)
        self._search_entry.connect("activate", lambda _e: self._do_search())
        search_box.append(self._search_entry)

        search_btn = Gtk.Button(label="Search")
        search_btn.add_css_class("suggested-action")
        search_btn.connect("clicked", lambda _b: self._do_search())
        search_box.append(search_btn)
        box.append(search_box)

        self._results_label = Gtk.Label(label="Enter a query and press Search")
        self._results_label.set_halign(Gtk.Align.START)
        self._results_label.add_css_class("dim-label")
        self._results_label.set_margin_top(6)
        box.append(self._results_label)

        self._result_list = Gtk.ListBox()
        self._result_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(self._result_list)
        scrolled.set_vexpand(True)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        box.append(frame)

        # Pagination
        nav = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        nav.set_halign(Gtk.Align.CENTER)
        self._prev_btn = Gtk.Button(label="Previous")
        self._prev_btn.connect("clicked", lambda _b: self._show_page(self._page - 1))
        self._prev_btn.set_sensitive(False)
        nav.append(self._prev_btn)
        self._page_label = Gtk.Label(label="")
        self._page_label.set_valign(Gtk.Align.CENTER)
        nav.append(self._page_label)
        self._next_btn = Gtk.Button(label="Next")
        self._next_btn.connect("clicked", lambda _b: self._show_page(self._page + 1))
        self._next_btn.set_sensitive(False)
        nav.append(self._next_btn)
        box.append(nav)

        clamp.set_child(box)
        scrolled2 = Gtk.ScrolledWindow()
        scrolled2.set_child(clamp)
        scrolled2.set_vexpand(True)
        toolbar.set_content(scrolled2)
        self.set_child(toolbar)

        self._all_results: list[str] = []
        self._page = 0

    def _do_search(self) -> None:
        query = self._search_entry.get_text().strip()
        if not query:
            return
        self._results_label.set_label(f"Searching for {query}\u2026")
        while child := self._result_list.get_first_child():
            self._result_list.remove(child)
        try:
            result = subprocess.run(
                ["bash", _FONT_CORE, "--search-remote", query],
                capture_output=True, text=True, timeout=30,
                stdin=subprocess.DEVNULL,
            )
            self._all_results = [l for l in result.stdout.strip().splitlines()
                                 if l.strip() and "(Installed)" not in l
                                 and "out-of-date" not in l.lower()
                                 and "Orphan" not in l]
            if not self._all_results:
                self._results_label.set_label("No results found")
                self._prev_btn.set_sensitive(False)
                self._next_btn.set_sensitive(False)
                self._page_label.set_label("")
                return
            self._results_label.set_label(f"{len(self._all_results)} results for \u201c{query}\u201d (installed filtered out)")
            self._show_page(0)
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as e:
            self._results_label.set_label(f"Search failed \u2014 {e}")

    _PER_PAGE = 10

    def _show_page(self, page: int) -> None:
        total = len(self._all_results)
        pages = max(1, (total + self._PER_PAGE - 1) // self._PER_PAGE)
        self._page = max(0, min(page, pages - 1))
        start = self._page * self._PER_PAGE
        end = min(start + self._PER_PAGE, total)

        while child := self._result_list.get_first_child():
            self._result_list.remove(child)

        for line in self._all_results[start:end]:
            line = line.strip()
            if not line:
                continue
            pkg = line.split()[0] if line.split() else ""
            if not pkg:
                continue
            desc = line[len(pkg):].strip()
            row = Adw.ActionRow(title=pkg, subtitle=desc[:60])

            is_ood = "out-of-date" in line.lower() or "Out of Date" in line
            btn_label = "Install (OOD)" if is_ood else "Install"
            install_btn = Gtk.Button(label=btn_label)
            install_btn.set_valign(Gtk.Align.CENTER)
            if is_ood:
                install_btn.add_css_class("destructive-action")
            else:
                install_btn.add_css_class("suggested-action")
            install_btn.connect("clicked", lambda _b, p=pkg: self._install(p))
            row.add_suffix(install_btn)
            self._result_list.append(row)

        self._page_label.set_label(f"Page {self._page + 1} of {pages}")
        self._prev_btn.set_sensitive(self._page > 0)
        self._next_btn.set_sensitive(self._page < pages - 1)

    def _install(self, pkg: str) -> None:
        from lib.python.variable import get_var as _g
        helper = _g("PKG_HELPER") or "yay"
        self.close()
        cmd = f"kitty -- bash -c '{helper} -S --needed --noconfirm {pkg}; echo; echo Press Enter to close.; read'"
        lua = f'hl.dsp.exec_cmd("{cmd}", {{ float = true, size = {{ 800, 500 }}, center = true }})'
        subprocess.Popen(
            ["hyprctl", "dispatch", lua],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
