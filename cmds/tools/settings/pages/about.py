"""About page — Retro Linux branding, system specs, and quick actions.

A read-only standalone page pinned in the sidebar above Settings. Gathers
hardware/software info via :mod:`settings.core.system_info` (background
thread, like the audio/network pages) and renders it with the Retro Linux
logo from ``assets/``.

Buttons:
- **Check Updates** — counts available package updates and offers to run
  ``retro --update`` in a terminal when any are found.
- **Copy Specs** — copies a plain-text spec block to the clipboard (wrench
  icon in the header bar).
- **Branch Selector** — switches the repository between the rolling
  ``develop`` and stable ``main`` branches.
- **View System Logs** — navigates to the existing Logs page.
- **GitHub Repo** — opens the repo URL in the default browser.
"""

import os
import re
import subprocess
import threading
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GdkPixbuf, Gio, GLib, Gtk

from settings.core.pending import PendingChange
from settings.core.system_info import (
    collect_system_info,
    copy_specs_text,
    display_version,
    get_preloaded_info,
    preload_system_info,
)
from settings.ui import confirm, make_page_layout
from settings.ui.icons import ABOUT_ICON

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_LOGO_PATH = os.path.join(
    os.environ.get("RETRO_DIR", "/opt/retrolinux"),
    "assets", "logo-palm-transparent-bg.png",
)

_REPO_FALLBACK = "https://github.com/anomalyco/retrolinux"


def _repo_url() -> str:
    """Best-effort https URL for the origin remote."""
    try:
        out = subprocess.run(
            ["git", "-C", os.environ.get("RETRO_DIR", "/opt/retrolinux"),
             "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=3,
            stdin=subprocess.DEVNULL,
        ).stdout.strip()
    except Exception:
        out = ""
    if out.startswith("git@"):
        m = re.match(r"git@([^:]+):(.+?)(?:\.git)?$", out)
        if m:
            return f"https://{m.group(1)}/{m.group(2)}"
    if out.endswith(".git"):
        out = out[:-4]
    return out or _REPO_FALLBACK


class AboutPage:
    """Retro Linux system info + actions. Read-only (never dirty)."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._check_btn: Gtk.Button | None = None
        self._version_lbl: Gtk.Label | None = None
        self._badge_lbl: Gtk.Label | None = None
        self._branch_dd: Gtk.DropDown | None = None
        self._branch_switching = False
        self._info = None
        self._value_rows: dict[str, Adw.ActionRow] = {}
        self._mem_bar: Gtk.LevelBar | None = None
        self._mem_lbl: Gtk.Label | None = None
        self._stor_bar: Gtk.LevelBar | None = None
        self._stor_lbl: Gtk.Label | None = None
        self._updates_count = -1
        self._auto_checked = False

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        copy_btn = Gtk.Button(icon_name="lucide-wrench-symbolic")
        copy_btn.set_tooltip_text("Copy specs")
        copy_btn.connect("clicked", lambda _b: self._copy_specs())
        header.pack_start(copy_btn)

        content_box.append(self._build_branding())

        hw = Adw.PreferencesGroup(title="Hardware")
        self._build_hardware(hw)
        content_box.append(hw)

        sw = Adw.PreferencesGroup(title="Software")
        self._build_software(sw)
        content_box.append(sw)

        info = get_preloaded_info()
        if info is not None:
            self._on_info_loaded(info)
        else:
            self._load_info_async()

        if not self._auto_checked:
            self._auto_checked = True
            self._check_updates(interactive=False)
        return toolbar

    def _build_branding(self) -> Gtk.Widget:
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        card.add_css_class("card")
        card.set_hexpand(True)
        card.set_margin_top(6)
        card.set_margin_bottom(12)

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        inner.set_margin_top(14)
        inner.set_margin_bottom(14)
        inner.set_margin_start(16)
        inner.set_margin_end(16)
        card.append(inner)

        if os.path.exists(_LOGO_PATH):
            logo = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            logo.set_halign(Gtk.Align.CENTER)
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file(_LOGO_PATH)
                pic = Gtk.Picture.new_for_pixbuf(pb)
                pic.set_content_fit(Gtk.ContentFit.CONTAIN)
                pic.set_size_request(96, 96)
                pic.set_halign(Gtk.Align.CENTER)
                pic.set_valign(Gtk.Align.CENTER)
                logo.append(pic)
            except Exception:
                pass
            inner.append(logo)

        title = Gtk.Label()
        title.set_markup('<span size="33000">Retro Linux</span>')
        title.add_css_class("title-1")
        title.set_halign(Gtk.Align.CENTER)
        inner.append(title)

        self._version_lbl = Gtk.Label(label="…")
        self._version_lbl.add_css_class("dim-label")
        self._version_lbl.set_halign(Gtk.Align.CENTER)
        inner.append(self._version_lbl)

        self._badge_lbl = Gtk.Label(label="…")
        self._badge_lbl.add_css_class("badge")
        self._badge_lbl.set_opacity(0.8)
        self._badge_lbl.set_halign(Gtk.Align.CENTER)
        inner.append(self._badge_lbl)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_box.set_halign(Gtk.Align.CENTER)
        btn_box.set_margin_top(10)

        self._check_btn = Gtk.Button(label="Check Updates")
        self._check_btn.add_css_class("suggested-action")
        self._check_btn.connect("clicked", lambda _b: self._check_updates())
        btn_box.append(self._check_btn)

        self._branch_dd = self._build_branch_dropdown()
        btn_box.append(self._branch_dd)

        gh_btn = Gtk.Button(label="GitHub Repo")
        gh_btn.connect("clicked", lambda _b: self._open_repo())
        btn_box.append(gh_btn)

        inner.append(btn_box)

        return card

    def _build_branch_dropdown(self) -> Gtk.DropDown:
        model = Gtk.StringList(strings=["Rolling (develop)", "Stable (main)"])
        dd = Gtk.DropDown(model=model)
        dd.set_selected(self._branch_index(self._current_branch()))
        dd.connect("notify::selected", self._on_branch_selected)
        return dd

    def _add_value_row(self, group: Adw.PreferencesGroup, title: str, icon: str = "") -> Adw.ActionRow:
        row = Adw.ActionRow(title=title, subtitle="—")
        if icon:
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(20)
            img.set_valign(Gtk.Align.CENTER)
            row.add_prefix(img)
        group.add(row)
        self._value_rows[title] = row
        return row

    def _add_bar_row(
        self,
        group: Adw.PreferencesGroup,
        title: str,
        icon: str = "",
    ) -> tuple[Adw.ActionRow, Gtk.LevelBar, Gtk.Label]:
        bar = Gtk.LevelBar()
        bar.set_min_value(0)
        bar.set_max_value(1)
        bar.set_size_request(180, 8)
        bar.set_valign(Gtk.Align.CENTER)

        lbl = Gtk.Label(label="—")
        lbl.set_valign(Gtk.Align.CENTER)

        suffix = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        suffix.set_valign(Gtk.Align.CENTER)
        suffix.append(bar)
        suffix.append(lbl)

        row = Adw.ActionRow(title=title)
        if icon:
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(20)
            img.set_valign(Gtk.Align.CENTER)
            row.add_prefix(img)
        row.add_suffix(suffix)
        group.add(row)
        return row, bar, lbl

    def _build_hardware(self, group: Adw.PreferencesGroup) -> None:
        self._add_value_row(group, "Processor", "cpu-symbolic")
        self._add_value_row(group, "Graphics", "video-display-symbolic")
        self._mem_row, self._mem_bar, self._mem_lbl = self._add_bar_row(group, "Memory", "memory-symbolic")
        self._stor_row, self._stor_bar, self._stor_lbl = self._add_bar_row(group, "Storage", "drive-harddisk-symbolic")

    def _build_software(self, group: Adw.PreferencesGroup) -> None:
        self._add_value_row(group, "Kernel", "terminal-symbolic")
        self._add_value_row(group, "Compositor", "display-symbolic")
        self._add_value_row(group, "Uptime", "appointment-soon-symbolic")

    # ── Data loading ──

    def _load_info_async(self) -> None:
        def worker():
            compositor = getattr(self._window.hypr, "version", None) or "Hyprland"
            # Reuse the app-startup preload if it's still running; only collect
            # ourselves when nothing is cached and nothing is in flight.
            preload_system_info(compositor=compositor)
            info = get_preloaded_info(timeout=20)
            if info is None:
                info = collect_system_info(compositor=compositor)
            GLib.idle_add(self._on_info_loaded, info)
        threading.Thread(target=worker, daemon=True).start()

    def _on_info_loaded(self, info) -> None:
        self._info = info
        version = display_version(info.os_version)
        if info.os_branch:
            version = f"{version} ({info.os_branch})"
        self._version_lbl.set_label(f"Version {version}")

        rolling = "nightly" in info.os_version.lower() or "rolling" in info.os_version.lower()
        self._badge_lbl.set_label("Rolling Release" if rolling else "Stable Release")

        rows = {
            "Processor": info.cpu_label,
            "Graphics": info.gpu + (f" · {info.gpu_mem_label}" if info.gpu_mem_label else "") or "—",
            "Kernel": info.kernel_label,
            "Compositor": info.compositor_label,
            "Uptime": info.uptime or "—",
        }
        for title, value in rows.items():
            row = self._value_rows.get(title)
            if row is not None:
                row.set_subtitle(value)

        self._set_bar(self._mem_bar, self._mem_lbl, info.mem_fraction, info.mem_label)
        self._set_bar(self._stor_bar, self._stor_lbl, info.storage_fraction, info.storage_label)

        if info.memory_type:
            self._mem_row.set_subtitle(info.memory_type)
        if info.storage_device_label:
            self._stor_row.set_subtitle(info.storage_device_label)

    @staticmethod
    def _set_bar(bar: Gtk.LevelBar | None, lbl: Gtk.Label | None,
                 fraction: float, text: str) -> None:
        if bar is None or lbl is None:
            return
        bar.set_value(min(1.0, max(0.0, fraction)))
        bar.remove_css_class("level-bar-warning")
        bar.remove_css_class("level-bar-critical")
        if fraction > 0.8:
            bar.add_css_class("level-bar-critical")
        elif fraction > 0.6:
            bar.add_css_class("level-bar-warning")
        lbl.set_label(text)

    # ── Actions ──

    @staticmethod
    def _current_branch() -> str:
        try:
            r = subprocess.run(
                ["git", "-C", os.environ.get("RETRO_DIR", "/opt/retrolinux"),
                 "rev-parse", "--abbrev-ref", "HEAD"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            return r.stdout.strip()
        except Exception:
            return ""

    @staticmethod
    def _branch_index(branch: str) -> int:
        return 1 if branch == "main" else 0

    def _on_branch_selected(self, _dd: Gtk.DropDown, _pspec) -> None:
        if self._branch_switching:
            return
        target = "main" if _dd.get_selected() == 1 else "develop"
        if target == self._current_branch():
            return
        self._confirm_switch_branch(target)

    def _confirm_switch_branch(self, target: str) -> None:
        current = self._current_branch() or "develop"

        def do_switch():
            self._branch_switching = True
            if self._branch_dd is not None:
                self._branch_dd.set_sensitive(False)
            threading.Thread(
                target=self._switch_branch, args=(target,), daemon=True
            ).start()

        confirm(
            self._window,
            heading=f"Switch to {target}?",
            body=(
                f"Retro Linux will move from {current} to {target} in "
                "$RETRO_DIR. Any uncommitted changes there will be discarded, "
                "and RETRO_BRANCH will be updated."
            ),
            label="Switch",
            on_confirm=do_switch,
            appearance=Adw.ResponseAppearance.SUGGESTED,
        )

    def _switch_branch(self, target: str) -> None:
        backup_ok, _backup_msg = self._create_backup(target)
        if backup_ok:
            self._finish_branch_switch(target)
        else:
            GLib.idle_add(self._ask_continue_without_backup, target)

    def _create_backup(self, target: str) -> tuple[bool, str]:
        try:
            r = subprocess.run(
                ["retro", "timeshift", "create", f"Pre-branch-switch: {target}"],
                capture_output=True, text=True, timeout=300, stdin=subprocess.DEVNULL,
            )
        except Exception as e:
            return False, str(e)
        return "CREATED" in (r.stdout + r.stderr), (r.stdout or r.stderr).strip()

    def _ask_continue_without_backup(self, target: str) -> None:
        dialog = Adw.AlertDialog(
            heading="Backup failed",
            body="Timeshift failed, no system backup was able to be made. "
                 "Do you want to continue switching branches anyway?",
        )
        dialog.add_response("cancel", "Abort")
        dialog.add_response("confirm", "Continue")
        dialog.set_response_appearance("confirm", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_response(_dialog, response):
            if response == "confirm":
                threading.Thread(
                    target=self._finish_branch_switch, args=(target,), daemon=True
                ).start()
            else:
                self._branch_switching = False
                if self._branch_dd is not None:
                    self._branch_dd.set_sensitive(True)
                    self._branch_dd.set_selected(self._branch_index(self._current_branch()))

        dialog.connect("response", on_response)
        dialog.present(self._window)

    def _finish_branch_switch(self, target: str) -> None:
        ok, msg = self._git_switch(target)
        GLib.idle_add(self._on_branch_switched, ok, msg)

    def _git_switch(self, target: str) -> tuple[bool, str]:
        """Delegate the switch to ``retro -b switch`` (single source of truth)."""
        try:
            r = subprocess.run(
                ["retro", "-b", "switch", target],
                capture_output=True, text=True, timeout=120,
                stdin=subprocess.DEVNULL,
            )
        except Exception as e:
            return False, str(e)
        out = (r.stdout or "").strip()
        if out.startswith("OK|"):
            return True, out[3:]
        reason = out
        if "reason=" in out:
            reason = out.split("reason=", 1)[-1]
        return False, reason or "Switch failed"

    def _on_branch_switched(self, ok: bool, msg: str) -> None:
        self._branch_switching = False
        if self._branch_dd is not None:
            self._branch_dd.set_sensitive(True)
        if ok:
            self._window.show_toast(f"Switched to {msg}")
            self._refresh_version_display()
            if msg == "develop":
                self._run_terminal(self._reinstall_command())
        else:
            if self._branch_dd is not None:
                self._branch_dd.set_selected(self._branch_index(self._current_branch()))
            self._window.show_toast(f"Switch failed: {msg}", timeout=8)

    def _refresh_version_display(self) -> None:
        branch = self._current_branch() or "develop"
        tag = ""
        try:
            r = subprocess.run(
                ["git", "-C", os.environ.get("RETRO_DIR", "/opt/retrolinux"),
                 "describe", "--tags", "--abbrev=0"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            tag = r.stdout.strip()
        except Exception:
            pass
        version = display_version(tag or "rolling-release")
        if self._version_lbl is not None:
            self._version_lbl.set_label(f"Version {version} ({branch})")
        if self._badge_lbl is not None:
            rolling = branch == "develop" or "nightly" in tag.lower()
            self._badge_lbl.set_label("Rolling Release" if rolling else "Stable Release")

    def _copy_specs(self) -> None:
        if self._info is None:
            self._window.show_toast("System info is still loading", timeout=2)
            return
        text = copy_specs_text(self._info)
        self._window.get_clipboard().set(text)
        self._window.show_toast("Specs copied to clipboard")

    def _open_repo(self) -> None:
        url = _repo_url()
        subprocess.Popen(
            ["xdg-open", url],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def _check_updates(self, interactive: bool = True) -> None:
        if self._check_btn is None:
            return
        if interactive:
            self._check_btn.set_label("Checking…")
            self._check_btn.set_sensitive(False)

        def worker():
            count = self._count_updates()
            GLib.idle_add(self._on_updates_checked, count, interactive)
        threading.Thread(target=worker, daemon=True).start()

    @staticmethod
    def _count_updates() -> int:
        """Count updates via ``retro -b updates`` (single source of truth)."""
        try:
            r = subprocess.run(
                ["retro", "-b", "updates"],
                capture_output=True, text=True, timeout=60,
                stdin=subprocess.DEVNULL,
            )
        except Exception:
            return -1
        for line in (r.stdout or "").splitlines():
            if line.startswith("count="):
                val = line[len("count="):]
                return int(val) if val.lstrip("-").isdigit() else -1
        return -1

    def _on_updates_checked(self, count: int, interactive: bool) -> None:
        self._updates_count = count
        if self._check_btn is None:
            return
        if interactive:
            self._check_btn.set_label("Check Updates")
            self._check_btn.set_sensitive(True)
            if count < 0:
                self._window.show_toast("Update check failed", timeout=5)
                return
            if count == 0:
                self._window.show_toast("System is up to date")
                return
            self._window.show_toast(f"{count} update{'s' if count != 1 else ''} available")

            def run_update():
                self._run_terminal("retro --update")

            confirm(
                self._window,
                heading=f"{count} update{'s' if count != 1 else ''} available",
                body="Would you like to update your system?",
                label="Update",
                on_confirm=run_update,
                appearance=Adw.ResponseAppearance.SUGGESTED,
            )
        else:
            if count > 0:
                self._check_btn.set_label(
                    f"{count} update{'s' if count != 1 else ''} available"
                )

    @staticmethod
    def _run_terminal(command: str) -> None:
        escaped = command.replace("'", "'\\''")
        cmd = f"kitty -- bash -c '{escaped}; echo; echo Press Enter to close.; read'"
        lua = f'hl.dsp.exec_cmd("{cmd}", {{ float = true, size = {{ 800, 500 }}, center = true }})'
        subprocess.Popen(
            ["hyprctl", "dispatch", lua],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    @staticmethod
    def _reinstall_command() -> str:
        from lib.python.variable import get_var
        install_type = get_var("RETRO_INSTALL", "complete")
        ricing = get_var("RETRO_RICING", "false")
        type_filter = "-t core" if install_type == "minimal" else "-t all"
        mode = "-m" if ricing == "true" else "-i"
        return (
            f"retro {mode} existing -a root {type_filter} -y && "
            f"retro {mode} existing -a user {type_filter} -y"
        )

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
            {"key": "about:overview", "label": "About Retro Linux",
             "description": "System specs, updates, logs, and repository links",
             "_group_id": "about", "_group_label": "About", "_section_label": "Overview"},
            {"key": "about:hardware", "label": "Hardware Info",
             "description": "Processor, graphics, memory, storage",
             "_group_id": "about", "_group_label": "About", "_section_label": "Hardware"},
            {"key": "about:software", "label": "Software Info",
             "description": "Kernel, compositor, uptime",
             "_group_id": "about", "_group_label": "About", "_section_label": "Software"},
        ]


__all__ = ["AboutPage"]
