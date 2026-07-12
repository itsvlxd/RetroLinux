"""Add/edit dialog for a single hypridle listener."""

from collections.abc import Callable

from gi.repository import Adw, Gtk

from settings.core.hypridle import IdleListener
from settings.ui import build_preview_group
from settings.ui.dialog import SingletonDialogMixin


class IdleListenerDialog(SingletonDialogMixin, Adw.Dialog):
    """Add or edit a hypridle listener (timeout + commands)."""

    def __init__(
        self,
        *,
        listener: IdleListener | None = None,
        on_apply: Callable[[IdleListener], None] | None = None,
    ):
        super().__init__()
        self._is_new = listener is None
        self._on_apply_callback = on_apply

        self.set_title("New Listener" if self._is_new else "Edit Listener")
        self.set_content_width(520)
        self.set_content_height(480)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: self.close())
        header.pack_start(cancel_btn)

        self._apply_btn = Gtk.Button(label="Apply")
        self._apply_btn.add_css_class("suggested-action")
        self._apply_btn.connect("clicked", self._on_apply)
        header.pack_end(self._apply_btn)
        toolbar.add_top_bar(header)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_vexpand(True)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(600)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)

        # Timeout
        timeout_group = Adw.PreferencesGroup(title="Timeout")
        self._timeout_spin = Adw.SpinRow.new_with_range(1, 86400, 30)
        self._timeout_spin.set_title("Idle Timeout (seconds)")
        self._timeout_spin.set_subtitle("After this many seconds of inactivity, the on-timeout command fires.")
        self._timeout_spin.set_value(300)
        self._timeout_spin.connect("notify::value", self._on_changed)
        timeout_group.add(self._timeout_spin)
        content.append(timeout_group)

        # Commands
        cmd_group = Adw.PreferencesGroup(title="Commands")

        self._on_timeout_entry = Adw.EntryRow(title="On Timeout")
        self._on_timeout_entry.set_tooltip_text("Command to run when the timeout fires (e.g. loginctl lock-session)")
        self._on_timeout_entry.connect("changed", self._on_changed)
        cmd_group.add(self._on_timeout_entry)

        self._on_resume_entry = Adw.EntryRow(title="On Resume")
        self._on_resume_entry.set_tooltip_text("Command to run when activity resumes (optional)")
        self._on_resume_entry.connect("changed", self._on_changed)
        cmd_group.add(self._on_resume_entry)

        content.append(cmd_group)

        # Options
        opt_group = Adw.PreferencesGroup(title="Options")
        self._ignore_inhibit_switch = Adw.SwitchRow(title="Ignore Inhibit")
        self._ignore_inhibit_switch.set_subtitle("Keep this listener active even when apps request idle inhibition")
        self._ignore_inhibit_switch.connect("notify::active", self._on_changed)
        opt_group.add(self._ignore_inhibit_switch)
        content.append(opt_group)

        # Preview
        self._preview_group, self._preview_label = build_preview_group(
            description="Preview of this listener block as it will appear in hypridle.conf."
        )
        content.append(self._preview_group)

        clamp.set_child(content)
        scrolled.set_child(clamp)
        toolbar.set_content(scrolled)
        self.set_child(toolbar)

        if listener is not None:
            self._load_from_listener(listener)
        self._refresh()

    def _load_from_listener(self, listener: IdleListener) -> None:
        self._timeout_spin.set_value(float(listener.timeout))
        self._on_timeout_entry.set_text(listener.on_timeout)
        self._on_resume_entry.set_text(listener.on_resume)
        self._ignore_inhibit_switch.set_active(listener.ignore_inhibit)

    def _build_listener(self) -> IdleListener:
        return IdleListener(
            timeout=int(self._timeout_spin.get_value()),
            on_timeout=self._on_timeout_entry.get_text().strip(),
            on_resume=self._on_resume_entry.get_text().strip(),
            ignore_inhibit=self._ignore_inhibit_switch.get_active(),
        )

    def _on_changed(self, *_args: object) -> None:
        self._refresh()

    def _refresh(self) -> None:
        listener = self._build_listener()
        from settings.core.hypridle import serialize_hypridle
        self._preview_label.set_text(serialize_hypridle(listeners=[listener]).strip())
        has_timeout = listener.timeout > 0
        has_cmd = bool(listener.on_timeout.strip())
        self._apply_btn.set_sensitive(has_timeout and has_cmd)

    def _on_apply(self, *_args: object) -> None:
        listener = self._build_listener()
        if listener.timeout <= 0 or not listener.on_timeout.strip():
            return
        if self._on_apply_callback is not None:
            self._on_apply_callback(listener)
        self.close()


__all__ = ["IdleListenerDialog"]
