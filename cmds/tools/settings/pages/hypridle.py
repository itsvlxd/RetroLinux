"""Hypridle management page — edit idle listeners and general settings."""

from html import escape as html_escape
from pathlib import Path

from gi.repository import Adw, Gtk

from settings.core import config
from settings.core.hypridle import (
    HYPRIDLE_CONFIG_PATH,
    IdleGeneral,
    IdleListener,
    hypridle_config_path,
    parse_hypridle,
    write_hypridle,
)
from settings.core.pending import PendingChange
from settings.ui import make_page_layout
from settings.ui.empty_state import EmptyState
from settings.ui.hypridle_dialog import IdleListenerDialog
from settings.ui.icons import SLEEP_ICON
from settings.ui.row_actions import RowActions


def _summarize_listener(l: IdleListener) -> str:
    parts = [f"{l.timeout}s"]
    if l.on_timeout:
        cmd = l.on_timeout[:40] + "…" if len(l.on_timeout) > 40 else l.on_timeout
        parts.append(f"→ {cmd}")
    if l.ignore_inhibit:
        parts.append("(no-inhibit)")
    return "  ".join(parts)


class HypridlePage:
    def __init__(self, window):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._scrolled: Gtk.ScrolledWindow | None = None
        self._dirty = False
        self._notify_dirty = lambda: None

        self._general = IdleGeneral()
        self._listeners: list[IdleListener] = []
        self._original_general = IdleGeneral()
        self._original_listeners: list[IdleListener] = []
        self._rows: list[Adw.ActionRow] = []

        self._general_widgets: dict[str, Gtk.Widget] = {}
        self._inhibit_spin: Gtk.SpinButton | None = None
        self._enable_idle_switch: Adw.SwitchRow | None = None
        self._enable_idle_value: bool = True

    def build(self, header: Adw.HeaderBar | None = None) -> Adw.ToolbarView:
        page_header = header or Adw.HeaderBar()

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Reload from file")
        refresh_btn.connect("clicked", lambda _b: self._on_refresh())
        page_header.pack_start(refresh_btn)

        toolbar_view, _, self._content_box, self._scrolled = make_page_layout(header=page_header)

        self._load()

        from lib.python.variable import get_var as _get_var
        self._enable_idle_value = _get_var("HYPRIDLE_ENABLE", "true") == "true"

        # Idle Configuration
        gen_group = Adw.PreferencesGroup(title="Idle Configuration")
        gen_group.set_description("Lock/unlock commands, sleep hooks, inhibit, and idle daemon toggle.")

        # Enable Idle — first option
        self._enable_idle_switch = Adw.SwitchRow(title="Enable Idle Daemon")
        self._enable_idle_switch.set_subtitle("Starts hypridle at boot to manage screen blanking, locking, and suspend")
        self._enable_idle_switch.set_active(self._enable_idle_value)
        self._enable_idle_switch.connect("notify::active", self._on_enable_idle_changed)
        gen_group.add(self._enable_idle_switch)

        for var, title, hint in [
            ("lock_cmd", "Lock Command", "Command to lock the session (e.g. 'pidof hyprlock || hyprlock')"),
            ("unlock_cmd", "Unlock Command", "Command to unlock the session"),
            ("on_lock_cmd", "On Lock Command", "Command run when the session gets locked by a lock screen app"),
            ("on_unlock_cmd", "On Unlock Command", "Command run when the session gets unlocked"),
            ("before_sleep_cmd", "Before Sleep Command", "Command run before the system suspends"),
            ("after_sleep_cmd", "After Sleep Command", "Command run after the system wakes up"),
        ]:
            row = Adw.EntryRow(title=title)
            row.set_text(getattr(self._general, var, ""))
            row.connect("changed", self._on_general_changed, var)
            gen_group.add(row)
            self._general_widgets[var] = row

        # Inhibit toggles
        for var, title, hint in [
            ("ignore_dbus_inhibit", "Ignore D-Bus Inhibit", "Bypass Firefox and other apps' idle inhibit"),
            ("ignore_systemd_inhibit", "Ignore systemd Inhibit", "Bypass systemd-inhibit idle blockers"),
            ("ignore_wayland_inhibit", "Ignore Wayland Inhibit", "Bypass Wayland protocol idle inhibitors"),
        ]:
            sw = Adw.SwitchRow(title=title)
            sw.set_subtitle(hint)
            sw.set_active(getattr(self._general, var, False))
            sw.connect("notify::active", self._on_general_switch_changed, var)
            gen_group.add(sw)
            self._general_widgets[var] = sw

        # Inhibit sleep mode
        inhibit_row = Adw.ActionRow(title="Inhibit Sleep Mode")
        inhibit_row.set_subtitle("0=disable  1=wait cmd  2=auto  3=lock")
        adj = Gtk.Adjustment(
            value=float(self._general.inhibit_sleep),
            lower=0, upper=3, step_increment=1, page_increment=1,
        )
        self._inhibit_spin = Gtk.SpinButton(adjustment=adj, digits=0)
        self._inhibit_spin.set_valign(Gtk.Align.CENTER)
        self._inhibit_spin.connect("notify::value", self._on_inhibit_changed)
        inhibit_row.add_suffix(self._inhibit_spin)
        gen_group.add(inhibit_row)

        self._content_box.append(gen_group)

        # Listeners
        self._listener_group = Adw.PreferencesGroup(title="Listeners")
        self._listener_group.set_description("Commands that fire after a set period of inactivity.")

        add_btn = Gtk.Button.new_from_icon_name("list-add-symbolic")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text("Add a listener")
        add_btn.connect("clicked", lambda _b: self._on_add())
        self._listener_group.set_header_suffix(add_btn)

        self._listener_listbox = Gtk.ListBox()
        self._listener_listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._listener_listbox.add_css_class("boxed-list")
        self._listener_group.add(self._listener_listbox)
        self._content_box.append(self._listener_group)

        self._rebuild_list()
        return toolbar_view

    def _load(self) -> None:
        path = hypridle_config_path()
        if not path.exists():
            default = config.RETRO_SETTINGS_DIR / "hypridle.conf"
            if default.exists():
                path = default
        self._general, self._listeners = parse_hypridle(path)
        self._original_general = IdleGeneral(
            **{f.name: getattr(self._general, f.name) for f in IdleGeneral.__dataclass_fields__.values()}
        )
        self._original_listeners = [IdleListener(**{f.name: getattr(l, f.name) for f in IdleListener.__dataclass_fields__.values()}) for l in self._listeners]
        from lib.python.variable import get_var as _get_var
        self._enable_idle_original = _get_var("HYPRIDLE_ENABLE", "true") == "true"
        self._enable_idle_value = self._enable_idle_original

    def _on_refresh(self) -> None:
        self._load()
        self._sync_widgets()
        self._rebuild_list()

    def _on_enable_idle_changed(self, sw: Adw.SwitchRow, _pspec) -> None:
        self._enable_idle_value = sw.get_active()
        self._check_dirty()

    def _on_general_changed(self, entry: Adw.EntryRow, _pspec, var: str) -> None:
        setattr(self._general, var, entry.get_text().strip())
        self._check_dirty()

    def _on_general_switch_changed(self, sw: Adw.SwitchRow, _pspec, var: str) -> None:
        setattr(self._general, var, sw.get_active())
        self._check_dirty()

    def _on_inhibit_changed(self, spin: Gtk.SpinButton, _pspec) -> None:
        self._general.inhibit_sleep = int(spin.get_value())
        self._check_dirty()

    def _check_dirty(self) -> None:
        gen_dirty = self._enable_idle_value != self._enable_idle_original or any(
            getattr(self._general, f.name) != getattr(self._original_general, f.name)
            for f in IdleGeneral.__dataclass_fields__.values()
        )
        # Compare listeners
        list_dirty = len(self._listeners) != len(self._original_listeners) or any(
            self._listeners[i].timeout != self._original_listeners[i].timeout
            or self._listeners[i].on_timeout != self._original_listeners[i].on_timeout
            or self._listeners[i].on_resume != self._original_listeners[i].on_resume
            or self._listeners[i].ignore_inhibit != self._original_listeners[i].ignore_inhibit
            for i in range(min(len(self._listeners), len(self._original_listeners)))
        )
        dirty = gen_dirty or list_dirty
        if dirty != self._dirty:
            self._dirty = dirty
            self._notify_dirty()

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        self._dirty = False
        self._original_general = IdleGeneral(
            **{f.name: getattr(self._general, f.name) for f in IdleGeneral.__dataclass_fields__.values()}
        )
        self._original_listeners = [
            IdleListener(**{f.name: getattr(l, f.name) for f in IdleListener.__dataclass_fields__.values()})
            for l in self._listeners
        ]
        from lib.python.variable import get_var as _get_var
        self._enable_idle_original = self._enable_idle_value

    def discard(self) -> None:
        self._general = IdleGeneral(
            **{f.name: getattr(self._original_general, f.name) for f in IdleGeneral.__dataclass_fields__.values()}
        )
        self._listeners = [
            IdleListener(**{f.name: getattr(l, f.name) for f in IdleListener.__dataclass_fields__.values()})
            for l in self._original_listeners
        ]
        from lib.python.variable import get_var as _get_var
        self._enable_idle_value = _get_var("HYPRIDLE_ENABLE", "true") == "true"
        self._dirty = False
        self._sync_widgets()
        self._rebuild_list()

    def _sync_widgets(self) -> None:
        if self._enable_idle_switch is not None:
            self._enable_idle_switch.set_active(self._enable_idle_value)
        for var, widget in self._general_widgets.items():
            if isinstance(widget, Adw.EntryRow):
                widget.set_text(getattr(self._general, var, ""))
            elif isinstance(widget, Adw.SwitchRow):
                widget.set_active(getattr(self._general, var, False))
        if self._inhibit_spin is not None:
            self._inhibit_spin.set_value(float(self._general.inhibit_sleep))

    def flush_pending(self) -> None:
        write_hypridle(general=self._general, listeners=self._listeners)
        from lib.python.variable import set_var as _set_var
        _set_var("HYPRIDLE_ENABLE", "true" if self._enable_idle_value else "false")
        self.mark_saved()

    def iter_pending_changes(self):
        if self._dirty:
            yield PendingChange(
                category="Sleep",
                title="Hypridle configuration",
                subtitle=f"{len(self._listeners)} listener(s)",
                navigate_to="hypridle",
                icon=SLEEP_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "hypridle:general", "label": "Sleep — General", "description": "Lock/unlock commands, sleep hooks, and idle inhibition", "_group_id": "hypridle", "_group_label": "Sleep", "_section_label": "General"},
            {"key": "hypridle:listeners", "label": "Sleep — Listeners", "description": "Timeout-based idle listeners with commands", "_group_id": "hypridle", "_group_label": "Sleep", "_section_label": "Listeners"},
        ]

    # ── Listener management ──

    def _on_add(self) -> None:
        def on_apply(listener: IdleListener) -> None:
            self._listeners.append(listener)
            self._check_dirty()
            self._rebuild_list()

        IdleListenerDialog.present_singleton(self._window, on_apply=on_apply)

    def _on_edit(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._listeners):
            return
        current = self._listeners[idx]

        def on_apply(new_listener: IdleListener) -> None:
            if new_listener == current:
                return
            self._listeners[idx] = new_listener
            self._check_dirty()
            self._rebuild_list()

        IdleListenerDialog.present_singleton(self._window, listener=current, on_apply=on_apply)

    def _on_delete(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._listeners):
            return
        del self._listeners[idx]
        self._check_dirty()
        self._rebuild_list()

    def _rebuild_list(self) -> None:
        if self._listener_listbox is None:
            return
        child = self._listener_listbox.get_first_child()
        while child is not None:
            self._listener_listbox.remove(child)
            child = self._listener_listbox.get_first_child()
        self._rows = []

        if not self._listeners:
            empty = EmptyState(
                title="No Sleep Listeners",
                description="Add a listener to run commands when your system is idle — dim the screen, lock the session, suspend, and more.",
                icon_name=SLEEP_ICON,
                primary_action=("Add Listener", self._on_add),
            )
            self._listener_listbox.append(empty)
            return

        for i, listener in enumerate(self._listeners):
            row = Adw.ActionRow(
                title=html_escape(_summarize_listener(listener)),
            )
            row.set_subtitle_lines(1)
            row.add_prefix(Gtk.Image.new_from_icon_name("clock-symbolic"))

            edit_btn = Gtk.Button.new_from_icon_name("document-edit-symbolic")
            edit_btn.set_valign(Gtk.Align.CENTER)
            edit_btn.add_css_class("flat")
            edit_btn.set_tooltip_text("Edit listener")
            edit_btn.connect("clicked", lambda _b, idx=i: self._on_edit(idx))
            row.add_suffix(edit_btn)

            delete_btn = Gtk.Button.new_from_icon_name("user-trash-symbolic")
            delete_btn.set_valign(Gtk.Align.CENTER)
            delete_btn.add_css_class("flat")
            delete_btn.set_tooltip_text("Remove listener")
            delete_btn.connect("clicked", lambda _b, idx=i: self._on_delete(idx))
            row.add_suffix(delete_btn)

            row.set_activatable(True)
            row.connect("activated", lambda _r, idx=i: self._on_edit(idx))
            row.add_suffix(Gtk.Image.new_from_icon_name("go-next-symbolic"))

            self._listener_listbox.append(row)
            self._rows.append(row)


__all__ = ["HypridlePage"]
