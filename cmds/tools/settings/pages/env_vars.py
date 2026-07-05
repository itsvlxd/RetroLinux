"""Environment Variables page — manage ``env = NAME,value`` entries.

Hyprland's ``env`` keyword exports environment variables to processes
the compositor spawns (``exec``/``exec-once`` children, dispatcher
``exec`` calls, terminal launches). Lines look like
``env = QT_QPA_PLATFORM,wayland``; the first comma separates name
from value, further commas inside the value are preserved.

Like autostart, env edits are **not** live-applied — Hyprland reads
``env`` lines once at compositor startup and there's no IPC path to
retroactively patch the environment of already-running processes.
Edits land in settings's managed config and take effect on the next
Hyprland session.

External entries (env vars defined in the user's ``hyprland.conf``
or any file it sources) are surfaced read-only at the bottom of the
page with an "override" button — same UX as locked keybinds. Clicking
the button opens the edit dialog pre-filled with the external var's
name and value; on apply, a new managed entry is added. Hyprland
sources files in order with last-write-wins semantics, and Retro Settings's
first-run setup ensures our file is sourced after ``hyprland.conf``,
so a managed override always wins.

The cursor theme/size variables (``XCURSOR_THEME``, ``XCURSOR_SIZE``,
``HYPRCURSOR_THEME``, ``HYPRCURSOR_SIZE``) are owned by the Cursor
page — they're transparently filtered out of this page on read (both
managed and external), so there's only one place to edit each
variable. On save, both pages emit env lines independently and the
window concatenates them (cursor first, by convention).

Reusable dialog lives in ``settings.ui``:

- ``ui.env_var_edit_dialog.EnvVarEditDialog`` for add/edit/override.
"""

from html import escape as html_escape

from gi.repository import Adw, Gtk

from settings.core import config
from settings.core.env_vars import (
    RESERVED_NAMES,
    ENV_LUA_PATH,
    EnvVar,
    ExternalEnvVar,
    load_external_env_vars,
    overridden_external_names,
    parse_env_lua_file,
    serialize_env_lua,
)
from settings.core.ownership import SavedList
from settings.pages.section import SavedListSectionPage
from settings.ui import make_inline_hint, make_page_layout
from settings.ui.empty_state import EmptyState
from settings.ui.env_var_edit_dialog import EnvVarEditDialog
from settings.ui.icons import ENV_VARS_ICON
from settings.ui.row_actions import RowActions


def update_env_vars_sidebar(window) -> None:
    """Update the Env Variables sidebar row with managed entry count."""
    try:
        sidebar = getattr(window, "_sidebar", None)
        if sidebar is None:
            return
        row = sidebar._rows_by_id.get("env_vars")
        if row is None:
            return
        if not hasattr(row, "_ev_sidebar_label"):
            lbl = Gtk.Label()
            lbl.set_valign(Gtk.Align.CENTER)
            lbl.add_css_class("badge")
            row.add_suffix(lbl)
            row._ev_sidebar_label = lbl
        from settings.core.env_vars import ENV_LUA_PATH, RESERVED_NAMES, parse_env_lua_file
        count = len([e for e in parse_env_lua_file(ENV_LUA_PATH) if e.name not in RESERVED_NAMES])
        row._ev_sidebar_label.set_visible(count > 0)
        if count:
            row._ev_sidebar_label.set_label(str(count))
    except Exception:
        pass


# ---------------------------------------------------------------------------
# EnvVarsPage
# ---------------------------------------------------------------------------


class EnvVarsPage(SavedListSectionPage[EnvVar]):
    """List editor for ``env = NAME,value`` config entries."""

    _unit_singular = "variable"
    _unit_plural = "variables"
    _page_attr = "_env_vars_page"
    _pending_category = "Env Variables"
    _pending_navigate_to = "env_vars"
    _pending_icon = ENV_VARS_ICON
    _group_title = "Variables"
    _group_add_tooltip = "Add another variable"

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
        self._owned: SavedList[EnvVar]
        # Snapshot of which external names are shadowed by an owned
        # entry; refreshed at the top of ``_rebuild_list`` so the
        # base-class external-row renderer can read a stable value
        # without recomputing per row.
        self._overridden_external: set[str] = set()
        self._load(saved_sections)

    # ── Loading ──

    def _load(self, saved_sections: dict[str, list[str]] | None) -> None:
        del saved_sections
        items = parse_env_lua_file(ENV_LUA_PATH)
        items = [item for item in items if item.name not in RESERVED_NAMES]
        managed_names = {e.name for e in items}

        # External entries from other sourced files (modules/hyprland/files/env.lua, etc.)
        retro_root = config.RETRO_SETTINGS_DIR.resolve()
        self._external = []
        for ext in load_external_env_vars(config.user_entry_path(), config.managed_path()):
            try:
                src = ext.source_path.resolve()
            except OSError:
                src = ext.source_path
            if retro_root in src.parents or src == retro_root:
                if ext.var.name not in managed_names:
                    items.append(ext.var)
                    managed_names.add(ext.var.name)
            else:
                self._external.append(ext)

        self._saved_items = list(items)
        self._owned = SavedList(items, key=lambda e: e.to_line())

    # ── Build ──

    def build(self, header: Adw.HeaderBar | None = None) -> Adw.ToolbarView:
        page_header = header or Adw.HeaderBar()

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_tooltip_text("Add environment variable")
        add_btn.connect("clicked", lambda _b: self._on_add())
        page_header.pack_start(add_btn)

        toolbar_view, _, self._content_box, self._scrolled = make_page_layout(header=page_header)

        self._rebuild_list()
        return toolbar_view

    # ── List rendering ──

    def _pre_rebuild(self) -> None:
        # Snapshot once per rebuild so the external-row renderer can look
        # up "is this entry shadowed by an owned line?" without threading
        # the set through method signatures.
        self._overridden_external = overridden_external_names(self._external, list(self._owned))

    def _build_order_hint(self) -> Gtk.Widget:
        return make_inline_hint(
            "Reorder entries by dragging them, "
            "or with Alt+↑ / Alt+↓ on a focused row. "
            "Order matters when one variable references another (e.g. ‘PATH’)."
        )

    def _build_empty_state(self) -> EmptyState:
        return EmptyState(
            title="No Environment Variables",
            description=(
                "Export variables to processes Hyprland spawns — toolkit "
                "hints (QT_QPA_PLATFORM), theme overrides, scaling settings, "
                "and so on."
            ),
            icon_name=ENV_VARS_ICON,
            primary_action=("Add Variable…", self._on_add),
        )

    def _deleted_row_summary(self, item: EnvVar) -> tuple[str, str]:
        return item.name, item.value or "(empty)"

    # ── Pending-changes summarizers ──

    def _summarize_item(self, item: EnvVar) -> tuple[str, str]:
        return item.name, item.value or "(empty)"

    def _summarize_modified(self, baseline: EnvVar, item: EnvVar) -> tuple[str, str]:
        if baseline.name != item.name:
            # Renames (delete-old + add-new) shouldn't reach here — they
            # appear as one "added" and one "removed" — but if the page
            # ever supports in-place rename, surface both halves of the diff.
            return item.name, f"{baseline.name} → {item.name}"
        return item.name, f"{baseline.value or '(empty)'} → {item.value or '(empty)'}"

    def _make_row(self, idx: int, item: EnvVar) -> Adw.ActionRow:
        row = Adw.ActionRow(
            title=html_escape(item.name),
            # The value is the interesting part — show it as the subtitle
            # in monospace so users can scan long values (e.g. paths).
            subtitle=html_escape(item.value or "(empty)"),
        )
        row.set_title_lines(1)
        row.set_subtitle_lines(1)

        prefix = Gtk.Image.new_from_icon_name(ENV_VARS_ICON)
        prefix.set_opacity(0.6)
        prefix.set_pixel_size(28)
        row.add_prefix(prefix)

        # Whole-row drag-and-drop reorder, mirroring the autostart page.
        # ``Gtk.DragSource`` only claims the press if motion crosses its
        # threshold, so a plain click still activates the row (edit dialog).
        # Keyboard parallel: Alt+Up / Alt+Down on the focused row.
        self._reorder.attach(row, idx)
        if idx < len(self._rows_by_idx):
            self._rows_by_idx[idx] = row

        is_dirty = self._owned.is_item_dirty(idx)
        is_saved = self._owned.get_baseline(idx) is not None

        actions = RowActions(
            row,
            on_discard=lambda i=idx: self._discard_at(i),
            on_reset=lambda i=idx: self._on_delete_at(i),
            reset_icon="user-trash-symbolic",
            reset_tooltip="Remove this variable",
        )
        row.add_suffix(actions.box)
        actions.update(is_managed=True, is_dirty=is_dirty, is_saved=is_saved)

        row.set_activatable(True)
        row.connect("activated", lambda _r, i=idx: self._on_edit_at(i))
        row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))
        return row

    # ── External (read-only display + override flow) ──
    #
    # External-section layout (hint + per-file groups) uses the base
    # ``SavedListSectionPage`` template; ``_make_external_row`` reads
    # the cached ``_overridden_external`` set so it can muted-badge
    # already-overridden entries instead of offering a redundant
    # override button.

    def _build_external_hint(self) -> Gtk.Widget:
        return make_inline_hint(
            "Variables below come from your hyprland.conf or its "
            "sourced files. Click the edit button to override them — "
            "your managed entry will take precedence on the next "
            "Hyprland session."
        )

    def _make_external_row(self, ext: ExternalEnvVar) -> Adw.ActionRow:
        """One locked row representing an external env var."""
        is_overridden = ext.var.name in self._overridden_external
        # Subtitle = value + line number. Path is already in the group
        # title, so we don't repeat it on every row.
        subtitle = f"{ext.var.value or '(empty)'}  ·  line {ext.lineno}"

        row = Adw.ActionRow(
            title=html_escape(ext.var.name),
            subtitle=html_escape(subtitle),
        )
        row.set_title_lines(1)
        row.set_subtitle_lines(1)
        row.add_css_class("option-default")
        row.set_opacity(0.65)
        row.set_tooltip_text(f"{ext.source_path}:{ext.lineno}")

        prefix = Gtk.Image.new_from_icon_name(ENV_VARS_ICON)
        prefix.set_opacity(0.4)
        prefix.set_pixel_size(28)
        row.add_prefix(prefix)

        if is_overridden:
            # An owned entry with the same name is already in our managed
            # file — Hyprland will see ours last and use ours. Label the
            # external row so the user can see what they overrode.
            badge = Gtk.Label(label="Overridden")
            badge.add_css_class("pending-badge")
            badge.add_css_class("pending-badge-modified")
            badge.set_valign(Gtk.Align.CENTER)
            row.add_suffix(badge)
            lock_icon = Gtk.Image.new_from_icon_name("changes-prevent-symbolic")
            lock_icon.set_opacity(0.4)
            lock_icon.set_valign(Gtk.Align.CENTER)
            row.add_suffix(lock_icon)
            return row

        # Not yet overridden — offer the override action.
        override_btn = Gtk.Button(icon_name="document-edit-symbolic")
        override_btn.set_valign(Gtk.Align.CENTER)
        override_btn.add_css_class("flat")
        override_btn.set_tooltip_text("Override this variable")
        override_btn.connect("clicked", lambda _b, e=ext: self._on_override(e))
        row.add_suffix(override_btn)

        lock_icon = Gtk.Image.new_from_icon_name("changes-prevent-symbolic")
        lock_icon.set_opacity(0.4)
        lock_icon.set_valign(Gtk.Align.CENTER)
        row.add_suffix(lock_icon)
        return row

    def _on_override(self, ext: ExternalEnvVar) -> None:
        """Open the edit dialog pre-filled with *ext*'s name and value.

        The user can change either field before applying — for example,
        keep the same name but flip the value (the typical override
        case). On apply, a new managed entry is appended to ``_owned``
        and the page rebuilds with the external row newly badged
        "Overridden".

        Note that the dialog's normal "name in RESERVED_NAMES" guard
        still applies — but external rows for reserved names are
        already filtered out by :func:`load_external_env_vars`, so
        users can only land here with a non-reserved name.
        """
        EnvVarEditDialog.present_singleton(
            self._window,
            entry=ext.var,
            is_override=True,
            on_apply=self._commit_appended,
        )

    # ── Add / Edit / Remove ──

    def _on_add(self) -> None:
        EnvVarEditDialog.present_singleton(self._window, on_apply=self._commit_appended)

    def _on_edit_at(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._owned):
            return
        current = self._owned[idx]

        def on_apply(new_item: EnvVar) -> None:
            if new_item != current:
                self._commit_replaced(idx, new_item)

        EnvVarEditDialog.present_singleton(
            self._window,
            entry=current,
            on_apply=on_apply,
        )

    # ``_on_delete_at`` / ``_discard_at`` / ``_on_restore_deleted`` use
    # the base ``SavedListSectionPage`` defaults — env vars don't have
    # any live-apply side effects, so no override is needed.

    # ── Save plumbing ──

    def is_dirty(self) -> bool:
        return list(self._owned) != self._saved_items

    def mark_saved(self) -> None:
        # Preserve cursor vars from env.lua, write everything back
        cursor_items = [item for item in parse_env_lua_file(ENV_LUA_PATH)
                        if item.name in RESERVED_NAMES]
        owned_names = {e.name for e in self._owned}
        cursor_items = [c for c in cursor_items if c.name not in owned_names]
        all_items = cursor_items + list(self._owned)
        ENV_LUA_PATH.parent.mkdir(parents=True, exist_ok=True)
        ENV_LUA_PATH.write_text(serialize_env_lua(all_items))
        self._saved_items = list(self._owned)

    def discard(self) -> None:
        self._owned = SavedList(self._saved_items, key=lambda e: e.to_line())
        self._rebuild_list()

    def pending_change_count(self) -> int:
        if not self.is_dirty():
            return 0
        count = 0
        for item in self._owned:
            if item not in self._saved_items:
                count += 1
        for item in self._saved_items:
            if item not in self._owned:
                count += 1
        return count

    def get_env_lines(self) -> list[str]:
        return []


__all__ = ["EnvVarsPage"]
