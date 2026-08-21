"""Keybind management page — categorized list with override support."""

import copy
import os
import re
from collections.abc import Iterator
from html import escape as html_escape

from gi.repository import Adw, GLib, Gtk
from hyprland_config import BindData, parse_bind_line
from hyprland_socket import HyprlandError, eval_lua

from settings.binds import (
    CATEGORY_BY_ID,
    DISPATCHER_CATEGORIES,
    OverrideTracker,
    categorize_bind,
    enrich_lua_binds,
    format_bind_action,
    live_bind_to_data,
)
from settings.binds.dialog import BindEditDialog
from settings.core import config
from settings.core.ownership import SavedList
from settings.core.pending import PendingChange
from settings.core.undo import BindsUndoEntry
from settings.pages.section import SectionPage
from settings.ui import clear_children, make_inline_hint, make_page_layout, try_with_toast
from settings.ui.empty_state import EmptyState
from settings.ui.icons import BINDS_ICON
from settings.ui.row_actions import RowActions


def update_binds_sidebar(window) -> None:
    """Update the Keybinds sidebar row with managed bind count."""
    try:
        sidebar = getattr(window, "_sidebar", None)
        if sidebar is None:
            return
        row = sidebar._rows_by_id.get("binds")
        if row is None:
            return
        if not hasattr(row, "_binds_sidebar_label"):
            lbl = Gtk.Label()
            lbl.set_valign(Gtk.Align.CENTER)
            lbl.add_css_class("badge")
            row.add_suffix(lbl)
            row._binds_sidebar_label = lbl
        kb = config.keybinds_path()
        count = 0
        if kb.exists():
            sections = config.read_all_sections(kb)[1]
            count += len(config.collect_bind_section(sections))
            count += len(re.findall(r'hl\.bind\(', kb.read_text(), re.MULTILINE))
        row._binds_sidebar_label.set_visible(count > 0)
        if count:
            row._binds_sidebar_label.set_label(str(count))
    except Exception:
        pass


class BindsPage(SectionPage):
    """Builds the keybinds management page with categorized layout."""

    def __init__(self, window, on_dirty_changed=None, push_undo=None, saved_sections=None):
        super().__init__(window, on_dirty_changed, push_undo)
        self._hypr_binds: list[BindData] = []
        self._search_term: str = ""
        self._group_widgets: dict[str, Adw.PreferencesGroup] = {}
        self._row_widgets: list[tuple[Adw.ActionRow, BindData, bool]] = []
        self._content_box: Gtk.Box
        self._scrolled: Gtk.ScrolledWindow
        self._search_entry: Gtk.SearchEntry
        self._search_bar: Gtk.SearchBar
        self._search_btn: Gtk.ToggleButton
        self._overrides: OverrideTracker
        self._owned_binds: SavedList[BindData]
        self._module_retro_binds: dict[tuple, BindData] = {}
        self._load_binds(saved_sections)

    def _apply_bind_live(self, bind: BindData) -> bool:
        """Register a bind in the running Hyprland instance.

        ``bindm`` rejects a trailing comma (``bind: too many args``) so the
        argument is only appended when present. Other bind variants tolerate
        either form.

        In Lua mode, Retro Lua function dispatchers are emitted directly as
        ``hl.bind("KEY", Retro.fn)`` via ``eval_lua`` — the legacy keyword
        IPC can't handle custom Lua dispatchers. In legacy mode the
        dispatcher is converted to its standard equivalent first.
        """
        disp = bind.dispatcher
        arg = bind.arg

        if disp in config.RETRO_DISPATCHER_MAP and self._window.hypr.is_live_lua_mode():
            combo = bind.format_shortcut()
            fn = config.RETRO_DISPATCHER_MAP[disp]
            return try_with_toast(
                self._window.show_bug_toast,
                "Bind failed",
                lambda: eval_lua(f'local Retro = require("lib.retro"); hl.bind("{combo}", {fn})'),
                catch=HyprlandError,
            )

        std = config.RETRO_STANDARD_MAP.get(disp)
        if std:
            disp, arg = std
        value = f"{bind.mods_str}, {bind.key}, {disp}"
        if arg:
            value += f", {arg}"
        return try_with_toast(
            self._window.show_bug_toast,
            "Bind failed",
            lambda: self._window.hypr.keyword(bind.bind_type, value),
            catch=HyprlandError,
        )

    def _revert_bind_live(self, bind: BindData) -> bool:
        """Remove a bind from the running Hyprland instance."""
        if self._window.hypr.is_live_lua_mode():
            return try_with_toast(
                self._window.show_bug_toast,
                "Unbind failed",
                lambda: eval_lua(f'hl.unbind("{bind.format_shortcut()}")'),
                catch=HyprlandError,
            )
        return try_with_toast(
            self._window.show_bug_toast,
            "Unbind failed",
            lambda: self._window.hypr.keyword(
                config.KEYWORD_UNBIND, f"{bind.mods_str}, {bind.key}"
            ),
            catch=HyprlandError,
        )

    def _pre_enrich_retro_binds(self) -> dict:
        """Pre-scan known Retro source files for ``hl.bind(..., Retro.fn)``.

        The hyprland-config Lua reader silently drops ``hl.bind(..., Retro.fn)``
        calls, so the document has no keywords for these binds and the standard
        :func:`enrich_lua_binds` pipeline can't resolve them.  Instead, read the
        source files directly and match by **combo** (not line number), handling
        both string literal combos (``"SUPER + K"``) and Lua expression combos
        (``mainMod .. " + K"``) with known variable substitution.

        Returns a ``{combo: dispatcher_name}`` mapping to apply to live binds
        before the normal enrichment pass.
        """
        retro_map: dict = {}
        _LITERAL_RETRO = re.compile(r'hl\.bind\("([^"]+)",\s*(Retro\.\w+)(?:\s*,\s*\{[^}]*\})?\)')
        _EXPR_RETRO = re.compile(
            r'hl\.bind\((\w+)\s*\.\.\s*"([^"]+)"\s*,\s*(Retro\.\w+)(?:\s*,\s*\{[^}]*\})?\)'
        )
        # Variable → modifier translation from the module's keybinds.lua.
        _KNOWN_MOD_VARS: dict[str, str] = {"mainMod": "SUPER"}

        retro_dir = os.environ.get("RETRO_DIR", "/opt/retrolinux")
        sources: list[str] = [
            os.path.join(retro_dir, "modules", "hyprland", "files", "keybinds.lua"),
        ]
        kb_override = config.keybinds_path()
        if kb_override.exists():
            sources.append(str(kb_override))

        for source in sources:
            if not os.path.exists(source):
                continue
            try:
                with open(source) as _f:
                    _content = _f.read()
            except OSError:
                continue

            for _m in _LITERAL_RETRO.finditer(_content):
                _combo_str, _fn_name = _m.groups()
                _parts = _combo_str.split(" + ")
                _key = _parts[-1]
                _mods = tuple(_m.upper() for _m in _parts[:-1])
                _combo = (_mods, _key.upper())
                _disp = config.RETRO_FN_MAP.get(_fn_name)
                if _disp:
                    retro_map[_combo] = _disp

            for _m in _EXPR_RETRO.finditer(_content):
                _var_name, _suffix, _fn_name = _m.groups()
                _mod_str = _KNOWN_MOD_VARS.get(_var_name)
                if _mod_str:
                    _combo_parts = [p.strip().upper() for p in _suffix.strip().split("+")]
                    _key = _combo_parts[-1] if _combo_parts else ""
                    _extra_mods = _combo_parts[:-1]
                    _mods = list(_mod_str.split(" + "))
                    for _em in _extra_mods:
                        if _em and _em not in _mods:
                            _mods.append(_em)
                    _combo = (tuple(_mods), _key)
                    _disp = config.RETRO_FN_MAP.get(_fn_name)
                    if _disp:
                        retro_map[_combo] = _disp

        return retro_map

    def _load_retro_binds(self):
        """Parse Retro function binds from the module keybinds.lua file.

        Stores parsed binds in ``_module_retro_binds`` (combo → BindData).
        These serve as the fallback / "locked" entries shown in the Retro
        Actions category when no override exists.
        """
        self._module_retro_binds.clear()
        _LITERAL_RETRO = re.compile(r'hl\.bind\("([^"]+)",\s*(Retro\.\w+)(?:\s*,\s*\{[^}]*\})?\)')
        _EXPR_RETRO = re.compile(
            r'hl\.bind\((\w+)\s*\.\.\s*"([^"]+)"\s*,\s*(Retro\.\w+)(?:\s*,\s*\{[^}]*\})?\)'
        )
        _KNOWN_MOD_VARS: dict[str, str] = {"mainMod": "SUPER"}

        retro_dir = os.environ.get("RETRO_DIR", "/opt/retrolinux")
        source = os.path.join(retro_dir, "modules", "hyprland", "files", "keybinds.lua")
        if not os.path.exists(source):
            return
        try:
            with open(source) as _f:
                _content = _f.read()
        except OSError:
            return

        for _m in _LITERAL_RETRO.finditer(_content):
            _combo_str, _fn_name = _m.groups()
            _parts = _combo_str.split(" + ")
            _key = _parts[-1]
            _mods = [m.upper() for m in _parts[:-1]]
            _disp = config.RETRO_FN_MAP.get(_fn_name)
            if _disp:
                _bd = BindData(
                    bind_type="bind",
                    mods=_mods,
                    key=_key.upper(),
                    dispatcher=_disp,
                    arg="",
                )
                self._module_retro_binds[_bd.combo] = _bd

        for _m in _EXPR_RETRO.finditer(_content):
            _var_name, _suffix, _fn_name = _m.groups()
            _mod_str = _KNOWN_MOD_VARS.get(_var_name)
            if _mod_str:
                _combo_parts = [p.strip().upper() for p in _suffix.strip().split("+")]
                _key = _combo_parts[-1] if _combo_parts else ""
                _extra_mods = _combo_parts[:-1]
                _mods = [m.upper() for m in _mod_str.split(" + ")]
                for _em in _extra_mods:
                    if _em and _em not in _mods:
                        _mods.append(_em)
                _disp = config.RETRO_FN_MAP.get(_fn_name)
                if _disp:
                    _bd = BindData(
                        bind_type="bind",
                        mods=_mods,
                        key=_key.upper(),
                        dispatcher=_disp,
                        arg="",
                    )
                    self._module_retro_binds[_bd.combo] = _bd

    def _load_binds(self, saved_sections=None):
        live_binds = self._window.hypr.get_binds() or []
        all_hypr_binds = [live_bind_to_data(b) for b in live_binds]

        # Pre-enrich: combo-based Retro function scan before the standard
        # line-number-based enrichment (which can't resolve Retro.* closures).
        retro_map = self._pre_enrich_retro_binds()
        for i, b in enumerate(all_hypr_binds):
            if b.dispatcher == "__lua" and b.combo in retro_map:
                all_hypr_binds[i] = BindData(
                    bind_type=b.bind_type,
                    mods=list(b.mods),
                    key=b.key,
                    dispatcher=retro_map[b.combo],
                    arg="",
                )

        # Lua-mode IPC labels every bind ``__lua: <line>``; swap in real
        # dispatcher info from the parsed source so categorisation and
        # row labels match what the user actually configured.
        all_hypr_binds = enrich_lua_binds(all_hypr_binds, self._window.hypr.document)

        sections = saved_sections if saved_sections is not None else self._window.saved_sections
        bind_lines = config.collect_bind_section(sections)
        parsed_binds: list[BindData] = []
        for line in bind_lines:
            parsed = parse_bind_line(line)
            if parsed:
                parsed_binds.append(parsed)
        existing_combos = {b.combo for b in parsed_binds}

        # Also load CLI-added keybinds from keybinds.lua
        try:
            kb_path = config.keybinds_path()
            if kb_path.exists():
                _, kb_sections, _ = config.read_all_sections(kb_path)
                for line in config.collect_bind_section(kb_sections):
                    parsed = parse_bind_line(line)
                    if parsed and parsed.combo not in existing_combos:
                        parsed_binds.append(parsed)
                        existing_combos.add(parsed.combo)
        except Exception:
            pass

        # Load binds from keybinds.lua (the library's Lua reader can't parse
        # ``hl.bind("KEY", Retro.fn)`` or ``hl.dsp.exec_cmd("cmd")``, so we
        # scan the raw file for any ``hl.bind("KEY", ...)`` call).
        try:
            kb_path = config.keybinds_path()
            if kb_path.exists():
                _bind_re = re.compile(r'hl\.bind\("([^"]+)",\s*(.+)\)')
                with open(kb_path) as _f:
                    for _line in _f:
                        _m = _bind_re.search(_line)
                        if _m:
                            _combo_str, _fn = _m.groups()
                            _parts = _combo_str.split(" + ")
                            _key = _parts[-1]
                            _mods = [m.upper() for m in _parts[:-1]]
                            _fn_stripped = _fn.strip()
                            _disp = config.RETRO_FN_MAP.get(_fn_stripped)
                            _arg = ""
                            if _disp is None:
                                _exec = re.match(
                                    r'hl\.dsp\.exec_cmd\(?"?([^")]+)"?\)',
                                    _fn_stripped,
                                )
                                if _exec:
                                    _disp = "exec"
                                    _arg = _exec.group(1)
                                else:
                                    _disp = "__lua__"
                            _bd = BindData(
                                bind_type="bind",
                                mods=_mods,
                                key=_key,
                                dispatcher=_disp,
                                arg=_arg,
                            )
                            if _bd.combo not in existing_combos:
                                parsed_binds.append(_bd)
                                existing_combos.add(_bd.combo)
        except Exception:
            pass

        self._load_retro_binds()
        self._overrides = OverrideTracker(
            all_hypr_binds,
            managed_path=config.keybinds_path(),
            document=self._window.hypr.document,
        )
        self._overrides.parse_saved_overrides(
            parsed_binds,
            module_retro=self._module_retro_binds,
        )
        self._owned_binds = SavedList(parsed_binds, key=lambda b: b.to_line())

    # -- Undo / Redo --

    def _binds_key(self) -> list[str]:
        """Serialized representation of current binds state for comparison."""
        return [b.to_line() for b in self._owned_binds]

    def _capture_undo(self):
        """Snapshot binds + override state for undo."""
        return self._owned_binds.snapshot(), self._overrides.snapshot_session()

    def _undo_key(self):
        return self._binds_key()

    def _build_undo_entry(self, old, new):
        (old_items, old_baselines), old_overrides = old
        (new_items, new_baselines), new_overrides = new
        return BindsUndoEntry(
            old_items=old_items,
            new_items=new_items,
            old_baselines=old_baselines,
            new_baselines=new_baselines,
            old_session_overrides=old_overrides,
            new_session_overrides=new_overrides,
        )

    def restore_snapshot(self, items, baselines, session_overrides):
        """Restore binds state from an undo/redo snapshot.

        Each ``_apply_bind_live`` / ``_revert_bind_live`` call already
        toasts on failure via ``try_with_toast``, so we deliberately
        ignore their boolean returns: a single undo can touch dozens of
        binds and a per-bind toast cascade would drown the user. The
        first failure is signal enough — subsequent ones almost always
        share a root cause.
        """
        # Undo live: unbind all current owned, restore overridden originals
        for b in self._owned_binds:
            self._revert_bind_live(b)
        for orig in self._overrides.snapshot_session().values():
            self._apply_bind_live(orig)

        # Restore internal state
        self._owned_binds.restore(items, baselines)
        self._overrides.restore_session(session_overrides)

        # Redo live: unbind restored override originals, bind all restored
        for orig in session_overrides.values():
            self._revert_bind_live(orig)
        for b in items:
            self._apply_bind_live(b)

        self._rebuild_list()
        self._notify_dirty()

    def build(self, header: Adw.HeaderBar | None = None) -> Adw.ToolbarView:
        page_header = header or Adw.HeaderBar()

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh keybinds from Hyprland")
        refresh_btn.connect("clicked", lambda _: self.reload_from_live())
        page_header.pack_start(refresh_btn)

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_tooltip_text("Add keybind")
        add_btn.connect("clicked", self._on_add)
        page_header.pack_start(add_btn)

        self._search_btn = Gtk.ToggleButton(icon_name="system-search-symbolic")
        self._search_btn.set_tooltip_text("Search keybinds")
        self._search_btn.connect("toggled", self._on_search_toggled)
        page_header.pack_end(self._search_btn)

        toolbar_view, page_box, self._content_box, self._scrolled = make_page_layout(
            header=page_header
        )

        self._search_entry = Gtk.SearchEntry()
        self._search_entry.set_placeholder_text("Filter keybinds\u2026")
        self._search_entry.connect("search-changed", self._on_search_changed)
        self._search_bar = Gtk.SearchBar()
        self._search_bar.set_child(self._search_entry)
        self._search_bar.connect_entry(self._search_entry)
        page_box.prepend(self._search_bar)

        self._rebuild_list()

        return toolbar_view

    # -- List building --

    def _refilter_hypr_binds(self):
        self._hypr_binds = self._overrides.filter_hypr_binds(self._owned_binds)  # type: ignore[arg-type]

    def _rebuild_list(self):
        self._refilter_hypr_binds()
        has_hypr_binds = bool(self._hypr_binds)

        vadj = self._scrolled.get_vadjustment()
        scroll_pos = vadj.get_value() if vadj else 0

        clear_children(self._content_box)

        self._group_widgets.clear()
        self._row_widgets.clear()

        categories: dict[str, list[tuple[BindData, bool, int]]] = {}
        for cat in DISPATCHER_CATEGORIES:
            categories[cat["id"]] = []

        for i, bind in enumerate(self._owned_binds):
            cat_id = categorize_bind(bind.bind_type, bind.dispatcher)
            if cat_id not in categories:
                cat_id = "advanced"
            categories[cat_id].append((bind, True, i))

        owned_combos = {b.combo for b in self._owned_binds}
        for bind in self._hypr_binds:
            if bind.combo in owned_combos:
                continue
            # Retro defaults are rendered from _module_retro_binds, not here.
            if bind.combo in self._module_retro_binds:
                continue
            cat_id = categorize_bind(bind.bind_type, bind.dispatcher)
            if cat_id not in categories:
                cat_id = "advanced"
            categories[cat_id].append((bind, False, -1))

        # Retro category: use module file defaults for non-overridden binds.
        # Skip combos that are the original of a changed-combo override,
        # and also skip combos that the override file explicitly unbinds.
        originals = {orig.combo for orig in self._overrides._session_overrides.values()}
        originals.update(orig.combo for orig in self._overrides._saved_overrides.values())
        unbound_combos: set[tuple] = set()
        try:
            _kb = config.keybinds_path()
            if _kb.exists():
                _raw = _kb.read_text()
                # Hyprlang unbind format
                for _m in re.finditer(r'unbind\s*=\s*([^,]+),\s*(.+)', _raw):
                    _mods = tuple(sorted(m.upper() for m in _m.group(1).split() if m.strip()))
                    _key = _m.group(2).strip().upper()
                    unbound_combos.add((_mods, _key))
                # Lua hl.unbind format
                for _m in re.finditer(r'hl\.unbind\("([^"]+)"\)', _raw):
                    _parts = _m.group(1).split(" + ")
                    _key = _parts[-1].upper()
                    _mods = tuple(sorted(m.upper() for m in _parts[:-1]))
                    unbound_combos.add((_mods, _key))
        except Exception:
            pass
        for combo, bind in self._module_retro_binds.items():
            if combo not in owned_combos and combo not in originals and combo not in unbound_combos:
                categories.setdefault("retro", []).append((bind, False, -1))

        # Info note for locked binds
        if has_hypr_binds:
            self._content_box.append(
                make_inline_hint(
                    "Locked keybinds come from your hyprland.conf. "
                    "Click the edit button to override them."
                )
            )

        for cat in DISPATCHER_CATEGORIES:
            binds_in_cat = categories.get(cat["id"], [])
            if not binds_in_cat:
                continue

            group = Adw.PreferencesGroup(title=cat["label"])
            group.set_description(
                f"{len(binds_in_cat)} keybind{'s' if len(binds_in_cat) != 1 else ''}"
            )

            add_btn = Gtk.Button(icon_name="list-add-symbolic")
            add_btn.set_valign(Gtk.Align.CENTER)
            add_btn.add_css_class("flat")
            add_btn.set_tooltip_text(f"Add keybind to {cat['label']}")
            add_btn.connect("clicked", lambda _btn, cid=cat["id"]: self._on_add(category=cid))
            group.set_header_suffix(add_btn)

            for bind, editable, index in binds_in_cat:
                row = self._make_bind_row(bind, editable=editable, index=index, icon=cat["icon"])
                group.add(row)
                self._row_widgets.append((row, bind, editable))

            self._group_widgets[cat["id"]] = group
            self._content_box.append(group)

        if not self._row_widgets:
            self._content_box.append(
                EmptyState(
                    title="No Keybinds",
                    description=(
                        "Bind keys to launch apps, switch workspaces, or trigger "
                        "any Hyprland dispatcher."
                    ),
                    icon_name=BINDS_ICON,
                    primary_action=("Add Keybind…", self._on_add),
                )
            )

        if vadj and scroll_pos > 0:
            GLib.idle_add(lambda: vadj.set_value(scroll_pos) or False)

        self._apply_filter()

    def _make_bind_row(
        self, bind: BindData, editable: bool, index: int = -1, icon: str = ""
    ) -> Adw.ActionRow:
        shortcut = bind.format_shortcut()
        action_str = format_bind_action(bind.bind_type, bind.dispatcher, bind.arg)

        row = Adw.ActionRow(
            title=html_escape(shortcut),
            subtitle=html_escape(action_str),
        )

        if icon:
            prefix_icon = Gtk.Image.new_from_icon_name(icon)
            prefix_icon.set_opacity(0.6)
            row.add_prefix(prefix_icon)

        if not editable:
            row.add_css_class("option-default")
            row.set_activatable(True)
            row.connect("activated", lambda _row, b=bind: self._on_override(b))

            edit_btn = Gtk.Button(icon_name="document-edit-symbolic")
            edit_btn.set_valign(Gtk.Align.CENTER)
            edit_btn.add_css_class("flat")
            edit_btn.set_tooltip_text("Edit this keybind")
            edit_btn.connect("clicked", lambda _btn, b=bind: self._on_override(b))
            row.add_suffix(edit_btn)
        else:
            row.set_activatable(True)
            row.connect("activated", lambda _row, idx=index: self._on_edit_at(idx))

            is_dirty = self._owned_binds.is_item_dirty(index)
            is_saved = self._owned_binds.get_baseline(index) is not None

            actions = RowActions(
                row,
                on_discard=lambda idx=index: self._discard_bind_at(idx),
                on_reset=lambda idx=index: self._on_delete_at(idx),
            )
            row.add_suffix(actions.box)

            actions.update(
                is_managed=True,
                is_dirty=is_dirty,
                is_saved=is_saved,
            )

            row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))

        return row

    # -- Search --

    def _on_search_toggled(self, btn):
        self._search_bar.set_search_mode(btn.get_active())
        if btn.get_active():
            self._search_entry.grab_focus()
        else:
            self._search_entry.set_text("")

    def _on_search_changed(self, entry):
        self._search_term = entry.get_text().strip().lower()
        self._apply_filter()

    def _apply_filter(self):
        term = self._search_term
        for cat_id, group in self._group_widgets.items():
            visible_count = 0
            for row, bind, _editable in self._row_widgets:
                if row.get_parent() is None:
                    continue
                row_cat = categorize_bind(bind.bind_type, bind.dispatcher)
                if row_cat != cat_id:
                    continue
                if not term:
                    row.set_visible(True)
                    visible_count += 1
                else:
                    shortcut = bind.format_shortcut().lower()
                    action = format_bind_action(bind.bind_type, bind.dispatcher, bind.arg).lower()
                    cat_label = CATEGORY_BY_ID.get(cat_id, {}).get("label", "").lower()
                    if term in shortcut or term in action or term in cat_label:
                        row.set_visible(True)
                        visible_count += 1
                    else:
                        row.set_visible(False)
            group.set_visible(visible_count > 0)

    # -- Duplicate detection --

    def _find_conflicts(self, bind: BindData, exclude_idx: int = -1) -> list[BindData]:
        target = bind.combo
        conflicts = []
        for i, b in enumerate(self._owned_binds):
            if i == exclude_idx:
                continue
            if b.combo == target:
                conflicts.append(b)
        for b in self._hypr_binds:
            if b.combo == target:
                conflicts.append(b)
        return conflicts

    # -- Add / Edit / Delete --

    def _on_add(self, _button=None, category: str = ""):
        owned_binds = self._owned_binds

        def on_apply(bind):
            with self._undo_track():
                self._apply_bind_live(bind)
                owned_binds.append_new(bind)
            self._notify_dirty()
            self._rebuild_list()

        dialog = BindEditDialog(
            window=self._window,
            initial_category=category,
            on_apply=on_apply,
            conflict_finder=lambda candidate: self._find_conflicts(candidate),
        )
        dialog.present(self._window)

    def _on_edit_at(self, idx):
        owned_binds = self._owned_binds
        if idx < 0 or idx >= len(owned_binds):
            return
        bind = owned_binds[idx]

        def on_apply(new_bind):
            with self._undo_track():
                self._revert_bind_live(bind)
                self._apply_bind_live(new_bind)
                owned_binds[idx] = new_bind
            self._notify_dirty()
            self._rebuild_list()

        dialog = BindEditDialog(
            bind=bind,
            window=self._window,
            on_apply=on_apply,
            conflict_finder=lambda candidate: self._find_conflicts(candidate, exclude_idx=idx),
        )
        dialog.present(self._window)

    def _on_override(self, hypr_bind):
        owned_binds = self._owned_binds
        overrides = self._overrides
        owned = copy.deepcopy(hypr_bind)
        hypr_c = hypr_bind.combo

        def on_apply(new_bind):
            with self._undo_track():
                self._revert_bind_live(hypr_bind)
                self._apply_bind_live(new_bind)
                owned_binds.append_new(new_bind)
                idx = len(owned_binds) - 1
                overrides.add_override(idx, hypr_bind)
            self._notify_dirty()
            self._rebuild_list()

        dialog = BindEditDialog(
            bind=owned,
            window=self._window,
            on_apply=on_apply,
            conflict_finder=lambda candidate: [
                c for c in self._find_conflicts(candidate) if c.combo != hypr_c
            ],
        )
        dialog.present(self._window)

    def _on_delete_at(self, idx):
        if idx < 0 or idx >= len(self._owned_binds):
            return
        with self._undo_track():
            removed = self._owned_binds.pop_at(idx)
            self._revert_bind_live(removed)
            original = self._overrides.remove_at(idx)
            # Always purge the removed override combo so it doesn't
            # leak back from _hypr_binds after the owned bind is gone.
            hypr = self._overrides._hypr_binds
            hypr_by = self._overrides._hypr_by_combo
            hypr[:] = [b for b in hypr if b.combo != removed.combo]
            hypr_by.pop(removed.combo, None)
            if original:
                self._apply_bind_live(original)
                if not any(b.combo == original.combo for b in hypr):
                    hypr.append(original)
                hypr_by[original.combo] = original
        self._notify_dirty()
        self._rebuild_list()

    # -- Dirty state --

    def _discard_bind_at(self, idx: int):
        """Revert a single bind to its saved state."""
        baseline = self._owned_binds.get_baseline(idx)
        if baseline is None:
            # New bind — discard means delete
            self._on_delete_at(idx)
            return
        # Revert to saved version — _undo_track handles pop-or-push
        with self._undo_track():
            current = self._owned_binds[idx]
            self._revert_bind_live(current)
            self._apply_bind_live(baseline)
            self._owned_binds.discard_at(idx)
        self._notify_dirty()
        self._rebuild_list()

    def is_dirty(self) -> bool:
        return self._owned_binds.is_dirty()

    def mark_saved(self):
        self._owned_binds.mark_saved()
        self._overrides.mark_saved(self._owned_binds, module_retro=self._module_retro_binds)  # type: ignore[arg-type]
        self._rebuild_list()

    def reload_from_live(self):
        """Re-read binds from Hyprland and reset baselines.

        Used after profile activation to sync with the new live state.
        """
        self._load_binds()
        self._rebuild_list()

    def discard(self):
        saved_lines = self._owned_binds.saved_set
        current_lines = {b.to_line() for b in self._owned_binds}

        for b in self._owned_binds:
            if b.to_line() not in saved_lines:
                self._revert_bind_live(b)
        for b in self._owned_binds.saved:
            if b.to_line() not in current_lines:
                self._apply_bind_live(b)

        self._owned_binds.discard_all()

        for original in self._overrides.clear_session_overrides():
            self._apply_bind_live(original)

        self._rebuild_list()

    def get_bind_lines(self) -> list[str]:
        return self._overrides.get_bind_lines(self._owned_binds)  # type: ignore[arg-type]

    # ── Pending changes ──

    def iter_pending_changes(self) -> Iterator[PendingChange]:
        if not self.is_dirty():
            return
        current_lines: set[str] = set()
        for idx, bind in enumerate(self._owned_binds):
            current_lines.add(bind.to_line())
            baseline = self._owned_binds.get_baseline(idx)
            if baseline is None:
                shortcut = bind.format_shortcut() or "(no shortcut)"
                yield PendingChange(
                    category="Keybinds",
                    title=shortcut,
                    subtitle=f"new · {bind.format_action()}",
                    kind="added",
                    revert=lambda i=idx: self._discard_bind_at(i),
                    navigate_to="binds",
                    icon=BINDS_ICON,
                )
                continue
            if not self._owned_binds.is_item_dirty(idx):
                continue
            old_shortcut = baseline.format_shortcut() or "(none)"
            new_shortcut = bind.format_shortcut() or "(none)"
            if old_shortcut == new_shortcut:
                subtitle = f"{baseline.format_action()} → {bind.format_action()}"
            else:
                subtitle = f"{old_shortcut} → {new_shortcut}"
            yield PendingChange(
                category="Keybinds",
                title=new_shortcut,
                subtitle=subtitle,
                kind="modified",
                revert=lambda i=idx: self._discard_bind_at(i),
                navigate_to="binds",
                icon=BINDS_ICON,
            )
        for saved_bind in self._owned_binds.saved:
            if saved_bind.to_line() not in current_lines:
                shortcut = saved_bind.format_shortcut() or "(none)"
                yield PendingChange(
                    category="Keybinds",
                    title=shortcut,
                    subtitle=f"deleted · {saved_bind.format_action()}",
                    kind="removed",
                    revert=lambda b=saved_bind: self._restore_deleted(b),
                    navigate_to="binds",
                    icon=BINDS_ICON,
                )

    def _restore_deleted(self, bind: BindData) -> None:
        """Re-insert a previously-deleted saved bind at its saved position.

        Pushes a single undo entry, replays the bind to the running
        compositor, and repaints the list — a pure delete-then-restore
        round trip leaves the page non-dirty.
        """
        with self._undo_track():
            self._apply_bind_live(bind)
            self._owned_binds.restore_deleted(bind)
        self._notify_dirty()
        self._rebuild_list()
