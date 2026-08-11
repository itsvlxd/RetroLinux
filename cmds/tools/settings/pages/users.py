"""Users page — create, re-sync, and delete system users.

Read-only page (never dirty): lists real system accounts with their retro
config status. All privileged actions run ``users_core.sh`` through
``pkexec`` in a background thread — no terminal is opened. pkexec shows a
native password prompt; output is captured to ``/tmp/retro_logs/users_gui.log``
and results are surfaced with toasts (errors include the log tail):

- **Add User** — creates the account, seeds ``~/.config/retro/variables.sh``
  from the current user (paths rewritten to the new home), generates a
  gradient avatar with the user's initials, and runs ``retro -i all -a user -y``
  as that user to deploy every user-space module. A custom profile picture
  and password can be chosen in the dialog.
- **Change picture** — sets a user's ``~/.face`` / ``~/.face.icon``.
- **Re-sync** — re-copies variables.sh and reinstalls the modules for an
  existing user.
- **Delete** — removes the user and their home directory.

Each user's avatar uses their ``.face`` / ``.face.icon`` when present,
falling back to initials.
"""

import os
import re
import subprocess
import threading
import time
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gdk, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import confirm, make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_USERS_CORE = os.path.join(
    os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "users_core.sh"
)
_USERNAME_RE = re.compile(r"^[a-z_][a-z0-9_-]*$")


def _list_users() -> list[dict]:
    """Query users_core.sh --list; each dict has name/uid/home/shell/retro/you."""
    try:
        r = subprocess.run(
            ["bash", _USERS_CORE, "--list"],
            capture_output=True, text=True, timeout=10,
            stdin=subprocess.DEVNULL,
        )
    except Exception:
        return []
    users = []
    for line in r.stdout.strip().splitlines():
        parts = line.split("|")
        if len(parts) != 6:
            continue
        name, uid, home, shell, retro, you = parts
        users.append({
            "name": name, "uid": uid, "home": home,
            "shell": shell, "retro": retro == "yes", "you": bool(you),
        })
    return users


def _face_path(home: str) -> str | None:
    """Return the user's avatar file (.face.icon preferred, then .face)."""
    for rel in (".face.icon", ".face"):
        path = os.path.join(home, rel)
        if os.path.isfile(path):
            return path
    return None


def _avatar_texture(path: str) -> Gdk.Texture | None:
    try:
        return Gdk.Texture.new_from_filename(path)
    except Exception:
        return None


def _can_sudo() -> bool:
    """True when the current user can elevate (root, or wheel/sudo group)."""
    if os.geteuid() == 0:
        return True
    try:
        r = subprocess.run(
            ["id", "-nG"], capture_output=True, text=True, timeout=5,
            stdin=subprocess.DEVNULL,
        )
        groups = r.stdout.split()
        return bool({"wheel", "sudo"} & set(groups))
    except Exception:
        return False


class UsersPage:
    """System user accounts — read-only action page."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._users: list[dict] = []
        self._list_group: Adw.PreferencesGroup | None = None
        self._rows: list[Gtk.ListBoxRow] = []
        self._on_dirty_changed = None

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        self._can_sudo = _can_sudo()

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_tooltip_text("Add user")
        add_btn.set_sensitive(self._can_sudo)
        add_btn.connect("clicked", lambda _b: self._on_add_user())
        header.pack_start(add_btn)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh users")
        refresh_btn.connect("clicked", lambda _b: self._reload())
        header.pack_start(refresh_btn)

        self._list_group = Adw.PreferencesGroup(title="Accounts")
        self._content_box.append(self._list_group)

        self._reload()
        return toolbar_view

    # ── Data loading ──

    def _reload(self) -> None:
        self._users = _list_users()
        self._render()

    def _render(self) -> None:
        if self._list_group is None:
            return
        for row in self._rows:
            self._list_group.remove(row)
        self._rows = []

        if not self._users:
            row = self._build_empty_row()
            self._list_group.add(row)
            self._rows.append(row)
            return

        for u in self._users:
            row = self._build_user_row(u)
            self._list_group.add(row)
            self._rows.append(row)

    @staticmethod
    def _build_empty_row() -> Gtk.ListBoxRow:
        lbl = Gtk.Label(label="No users found")
        lbl.set_margin_top(16)
        lbl.set_margin_bottom(16)
        lbl.add_css_class("dim-label")
        lbl.set_halign(Gtk.Align.CENTER)
        row = Gtk.ListBoxRow()
        row.set_child(lbl)
        return row

    # ── User row ──

    def _build_user_row(self, u: dict) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row.set_activatable(False)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(8)
        box.set_margin_end(8)

        avatar = Adw.Avatar()
        avatar.set_size(40)
        avatar.set_show_initials(True)
        avatar.set_text(u["name"])
        avatar.set_valign(Gtk.Align.CENTER)
        face = _face_path(u["home"])
        if face:
            tex = _avatar_texture(face)
            if tex is not None:
                avatar.set_custom_image(tex)

        avatar_btn = Gtk.Button()
        avatar_btn.add_css_class("flat")
        avatar_btn.add_css_class("circular")
        avatar_btn.set_child(avatar)
        avatar_btn.set_valign(Gtk.Align.CENTER)
        avatar_btn.set_tooltip_text("Change profile picture")
        avatar_btn.connect(
            "clicked", lambda _b, n=u["name"], h=u["home"]: self._on_change_picture(n, h)
        )
        box.append(avatar_btn)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        text_box.set_hexpand(True)

        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        name_lbl = Gtk.Label(label=u["name"])
        name_lbl.set_halign(Gtk.Align.START)
        name_lbl.set_ellipsize(True)
        name_box.append(name_lbl)

        if u["you"]:
            you_badge = Gtk.Label(label="CURRENT SESSION")
            you_badge.add_css_class("badge")
            you_badge.set_opacity(0.8)
            name_box.append(you_badge)

        text_box.append(name_box)

        subtitle_parts = [f"UID {u['uid']}", u["shell"], u["home"]]
        if u["retro"]:
            subtitle_parts.append("Retro configured")
        else:
            subtitle_parts.append("No retro config")
        sub_lbl = Gtk.Label(label="  ·  ".join(subtitle_parts))
        sub_lbl.set_halign(Gtk.Align.START)
        sub_lbl.add_css_class("dim-label")
        sub_lbl.add_css_class("caption")
        text_box.append(sub_lbl)

        box.append(text_box)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        btn_box.set_valign(Gtk.Align.CENTER)

        photo_btn = self._make_icon_button(
            "camera-photo-symbolic", "Change profile picture",
            lambda _b, n=u["name"], h=u["home"]: self._on_change_picture(n, h),
        )
        btn_box.append(photo_btn)

        edit_btn = self._make_icon_button(
            "document-edit-symbolic", "Edit user",
            lambda _b, n=u["name"], h=u["home"], s=u["shell"]: self._on_edit_user(n, h, s),
        )
        edit_btn.set_sensitive(self._can_sudo)
        btn_box.append(edit_btn)

        resync_btn = self._make_icon_button(
            "view-refresh-symbolic", "Re-sync retro config",
            lambda _b, n=u["name"]: self._on_resync(n),
        )
        resync_btn.set_sensitive(self._can_sudo)
        btn_box.append(resync_btn)

        delete_btn = self._make_icon_button(
            "user-trash-symbolic", "Delete user",
            lambda _b, n=u["name"]: self._on_delete(n),
        )
        delete_btn.set_sensitive(not u["you"] and self._can_sudo)
        btn_box.append(delete_btn)

        box.append(btn_box)
        row.set_child(box)
        return row

    @staticmethod
    def _make_icon_button(icon_name: str, tooltip: str, on_click) -> Gtk.Button:
        btn = Gtk.Button()
        btn.add_css_class("flat")
        img = Gtk.Image.new_from_icon_name(icon_name)
        img.set_pixel_size(16)
        btn.set_child(img)
        btn.set_tooltip_text(tooltip)
        btn.set_size_request(28, 28)
        btn.connect("clicked", on_click)
        return btn

    # ── Actions ──

    def _on_add_user(self) -> None:
        self._show_add_dialog()

    def _show_add_dialog(self) -> None:
        dialog = Adw.AlertDialog(
            heading="Create User",
            body="The new user is set up from your current config.",
        )

        entry = Adw.EntryRow(title="Username")
        entry.set_input_purpose(Gtk.InputPurpose.ALPHA)
        entry.set_text("")

        name_entry = Adw.EntryRow(title="Full name (optional)")

        password_entry = Adw.PasswordEntryRow(title="Password")

        confirm_password_entry = Adw.PasswordEntryRow(title="Confirm password")

        admin_row = Adw.SwitchRow(title="Grant sudo access")
        admin_row.set_subtitle("Adds the user to the wheel group")

        picture_row = Adw.ActionRow(title="Profile picture")
        picture_row.set_subtitle("Choose an image (optional)")

        self._add_pic_path: str | None = None
        pic_btn = Gtk.Button(label="Choose…")
        pic_btn.add_css_class("suggested-action")
        pic_btn.connect("clicked", lambda _b: self._pick_picture(picture_row))
        picture_row.add_suffix(pic_btn)
        self._add_pic_btn = pic_btn

        list_box = Adw.PreferencesGroup()
        list_box.add(entry)
        list_box.add(name_entry)
        list_box.add(password_entry)
        list_box.add(confirm_password_entry)
        list_box.add(admin_row)
        list_box.add(picture_row)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(list_box)
        dialog.set_extra_child(box)

        dialog.add_response("cancel", "Cancel")
        dialog.add_response("create", "Create")
        dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_response(_d, response):
            if response != "create":
                return
            username = entry.get_text().strip()
            full_name = name_entry.get_text().strip()
            password = password_entry.get_text()
            confirm_password = confirm_password_entry.get_text()
            if not password:
                self._window.show_toast("Password is required", timeout=4)
                return
            if password != confirm_password:
                self._window.show_toast("Passwords do not match", timeout=4)
                return
            admin = admin_row.get_active()
            pic = self._add_pic_path
            self._run_create(username, full_name, admin, pic, password)

        dialog.connect("response", on_response)
        dialog.present(self._window)

    def _pick_picture(self, row: Adw.ActionRow) -> None:
        dialog = Gtk.FileDialog.new()
        dialog.set_title("Choose a profile picture")

        def on_chosen(_dlg, result):
            try:
                gfile = dialog.open_finish(result)
            except GLib.Error:
                return
            if not gfile:
                return
            path = gfile.get_path()
            if not path or not os.path.isfile(path):
                return
            self._add_pic_path = path
            row.set_subtitle(os.path.basename(path))
            self._add_pic_btn.set_label("Change…")

        dialog.open(self._window, None, on_chosen)

    def _run_create(self, username: str, full_name: str, admin: bool, pic: str | None,
                    password: str = "") -> None:
        if not _USERNAME_RE.match(username):
            self._window.show_toast(
                "Invalid username — use lowercase letters, digits, _ and -",
                timeout=4,
            )
            return
        self._window.show_toast(f"Creating user {username}…", timeout=4)
        args = ["--create", username]
        if admin:
            args.append("--admin")
        if full_name:
            args += ["--full-name", full_name]
        if password:
            args += ["--password", password]
        self._run_privileged(
            args,
            success=f"User {username} created",
            error=f"Failed to create {username}",
            expect_present=True,
            username=username,
        )

        if pic:
            self._run_privileged(
                ["--set-face", username, pic],
                success=f"Profile picture set for {username}",
                error=f"Failed to set profile picture for {username}",
            )

    def _on_change_picture(self, username: str, home: str) -> None:
        def do_set(path: str):
            self._run_privileged(
                ["--set-face", username, path],
                success=f"Profile picture set for {username}",
                error=f"Failed to set profile picture for {username}",
                reload_on_success=True,
            )
        self._window.show_toast("Select a picture to set as the avatar", timeout=3)

        dialog = Gtk.FileDialog.new()
        dialog.set_title(f"Profile picture for {username}")

        def on_chosen(_dlg, result):
            try:
                gfile = dialog.open_finish(result)
            except GLib.Error:
                return
            if not gfile:
                return
            path = gfile.get_path()
            if not path or not os.path.isfile(path):
                return
            do_set(path)

        dialog.open(self._window, None, on_chosen)

    def _on_resync(self, username: str) -> None:
        def do_resync():
            self._run_privileged(
                ["--resync", username],
                success=f"Config re-synced for {username}",
                error=f"Failed to re-sync {username}",
            )
        confirm(
            self._window,
            heading=f"Re-sync {username}?",
            body=(
                "This re-copies variables.sh from the current account and "
                "reinstalls all user-space modules for this user. Their "
                "settings are updated to match yours."
            ),
            label="Re-sync",
            on_confirm=do_resync,
            appearance=Adw.ResponseAppearance.SUGGESTED,
        )

    def _on_delete(self, username: str) -> None:
        def do_delete():
            self._run_privileged(
                ["--delete", username],
                success=f"User {username} deleted",
                error=f"Failed to delete {username}",
                expect_present=False,
                username=username,
            )
        confirm(
            self._window,
            heading=f"Delete {username}?",
            body=(
                "This permanently removes the user and their home directory. "
                "This cannot be undone."
            ),
            label="Delete",
            on_confirm=do_delete,
        )

    def _on_edit_user(self, username: str, home: str, shell: str) -> None:
        dialog = Adw.AlertDialog(
            heading=f"Edit {username}",
            body="Move the home folder and/or change the login shell.",
        )

        home_entry = Adw.EntryRow(title="Home folder")
        home_entry.set_text(home)

        shell_entry = Adw.EntryRow(title="Default shell")
        shell_entry.set_text(shell)

        delete_old_sw = Adw.SwitchRow(title="Delete old home directory")
        delete_old_sw.set_subtitle(
            "Remove the previous home folder after moving (irreversible)"
        )
        delete_old_sw.set_sensitive(False)

        def on_home_changed(*_a):
            delete_old_sw.set_sensitive(home_entry.get_text().strip() != home)

        home_entry.connect("changed", on_home_changed)

        list_box = Adw.PreferencesGroup()
        list_box.add(home_entry)
        list_box.add(shell_entry)
        list_box.add(delete_old_sw)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(list_box)
        dialog.set_extra_child(box)

        dialog.add_response("cancel", "Cancel")
        dialog.add_response("apply", "Apply")
        dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_response(_d, response):
            if response != "apply":
                return
            new_home = home_entry.get_text().strip()
            new_shell = shell_entry.get_text().strip()
            delete_old = delete_old_sw.get_active()

            if new_home == home and new_shell == shell:
                self._window.show_toast("No changes made", timeout=3)
                return

            args = ["--modify", username]
            if new_home and new_home != home:
                args += ["--home", new_home]
            if new_shell and new_shell != shell:
                args += ["--shell", new_shell]
            if delete_old:
                args += ["--delete-old", "true"]

            self._window.show_toast(f"Updating {username}…", timeout=4)
            self._run_privileged(
                args,
                success=f"User {username} updated",
                error=f"Failed to update {username}",
                username=username,
                expect_present=True,
            )

        dialog.connect("response", on_response)
        dialog.present(self._window)

    def _run_privileged(self, args: list[str], *, success: str, error: str,
                        username: str | None = None,
                        expect_present: bool | None = None,
                        reload_on_success: bool = False) -> None:
        """Run a users_core action via pkexec in the background.

        No terminal is opened: pkexec shows a native password prompt, output
        is captured to the retro users log, and the result is surfaced with a
        toast (error variant copies the log tail).
        """
        full_args = ["pkexec", "bash", _USERS_CORE, *args]
        self._window.show_toast("Requesting elevated access…", timeout=3)

        def worker():
            try:
                r = subprocess.run(
                    full_args,
                    capture_output=True, text=True, timeout=600,
                    stdin=subprocess.DEVNULL,
                )
            except Exception as e:
                GLib.idle_add(
                    lambda: self._window.show_bug_toast(
                        f"{error} — {e}", detail=str(e), timeout=6
                    )
                )
                return

            out = (r.stdout or "") + (r.stderr or "")
            if out.strip():
                self._append_log(out)

            if r.returncode == 0:
                GLib.idle_add(lambda: self._window.show_toast(success))
                if username and expect_present is not None:
                    GLib.idle_add(
                        lambda: self._refresh_when_user_changes(
                            username, expect_present=expect_present
                        )
                    )
                elif reload_on_success:
                    GLib.idle_add(self._reload)
            else:
                tail = "\n".join(out.strip().splitlines()[-8:])
                GLib.idle_add(
                    lambda: self._window.show_bug_toast(
                        f"{error} — see log for details",
                        detail=tail or str(r.returncode), timeout=8,
                    )
                )

        threading.Thread(target=worker, daemon=True).start()

    @staticmethod
    def _append_log(text: str) -> None:
        import datetime
        log_dir = "/tmp/retro_logs"
        os.makedirs(log_dir, exist_ok=True)
        path = os.path.join(log_dir, "users_gui.log")
        ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        lines = [f"[{ts}] {line}" for line in text.strip().splitlines()]
        try:
            with open(path, "a") as f:
                f.write("\n".join(lines) + "\n")
        except OSError:
            pass

    def _refresh_when_user_changes(self, username: str, *, expect_present: bool) -> None:
        """Poll getent in the background and reload the list once the user's
        existence matches *expect_present* (e.g. after a delete the terminal
        closes, the account disappears, and the list refreshes by itself)."""
        def worker():
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                try:
                    r = subprocess.run(
                        ["getent", "passwd", username],
                        capture_output=True, text=True, timeout=5,
                        stdin=subprocess.DEVNULL,
                    )
                    present = r.returncode == 0
                except Exception:
                    present = expect_present
                if present == expect_present:
                    GLib.idle_add(self._reload)
                    return
                time.sleep(1)
        threading.Thread(target=worker, daemon=True).start()

    # ── Lifecycle (read-only) ──

    def is_dirty(self) -> bool:
        return False

    def mark_saved(self) -> None:
        pass

    def discard(self) -> None:
        pass

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return ()

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "users:overview", "label": "Users",
             "description": "Create, re-sync and delete system users",
             "_group_id": "users", "_group_label": "System", "_section_label": "Overview"},
            {"key": "users:create", "label": "Create User",
             "description": "Add a new account from the current config",
             "_group_id": "users", "_group_label": "System", "_section_label": "Accounts"},
            {"key": "users:picture", "label": "Change Profile Picture",
             "description": "Set a user's avatar (.face / .face.icon)",
             "_group_id": "users", "_group_label": "System", "_section_label": "Accounts"},
            {"key": "users:edit", "label": "Edit User",
             "description": "Move a user's home folder or change their login shell",
             "_group_id": "users", "_group_label": "System", "_section_label": "Accounts"},
            {"key": "users:resync", "label": "Re-sync User",
             "description": "Re-copy config and reinstall modules for a user",
             "_group_id": "users", "_group_label": "System", "_section_label": "Accounts"},
            {"key": "users:delete", "label": "Delete User",
             "description": "Remove a user and their home directory",
             "_group_id": "users", "_group_label": "System", "_section_label": "Accounts"},
        ]


__all__ = ["UsersPage"]
