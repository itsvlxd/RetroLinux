"""QuickShare page — native Android Quick Share (Nearby Share) receiver.

Read-only page (never dirty): controls the native Quick Share daemon
(scripts/python/quickshare_receive.py, vendored protocol engine in
lib/python/quickshare) that makes this machine discoverable to Android's
built-in Quick Share over Wi-Fi. It shows the daemon state (ACTIVE/INACTIVE,
PID, uptime) with Start/Stop/Restart buttons, the download folder,
auto-accept and start-at-login toggles, a live transfers table with
cancel buttons, and a device-picker dialog for sending files.

Everything is backed by ``scripts/quickshare_core.sh``; errors are surfaced
with toasts and logged to ``/tmp/retro_logs/quickshare.log``.
"""

import json
import os
import signal
import socket
import subprocess
import threading
import time
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk, Pango

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_RETRO_DIR = os.environ.get("RETRO_DIR", "/opt/retrolinux")
_QS_CORE = os.path.join(_RETRO_DIR, "scripts", "quickshare_core.sh")
_QS_TRANSFERS = "/tmp/retro_logs/quickshare_transfers.json"
_QS_SEND_TRANSFERS = "/tmp/retro_logs/quickshare_send_transfers.json"

_DEVICE_ICONS = {
    "PHONE": "phone-symbolic",
    "FOLDABLE": "phone-symbolic",
    "TABLET": "computer-symbolic",
    "LAPTOP": "computer-symbolic",
}


def _device_icon(dtype: str) -> str:
    return _DEVICE_ICONS.get(dtype.upper(), "network-transmit-receive-symbolic")


def _device_type_label(dtype: str) -> str:
    return {
        "PHONE": "Phone",
        "FOLDABLE": "Phone",
        "TABLET": "Tablet",
        "LAPTOP": "PC",
    }.get(dtype.upper(), "Other")


def _human_size(n) -> str:
    try:
        n = float(n)
    except (TypeError, ValueError):
        return "?"
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024 or unit == "T":
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024
    return f"{n}B"


def _qs(args: list[str], timeout: int = 10) -> str:
    try:
        r = subprocess.run(
            ["bash", _QS_CORE, *args],
            capture_output=True, text=True, timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _friendly_send_reason(reason: str) -> str:
    return {
        "receiver_canceled": "the receiving device stopped the transfer",
        "canceled": "the transfer was canceled",
        "REJECT": "the device declined \u2014 accept the transfer on that device",
        "bad_target": "the receiving device is no longer reachable",
        "file_not_found": "the selected file was not found",
    }.get(reason, reason or "unknown error")


def _pid_alive(pid) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ProcessLookupError, ValueError, TypeError):
        return False


def _is_stale_send(t: dict, now: float) -> bool:
    if t.get("done"):
        result = t.get("result")
        if result and result != "ok":
            return bool(t.get("finished_at")) and now - t["finished_at"] > 3
        return False
    return not _pid_alive(t.get("pid"))


def _rewrite_send_transfers(entries: list[dict]) -> None:
    try:
        os.makedirs(os.path.dirname(_QS_SEND_TRANSFERS), exist_ok=True)
        tmp = _QS_SEND_TRANSFERS + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"transfers": entries}, f)
        os.replace(tmp, _QS_SEND_TRANSFERS)
    except Exception:
        pass


class QuickSharePage:
    """Android Quick Share receiver — read-only action page."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._on_dirty_changed = None
        self._status: dict[str, str] = {}
        self._setting_value = False
        self._tick_source = None
        self._transfers_tick_source = None
        self._transfers_group: Adw.PreferencesGroup | None = None
        self._transfers_listbox: Gtk.ListBox | None = None
        self._send_seq = 0
        self._send_transfers: dict[int, dict] = {}
        self._send_procs: dict[int, subprocess.Popen] = {}
        self._send_cancelled: set[int] = set()

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        send_btn = Gtk.Button(icon_name="document-send-symbolic")
        send_btn.set_tooltip_text("Send a File")
        send_btn.connect("clicked", lambda _b: self._send_file())
        header.pack_start(send_btn)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh")
        refresh_btn.connect("clicked", lambda _b: self._reload())
        header.pack_start(refresh_btn)

        self._content_box.append(self._build_status_group())
        self._content_box.append(self._build_transfers_group())

        self._reload()
        self._tick_source = GLib.timeout_add(5000, self._tick)
        self._transfers_tick_source = GLib.timeout_add(1000, self._transfers_tick)
        return toolbar_view

    def _build_status_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup(title="QuickShare Configuration")

        self._enabled_sw = Adw.SwitchRow(
            title="Enable QuickShare",
            subtitle="Start Quick Share automatically and keep it running",
        )
        self._enabled_sw.connect("notify::active", self._on_enabled)
        group.add(self._enabled_sw)

        self._switch = Adw.SwitchRow(
            title="Android Quick Share",
            subtitle="Make this device discoverable to Android Quick Share",
        )
        self._switch.connect("notify::active", self._on_switch)
        group.add(self._switch)

        self._dir_row = Adw.ActionRow(title="Download folder", subtitle="—")
        dir_btn = Gtk.Button(icon_name="folder-symbolic")
        dir_btn.set_valign(Gtk.Align.CENTER)
        dir_btn.set_tooltip_text("Choose download folder")
        dir_btn.connect("clicked", lambda _b: self._pick_dir())
        self._dir_row.add_suffix(dir_btn)
        group.add(self._dir_row)

        self._autoaccept_sw = Adw.SwitchRow(
            title="Auto-accept transfers",
            subtitle="Accept incoming files without a confirmation prompt",
        )
        self._autoaccept_sw.connect("notify::active", self._on_autoaccept)
        group.add(self._autoaccept_sw)

        return group

    def _build_transfers_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup(title="Transfers")
        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        listbox.add_css_class("boxed-list")
        group.add(listbox)
        self._transfers_group = group
        self._transfers_listbox = listbox
        group.set_visible(False)
        return group

    def _transfers_tick(self) -> bool:
        threading.Thread(target=self._transfers_worker, daemon=True).start()
        return True

    def _transfers_worker(self) -> None:
        raw: list[dict] = []
        offers: list[dict] = []
        send_raw: list[dict] = []
        try:
            if os.path.isfile(_QS_TRANSFERS):
                with open(_QS_TRANSFERS) as f:
                    data = json.load(f)
                raw = data.get("transfers", [])
                offers = data.get("offers", [])
            if os.path.isfile(_QS_SEND_TRANSFERS):
                with open(_QS_SEND_TRANSFERS) as f:
                    sdata = json.load(f)
                send_raw = sdata.get("transfers", [])
        except Exception:
            raw = []
        now = time.time()
        cleaned = [t for t in send_raw if not _is_stale_send(t, now)]
        if len(cleaned) != len(send_raw):
            _rewrite_send_transfers(cleaned)
            send_raw = cleaned
        if _qs(["--status"]).split("|", 1)[0] != "running":
            raw = [t for t in raw if t.get("done")]
        GLib.idle_add(self._render_transfers, raw, offers, send_raw)

    def _render_transfers(self, daemon_transfers: list[dict], offers: list[dict] | None = None,
                          send_transfers: list[dict] | None = None) -> None:
        if self._transfers_listbox is None or self._transfers_group is None:
            return
        lb = self._transfers_listbox

        merged = list(daemon_transfers)
        own_pids = {t.get("pid") for t in self._send_transfers.values() if t.get("pid")}
        for t in (send_transfers or []):
            if t.get("pid") in own_pids:
                continue
            if not t.get("done") or t.get("finished_at"):
                merged.append(t)
        merged.extend(list(self._send_transfers.values()))
        offer_rows = offers or []

        while child := lb.get_first_child():
            lb.remove(child)

        if not merged and not offer_rows:
            self._transfers_group.set_visible(False)
            return

        for o in offer_rows:
            lb.append(self._build_offer_row(o))
        for t in merged:
            lb.append(self._build_transfer_row(t))
        self._transfers_group.set_visible(True)

    def _build_offer_row(self, o: dict) -> Gtk.ListBoxRow:
        pin = o.get("pin", "—")
        files = o.get("files", [])
        names = ", ".join(f.get("name", "?") for f in files)
        oid = o.get("id")

        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(8)
        box.set_margin_end(8)

        img = Gtk.Image.new_from_icon_name("network-transmit-receive-symbolic")
        img.set_pixel_size(20)
        img.set_valign(Gtk.Align.CENTER)
        box.append(img)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text_box.set_hexpand(True)

        title_lbl = Gtk.Label(label="Incoming transfer")
        title_lbl.set_halign(Gtk.Align.START)
        title_lbl.add_css_class("caption")
        title_lbl.set_opacity(0.8)
        text_box.append(title_lbl)

        name_lbl = Gtk.Label(label=names)
        name_lbl.set_halign(Gtk.Align.START)
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        text_box.append(name_lbl)

        pin_lbl = Gtk.Label(label=f"PIN: {pin}")
        pin_lbl.set_halign(Gtk.Align.START)
        pin_lbl.add_css_class("dim-label")
        pin_lbl.add_css_class("caption")
        text_box.append(pin_lbl)

        box.append(text_box)

        accept_btn = Gtk.Button(label="Accept")
        accept_btn.add_css_class("suggested-action")
        accept_btn.set_valign(Gtk.Align.CENTER)
        accept_btn.connect("clicked", lambda _b, oid=oid: self._accept_offer(oid, "accept"))
        box.append(accept_btn)

        deny_btn = Gtk.Button(label="Deny")
        deny_btn.set_valign(Gtk.Align.CENTER)
        deny_btn.connect("clicked", lambda _b, oid=oid: self._accept_offer(oid, "deny"))
        box.append(deny_btn)

        row.set_child(box)
        return row

    def _accept_offer(self, offer_id, decision: str) -> None:
        res = _qs(["--accept-offer", str(offer_id), decision])
        self._window.show_toast(
            "Incoming transfer accepted" if decision == "accept" else "Incoming transfer declined"
        )

    def _build_transfer_row(self, t: dict) -> Gtk.ListBoxRow:
        size = t.get("size", 0) or 0
        done = bool(t.get("done", False))
        if t.get("pct") is not None:
            pct = max(0, min(100, int(t.get("pct") or 0)))
            bytes_done = int(size * pct / 100) if size else 0
        else:
            bytes_done = t.get("bytes", 0) or 0
            pct = int(bytes_done * 100 / size) if size else 0
        if done:
            pct = 100
            bytes_done = size

        direction = t.get("direction", "receive")
        icon = "go-down-symbolic" if direction == "receive" else "go-up-symbolic"

        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(8)
        box.set_margin_end(8)

        img = Gtk.Image.new_from_icon_name(icon)
        img.set_pixel_size(20)
        img.set_valign(Gtk.Align.CENTER)
        box.append(img)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text_box.set_hexpand(True)

        name_lbl = Gtk.Label(label=t.get("file", "?"))
        name_lbl.set_halign(Gtk.Align.START)
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        text_box.append(name_lbl)

        prog = Gtk.ProgressBar()
        prog.set_fraction(pct / 100.0)
        prog.set_show_text(True)
        prog.set_text(f"{pct}%")
        text_box.append(prog)

        size_lbl = Gtk.Label(
            label=f"{'Receiving' if direction == 'receive' else 'Sending'}  \u00b7  {_human_size(bytes_done)} / {_human_size(size)}"
        )
        size_lbl.set_halign(Gtk.Align.START)
        size_lbl.add_css_class("dim-label")
        size_lbl.add_css_class("caption")
        text_box.append(size_lbl)

        box.append(text_box)

        if done:
            if direction == "receive" and t.get("dest"):
                open_btn = Gtk.Button(label="Open")
                open_btn.set_valign(Gtk.Align.CENTER)
                open_btn.connect("clicked", lambda _b, tr=t: self._open_transfer(tr))
                box.append(open_btn)
            close_btn = Gtk.Button(icon_name="window-close-symbolic")
            close_btn.set_valign(Gtk.Align.CENTER)
            close_btn.set_tooltip_text("Dismiss")
            close_btn.connect("clicked", lambda _b, tr=t: self._close_transfer(tr))
            box.append(close_btn)
        else:
            cancel_btn = Gtk.Button(icon_name="process-stop-symbolic")
            cancel_btn.set_valign(Gtk.Align.CENTER)
            cancel_btn.set_tooltip_text("Cancel transfer")
            cancel_btn.connect("clicked", lambda _b, tr=t: self._cancel_transfer(tr))
            box.append(cancel_btn)

        row.set_child(box)
        return row

    def _open_transfer(self, t: dict) -> None:
        dest = t.get("dest")
        if dest and os.path.isfile(dest):
            subprocess.Popen(
                ["xdg-open", dest],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        else:
            self._window.show_toast("File no longer exists", timeout=5)

    def _close_transfer(self, t: dict) -> None:
        direction = t.get("direction", "receive")
        if direction == "send":
            seq = int(t.get("seq") or 0)
            spid = int(t.get("pid") or 0)
            self._send_cancelled.add(seq)
            proc = self._send_procs.pop(seq, None)
            if proc is not None and proc.poll() is None:
                proc.terminate()
            self._send_transfers.pop(seq, None)
            if spid:
                _qs(["--clear-send", str(spid)])
        else:
            tid = t.get("id")
            if tid is not None:
                _qs(["--clear-transfer", str(tid)])

    def _cancel_transfer(self, t: dict) -> None:
        direction = t.get("direction", "receive")
        if direction == "send":
            seq = int(t.get("seq") or 0)
            if seq:
                self._send_cancelled.add(seq)
                proc = self._send_procs.get(seq)
                if proc is not None and proc.poll() is None:
                    try:
                        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                    except (OSError, ProcessLookupError):
                        try:
                            proc.terminate()
                        except Exception:
                            pass

                    def _force_kill():
                        time.sleep(1.5)
                        try:
                            if proc.poll() is None:
                                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                        except (OSError, ProcessLookupError):
                            pass

                    threading.Thread(target=_force_kill, daemon=True).start()
                self._send_transfers.pop(seq, None)
                self._send_procs.pop(seq, None)
            else:
                spid = int(t.get("pid") or 0)
                if spid:
                    # Only signal the send process itself — it shares the
                    # shell's process group, so killpg would nuke the shell.
                    try:
                        os.kill(spid, signal.SIGTERM)
                    except (OSError, ProcessLookupError):
                        pass
            self._window.show_toast("Send canceled")
        else:
            tid = t.get("id")
            if tid is not None:
                _qs(["--cancel-receive", str(tid)])
            self._window.show_toast("Canceling transfer\u2026")

    # ── Data loading ──

    def _reload(self) -> None:
        self._load_status()

    def _load_status(self) -> None:
        out = _qs(["--status"])
        parts = out.split("|")
        while len(parts) < 5:
            parts.append("")
        state, dl_dir, autostart, pid, autoaccept = parts[0], parts[1], parts[2], parts[3], parts[4]
        self._status = {
            "state": state, "dir": dl_dir,
            "autostart": autostart, "pid": pid, "autoaccept": autoaccept,
        }
        self._render_status()

    def _render_status(self) -> None:
        running = self._status.get("state") == "running"

        self._setting_value = True
        self._switch.set_active(running)
        self._autoaccept_sw.set_active(self._status.get("autoaccept") == "true")
        if hasattr(self, "_enabled_sw"):
            self._enabled_sw.set_active(_qs(["--enabled-status"]).strip() != "false")
        self._setting_value = False
        self._dir_row.set_subtitle(self._status.get("dir", "—") or "—")

    def _tick(self) -> bool:
        threading.Thread(target=self._tick_worker, daemon=True).start()
        return True

    def _tick_worker(self) -> None:
        try:
            out = _qs(["--status"])
            GLib.idle_add(self._apply_status, out)
        except Exception:
            pass

    def _apply_status(self, out: str) -> None:
        parts = out.split("|")
        while len(parts) < 5:
            parts.append("")
        self._status = {
            "state": parts[0], "dir": parts[1],
            "autostart": parts[2], "pid": parts[3], "autoaccept": parts[4],
        }
        self._render_status()

    # ── Actions ──

    def _on_switch(self, sw: Adw.SwitchRow, _pspec) -> None:
        if self._setting_value:
            return
        res = _qs(["--start"] if sw.get_active() else ["--stop"])
        if res.startswith("OK"):
            self._window.show_toast(
                "Quick Share enabled" if sw.get_active() else "Quick Share disabled"
            )
        else:
            self._window.show_bug_toast(
                "Failed to toggle Quick Share", detail=res or "unknown error", timeout=5,
            )
            sw.set_active(not sw.get_active())
        self._reload()

    def _on_autoaccept(self, sw: Adw.SwitchRow, _pspec) -> None:
        if self._setting_value:
            return
        state = "on" if sw.get_active() else "off"
        res = _qs(["--auto-accept", state])
        if res.startswith("OK"):
            self._window.show_toast(
                f"Auto-accept {'enabled' if sw.get_active() else 'disabled'}"
            )
        else:
            self._window.show_bug_toast(
                "Failed to set auto-accept", detail=res or "unknown error", timeout=5,
            )
            sw.set_active(not sw.get_active())
        self._reload()

    def _on_enabled(self, sw: Adw.SwitchRow, _pspec) -> None:
        if self._setting_value:
            return
        state = "on" if sw.get_active() else "off"
        res = _qs(["--set-enabled", state])
        if res.startswith("OK"):
            self._window.show_toast(
                f"Keep-alive {'enabled' if sw.get_active() else 'disabled'}"
            )
        else:
            self._window.show_bug_toast(
                "Failed to set keep-alive", detail=res or "unknown error", timeout=5,
            )
            sw.set_active(not sw.get_active())
        self._reload()

    def _pick_dir(self) -> None:
        def do_pick():
            res = _qs(["--set-dir-interactive"], timeout=600)
            if res.startswith("OK"):
                dir_path = res.split("|", 1)[1]
                GLib.idle_add(lambda: self._window.show_toast(f"Download folder set to {dir_path}"))
            else:
                reason = "canceled" if "canceled" in res else (res or "unknown error")
                GLib.idle_add(lambda: self._window.show_toast(f"Folder picker {reason}", timeout=5))
            GLib.idle_add(self._reload)
        threading.Thread(target=do_pick, daemon=True).start()

    def _send_file(self) -> None:
        self._show_device_picker()

    def _show_device_picker(self) -> None:
        dialog = Adw.Dialog()
        dialog.set_title("Send via Quick Share")
        dialog.set_content_width(520)
        dialog.set_content_height(460)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        refresh_btn = Gtk.Button(label="Refresh")
        refresh_btn.set_tooltip_text("Re-scan for nearby devices")
        header.pack_start(refresh_btn)
        toolbar.add_top_bar(header)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(520)
        clamp.set_tightening_threshold(420)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)
        box.set_margin_start(8)
        box.set_margin_end(8)

        info_lbl = Gtk.Label(label="Scanning for nearby devices\u2026")
        info_lbl.set_halign(Gtk.Align.START)
        info_lbl.add_css_class("dim-label")
        box.append(info_lbl)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        listbox.set_vexpand(True)
        listbox.add_css_class("boxed-list")

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(listbox)
        scrolled.set_vexpand(True)
        frame = Gtk.Frame()
        frame.set_child(scrolled)
        box.append(frame)

        clamp.set_child(box)
        scrolled2 = Gtk.ScrolledWindow()
        scrolled2.set_child(clamp)
        scrolled2.set_vexpand(True)
        toolbar.set_content(scrolled2)
        dialog.set_child(toolbar)

        def apply(raw: str) -> None:
            while child := listbox.get_first_child():
                listbox.remove(child)
            local_name = socket.gethostname().lower()
            count = 0
            for line in raw.splitlines():
                p = line.split("|")
                if len(p) < 4:
                    continue
                name, addr, port, dtype = p[0], p[1], p[2], p[3]
                if not name:
                    continue
                if name.lower() == local_name:
                    continue
                count += 1

                row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
                row_box.set_margin_top(6)
                row_box.set_margin_bottom(6)
                row_box.set_margin_start(8)
                row_box.set_margin_end(8)

                img = Gtk.Image.new_from_icon_name(_device_icon(dtype))
                img.set_pixel_size(24)
                img.set_valign(Gtk.Align.CENTER)
                row_box.append(img)

                text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
                text_box.set_hexpand(True)
                n_lbl = Gtk.Label(label=name)
                n_lbl.set_halign(Gtk.Align.START)
                n_lbl.set_ellipsize(Pango.EllipsizeMode.END)
                text_box.append(n_lbl)
                m_lbl = Gtk.Label(label=f"{addr}:{port}, {_device_type_label(dtype)}")
                m_lbl.set_halign(Gtk.Align.START)
                m_lbl.add_css_class("dim-label")
                m_lbl.add_css_class("caption")
                text_box.append(m_lbl)
                row_box.append(text_box)

                send_btn = Gtk.Button(label="Send")
                send_btn.add_css_class("suggested-action")
                send_btn.set_valign(Gtk.Align.CENTER)
                send_btn.connect(
                    "clicked",
                    lambda _b, a=addr, pt=port, n=name: (
                        dialog.close(),
                        self._choose_file_and_send(a, pt, n),
                    ),
                )
                row_box.append(send_btn)

                row = Gtk.ListBoxRow()
                row.set_child(row_box)
                listbox.append(row)

            info_lbl.set_label(
                f"{count} device{'s' if count != 1 else ''} found"
                if count
                else "No devices found \u2014 check your phone's Quick Share visibility"
            )
            if not listbox.get_first_child():
                empty_lbl = Gtk.Label(label="No nearby devices")
                empty_lbl.set_margin_top(16)
                empty_lbl.set_margin_bottom(16)
                empty_lbl.set_halign(Gtk.Align.CENTER)
                empty_lbl.add_css_class("dim-label")
                row = Gtk.ListBoxRow()
                row.set_child(empty_lbl)
                listbox.append(row)

        def refresh_list():
            info_lbl.set_label("Scanning for nearby devices\u2026")

            def worker():
                raw = _qs(["--scan"])
                GLib.idle_add(lambda: apply(raw))

            threading.Thread(target=worker, daemon=True).start()
            return True

        refresh_btn.connect("clicked", lambda _b: refresh_list())
        refresh_list()
        source = GLib.timeout_add(6000, refresh_list)

        def _on_dialog_closed(_d):
            try:
                GLib.source_remove(source)
            except Exception:
                pass

        dialog.connect("closed", _on_dialog_closed)
        dialog.present(self._window)

    def _choose_file_and_send(self, addr: str, port: str, name: str) -> None:
        def worker():
            res = _qs(["--pick-file"], timeout=600)
            if res.startswith("OK|"):
                file_path = res.split("|", 1)[1]
                if not os.path.isfile(file_path):
                    GLib.idle_add(
                        lambda: self._window.show_toast("Selected file not found", timeout=5)
                    )
                    return
                GLib.idle_add(
                    lambda: self._window.show_toast(f"Sending to {name}\u2026")
                )
                GLib.idle_add(lambda: self._do_send(addr, port, file_path, name))
            else:
                GLib.idle_add(
                    lambda: self._window.show_toast("File selection canceled")
                )

        threading.Thread(target=worker, daemon=True).start()

    def _do_send(self, addr: str, port: str, file_path: str, name: str) -> None:
        self._send_seq += 1
        seq = self._send_seq
        size = os.path.getsize(file_path) if os.path.isfile(file_path) else 0
        self._send_transfers[seq] = {
            "seq": seq,
            "file": os.path.basename(file_path),
            "size": size,
            "bytes": 0,
            "pct": 0,
            "direction": "send",
            "done": False,
        }

        def do_send():
            proc = None
            try:
                proc = subprocess.Popen(
                    ["bash", _QS_CORE, "--send", addr, port, file_path],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, start_new_session=True,
                )
                self._send_procs[seq] = proc
                self._send_transfers[seq]["pid"] = proc.pid
                assert proc.stdout is not None
                last_pct = -1
                for line in proc.stdout:
                    line = line.strip()
                    if not line:
                        continue
                    if line.startswith("WAITING"):
                        GLib.idle_add(
                            lambda: self._window.show_toast(f"Connecting to {name}\u2026")
                        )
                    elif line.startswith("PIN|"):
                        pin = line.split("|", 1)[1]
                        GLib.idle_add(
                            lambda: self._window.show_toast(
                                f"Confirm code {pin} matches your phone"
                            )
                        )
                    elif line.startswith("PROGRESS|"):
                        try:
                            pct = int(line.split("|")[1])
                        except (ValueError, IndexError):
                            continue
                        self._send_transfers[seq] = {
                            "seq": seq,
                            "file": os.path.basename(file_path),
                            "size": size,
                            "bytes": int(size * pct / 100) if size else 0,
                            "pct": pct,
                            "direction": "send",
                            "done": False,
                        }
                        if pct >= last_pct + 25 and pct in (25, 50, 75, 100):
                            last_pct = pct
                            GLib.idle_add(
                                lambda pct=pct: self._window.show_toast(
                                    f"Sending to {name}\u2026 {pct}%"
                                )
                            )
                    elif line.startswith("OK|"):
                        if seq in self._send_cancelled:
                            break
                        self._send_transfers[seq] = {
                            "seq": seq,
                            "file": os.path.basename(file_path),
                            "size": size,
                            "bytes": size,
                            "pct": 100,
                            "direction": "send",
                            "done": True,
                        }
                        elapsed = line.split("|", 1)[1]
                        GLib.idle_add(
                            lambda: self._window.show_toast(
                                f"Sent to {name} in {elapsed}s"
                            )
                        )
                    elif line.startswith("ERR|"):
                        if seq in self._send_cancelled:
                            break
                        self._send_transfers[seq] = {
                            "seq": seq,
                            "file": os.path.basename(file_path),
                            "size": size,
                            "bytes": 0,
                            "pct": 0,
                            "direction": "send",
                            "done": True,
                        }
                        reason = line.split("|", 1)[1] if "|" in line else "failed"
                        GLib.idle_add(
                            lambda: self._window.show_toast(
                                f"Send failed \u2014 {_friendly_send_reason(reason)}", timeout=5
                            )
                        )
                proc.wait()
            except Exception as e:
                if seq not in self._send_cancelled:
                    self._send_transfers[seq] = {
                        "seq": seq,
                        "file": os.path.basename(file_path),
                        "size": size,
                        "bytes": 0,
                        "pct": 0,
                        "direction": "send",
                        "done": True,
                    }
                    GLib.idle_add(
                        lambda: self._window.show_toast(f"Send failed ({e})", timeout=5)
                    )
            finally:
                self._send_procs.pop(seq, None)
                self._send_cancelled.discard(seq)

        threading.Thread(target=do_send, daemon=True).start()

    # ── Lifecycle (read-only) ──

    def is_dirty(self) -> bool:
        return False

    def mark_saved(self) -> None:
        pass

    def discard(self) -> None:
        pass

    def destroy(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None
        if self._transfers_tick_source:
            GLib.source_remove(self._transfers_tick_source)
            self._transfers_tick_source = None

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return ()

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "quickshare:overview", "label": "Android Quick Share",
             "description": "Receive files from Android Quick Share (Nearby Share)",
             "_group_id": "quickshare", "_group_label": "System", "_section_label": "Overview"},
            {"key": "quickshare:status", "label": "Quick Share",
             "description": "Enable or disable the Quick Share receiver",
             "_group_id": "quickshare", "_group_label": "System", "_section_label": "Status"},
            {"key": "quickshare:transfers", "label": "Transfers",
             "description": "Current file transfers, progress and cancel",
             "_group_id": "quickshare", "_group_label": "System", "_section_label": "Status"},
            {"key": "quickshare:dir", "label": "Download Folder",
             "description": "Choose where received Quick Share files are saved",
             "_group_id": "quickshare", "_group_label": "System", "_section_label": "Status"},
            {"key": "quickshare:autoaccept", "label": "Auto-accept Transfers",
             "description": "Accept incoming Quick Share files without prompting",
             "_group_id": "quickshare", "_group_label": "System", "_section_label": "Status"},
            {"key": "quickshare:enabled", "label": "Quick Share Enabled",
             "description": "Auto-restart the Quick Share receiver if it stops",
             "_group_id": "quickshare", "_group_label": "System", "_section_label": "Status"},
            {"key": "quickshare:send", "label": "Send a File",
             "description": "Send files to a nearby Android Quick Share device",
             "_group_id": "quickshare", "_group_label": "System", "_section_label": "Actions"},
        ]


__all__ = ["QuickSharePage"]
