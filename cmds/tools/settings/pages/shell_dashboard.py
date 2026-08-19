"""Dashboard page — customize the dashboard launcher tab.

Controls:
- Widget order: which dashboard widgets show (player, quick actions, calendar,
  notifications, controls) and their order (``widgetOrder``).
- QuickControls buttons: the hot-action buttons shown in the quick actions
  widget (Wi-Fi, Bluetooth, Quick Share, Caffeine, Dark Mode, Night Light),
  their order, and which are present (``controlOrder``). At least
  ``DASHBOARD_MIN_CONTROLS`` must remain.

All values live in ``~/.config/retro/shell/dashboard.json``, which the shell
watches via ``FileView`` so changes apply live.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import (
    DASHBOARD_CONTROL_IDS,
    DASHBOARD_MIN_CONTROLS,
    DASHBOARD_WIDGET_IDS,
    load_dashboard,
    save_dashboard,
)
from settings.ui import make_inline_hint, make_page_layout
from settings.ui.icons import DASHBOARD_ICON
from settings.ui.reorder import RowReorderController

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_WIDGET_LABELS = {
    "player": "Music Player",
    "quickactions": "Quick Actions + Calendar",
    "notifications": "Notifications",
    "controls": "Controls",
}

_WIDGET_DESCRIPTIONS = {
    "player": "Now-playing music player and media controls",
    "quickactions": "Hot-action buttons with the month calendar below",
    "notifications": "Notification history and activity feed",
    "controls": "Circular controls: brightness, volume and microphone",
}

_WIDGET_ICONS = {
    "player": "multimedia-player-symbolic",
    "quickactions": "emblem-system-symbolic",
    "notifications": "preferences-system-notifications-symbolic",
    "controls": "audio-volume-high-symbolic",
}

_CONTROL_LABELS = {
    "wifi": "Wi-Fi",
    "bluetooth": "Bluetooth",
    "quickshare": "Quick Share",
    "caffeine": "Caffeine",
    "darkmode": "Dark Mode",
    "nightlight": "Night Light",
}

_CONTROL_DESCRIPTIONS = {
    "wifi": "Toggle Wi-Fi and open the network panel",
    "bluetooth": "Toggle Bluetooth and manage paired devices",
    "quickshare": "Toggle Quick Share file transfer",
    "caffeine": "Inhibit sleep with an optional timer",
    "darkmode": "Switch between dark and light theme",
    "nightlight": "Toggle the warm night-light filter",
}

_CONTROL_ICONS = {
    "wifi": "network-wireless-symbolic",
    "bluetooth": "bluetooth-symbolic",
    "quickshare": "send-to-symbolic",
    "caffeine": "caffeine-symbolic",
    "darkmode": "darkmode-symbolic",
    "nightlight": "nightlight-symbolic",
}


class ShellDashboardPage:
    """Dashboard launcher customization."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None
        self._data = load_dashboard()
        self._saved = dict(self._data)
        self._content_box: Gtk.Box | None = None

        # Widget order
        self._widgets: list[str] = list(self._data.get("widgetOrder", DASHBOARD_WIDGET_IDS))
        self._saved_widgets: list[str] = list(self._widgets)
        self._widget_rows: list[Adw.ActionRow] = []
        self._widget_group: Adw.PreferencesGroup | None = None
        self._widget_reorder = RowReorderController(
            move=self._move_widget, iter_rows=lambda: self._widget_rows
        )

        # Control order
        self._controls: list[str] = list(self._data.get("controlOrder", DASHBOARD_CONTROL_IDS))
        self._saved_controls: list[str] = list(self._controls)
        self._control_rows: list[Adw.ActionRow] = []
        self._control_group: Adw.PreferencesGroup | None = None
        self._control_reorder = RowReorderController(
            move=self._move_control, iter_rows=lambda: self._control_rows
        )

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        # Widget order
        self._widget_group = Adw.PreferencesGroup(
            title="Dashboard Layout",
            description="Drag the boxes to arrange the horizontal order of the dashboard groups.",
        )
        content_box.append(self._widget_group)
        content_box.append(make_inline_hint(
            "Drag a group left or right to reposition it, or Alt+← / Alt+→ on a focused row."
        ))
        self._rebuild_widgets()

        # Control order
        self._control_group = Adw.PreferencesGroup(
            title="Quick Action Buttons",
            description=f"Drag the boxes to order the hot-action buttons. At least {DASHBOARD_MIN_CONTROLS} must stay enabled.",
        )
        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_valign(Gtk.Align.CENTER)
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text("Add a control button")
        add_btn.connect("clicked", self._on_add_control)
        self._control_group.set_header_suffix(add_btn)
        content_box.append(self._control_group)
        content_box.append(make_inline_hint(
            "Reorder controls by dragging them. Remove a button to hide it from the dashboard."
        ))
        self._rebuild_controls()

        return toolbar

    # ── Widget order list ──

    def _rebuild_widgets(self, focus_idx: int = -1) -> None:
        if self._widget_group is None:
            return
        group = self._widget_group
        for row in self._widget_rows:
            group.remove(row)
        self._widget_rows = []

        for idx, wid in enumerate(self._widgets):
            row = Adw.ActionRow(
                title=_WIDGET_LABELS.get(wid, wid),
                subtitle=_WIDGET_DESCRIPTIONS.get(wid, ""),
            )
            row.set_subtitle_lines(2)

            icon = Gtk.Image.new_from_icon_name(_WIDGET_ICONS.get(wid, "view-list-symbolic"))
            icon.set_pixel_size(24)
            icon.add_css_class("dim-label")
            row.add_prefix(icon)

            handle = Gtk.Image.new_from_icon_name("drag-handle-symbolic")
            handle.set_opacity(0.5)
            handle.set_valign(Gtk.Align.CENTER)
            row.add_suffix(handle)

            self._widget_reorder.attach(row, idx)
            group.add(row)
            self._widget_rows.append(row)

        if focus_idx >= 0 and focus_idx < len(self._widget_rows):
            self._widget_rows[focus_idx].grab_focus()

    def _move_widget(self, src: int, dst: int) -> bool:
        n = len(self._widgets)
        if dst == src or not (0 <= src < n and 0 <= dst < n):
            return False
        item = self._widgets.pop(src)
        self._widgets.insert(dst, item)
        self._notify_dirty()
        self._rebuild_widgets(dst)
        return True

    # ── Control order list ──

    def _rebuild_controls(self, focus_idx: int = -1) -> None:
        if self._control_group is None:
            return
        group = self._control_group
        for row in self._control_rows:
            group.remove(row)
        self._control_rows = []

        for idx, cid in enumerate(self._controls):
            row = Adw.ActionRow(
                title=_CONTROL_LABELS.get(cid, cid),
                subtitle=_CONTROL_DESCRIPTIONS.get(cid, ""),
            )
            row.set_subtitle_lines(1)

            icon = Gtk.Image.new_from_icon_name(_CONTROL_ICONS.get(cid, "emblem-system-symbolic"))
            icon.set_pixel_size(24)
            icon.add_css_class("dim-label")
            row.add_prefix(icon)

            handle = Gtk.Image.new_from_icon_name("drag-handle-symbolic")
            handle.set_opacity(0.5)
            handle.set_valign(Gtk.Align.CENTER)
            row.add_suffix(handle)

            remove_btn = Gtk.Button(icon_name="user-trash-symbolic")
            remove_btn.set_valign(Gtk.Align.CENTER)
            remove_btn.add_css_class("flat")
            remove_btn.set_tooltip_text("Remove from dashboard")
            remove_btn.set_sensitive(len(self._controls) > DASHBOARD_MIN_CONTROLS)
            remove_btn.connect("clicked", lambda _b, i=idx: self._on_remove_control(i))
            row.add_suffix(remove_btn)

            self._control_reorder.attach(row, idx)
            group.add(row)
            self._control_rows.append(row)

        if focus_idx >= 0 and focus_idx < len(self._control_rows):
            self._control_rows[focus_idx].grab_focus()

    def _move_control(self, src: int, dst: int) -> bool:
        n = len(self._controls)
        if dst == src or not (0 <= src < n and 0 <= dst < n):
            return False
        item = self._controls.pop(src)
        self._controls.insert(dst, item)
        self._notify_dirty()
        self._rebuild_controls(dst)
        return True

    def _on_add_control(self, _btn=None) -> None:
        available = [c for c in DASHBOARD_CONTROL_IDS if c not in self._controls]
        if not available:
            self._window.show_toast("All controls are already added", timeout=2)
            return

        group = Adw.PreferencesGroup()
        combo = Adw.ComboRow(title="Control")
        combo.set_model(Gtk.StringList.new([_CONTROL_LABELS.get(c, c) for c in available]))
        combo.set_selected(0)
        group.add(combo)

        dialog = Adw.AlertDialog(
            heading="Add Control Button",
            extra_child=group,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("add", "Add")
        dialog.set_default_response("add")
        dialog.set_close_response("cancel")

        def _on_response(_dialog_obj, response):
            if response != "add":
                return
            idx = combo.get_selected()
            if 0 <= idx < len(available):
                self._controls.append(available[idx])
                self._notify_dirty()
                self._rebuild_controls()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    def _on_remove_control(self, idx: int) -> None:
        if idx < 0 or idx >= len(self._controls):
            return
        if len(self._controls) <= DASHBOARD_MIN_CONTROLS:
            self._window.show_toast(
                f"Keep at least {DASHBOARD_MIN_CONTROLS} controls", timeout=2
            )
            return
        del self._controls[idx]
        self._notify_dirty()
        self._rebuild_controls()

    # ── Persistence ──

    def _write_live(self) -> None:
        self._data["widgetOrder"] = list(self._widgets)
        self._data["controlOrder"] = list(self._controls)
        save_dashboard(self._data)

    def _notify_dirty(self) -> None:
        self._write_live()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return (self._widgets != self._saved_widgets
                or self._controls != self._saved_controls)

    def mark_saved(self) -> None:
        self._data["widgetOrder"] = list(self._widgets)
        self._data["controlOrder"] = list(self._controls)
        save_dashboard(self._data)
        self._saved = dict(self._data)
        self._saved_widgets = list(self._widgets)
        self._saved_controls = list(self._controls)

    def discard(self) -> None:
        self._data = dict(self._saved)
        self._widgets = list(self._saved_widgets)
        self._controls = list(self._saved_controls)
        self._rebuild_widgets()
        self._rebuild_controls()
        self._write_live()

    def reload_from_disk(self) -> None:
        """Re-read dashboard.json (e.g. after applying a preset) and sync widgets."""
        self._data = load_dashboard()
        self._saved = dict(self._data)
        self._widgets = list(self._data.get("widgetOrder", DASHBOARD_WIDGET_IDS))
        self._saved_widgets = list(self._widgets)
        self._controls = list(self._data.get("controlOrder", DASHBOARD_CONTROL_IDS))
        self._saved_controls = list(self._controls)
        self._rebuild_widgets()
        self._rebuild_controls()

    # ── Pending changes ──

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        parts = []
        if self._widgets != self._saved_widgets:
            parts.append("Widgets")
        if self._controls != self._saved_controls:
            parts.append("Controls")
        yield PendingChange(
            category="Dashboard",
            title="Dashboard",
            subtitle=", ".join(parts[:3]),
            navigate_to="shell_dashboard",
            icon=DASHBOARD_ICON,
            kind="modified",
            revert=self.discard,
        )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "dashboard:widgets", "label": "Dashboard Widgets",
             "description": "Reorder and choose which widgets appear in the dashboard",
             "_group_id": "shell_dashboard", "_group_label": "Dashboard", "_section_label": "Widgets"},
            {"key": "dashboard:controls", "label": "Quick Action Buttons",
             "description": "Reorder and toggle the dashboard hot-action buttons",
             "_group_id": "shell_dashboard", "_group_label": "Dashboard", "_section_label": "Controls"},
        ]


__all__ = ["ShellDashboardPage"]
