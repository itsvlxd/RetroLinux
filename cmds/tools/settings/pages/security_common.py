"""Shared helpers for the Firewall / SSH / Faillock security pages.

Common privileged runners (``_run``, ``_can_sudo``), the service-preset
table, the traffic-graph classes, and :class:`SecurityPageBase` which
provides the no-op dirty lifecycle the window expects plus the
``_pkexec``/``_run_ssh`` privileged action runners. The three dedicated
pages inherit from the base and only implement their own widgets, reload
and handlers.
"""

import os
import subprocess
import threading
import time
from collections.abc import Iterable

from gi.repository import GLib, Gtk, cairo

from settings.core.pending import PendingChange

_FIREWALL_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "firewall_core.sh")
_SSH_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "ssh_core.sh")


def _run(script: str, args: list[str]) -> str:
    try:
        r = subprocess.run(
            ["sudo", "-n", script, *args],
            capture_output=True, text=True, timeout=15,
            stdin=subprocess.DEVNULL,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except Exception:
        pass
    try:
        r = subprocess.run(
            ["bash", script, *args],
            capture_output=True, text=True, timeout=15,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _can_sudo() -> bool:
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


def _remove_rows(group, rows: list) -> None:
    """Remove tracked rows from a PreferencesGroup.

    Adw.PreferencesGroup wraps added rows in an inner Gtk.ListBox, so
    ``row.get_parent()`` is the ListBox, never the group. Removing from
    the actual parent guarantees rows don't pile up on refresh.
    """
    for row in rows:
        parent = row.get_parent()
        if parent is not None:
            parent.remove(row)


SERVICES = [
    ("SSH", "22", "tcp"),
    ("HTTP", "80", "tcp"),
    ("HTTPS", "443", "tcp"),
    ("DNS", "53", "udp"),
    ("SMB", "445", "tcp"),
    ("RDP", "3389", "tcp"),
    ("VNC", "5900", "tcp"),
]

SERVICE_PORTS = {name: (port, proto) for name, port, proto in SERVICES}

SERVICE_NAMES = ["Custom", *(name for name, _p, _pr in SERVICES)]


class FirewallTrafficStats:
    """Reads RX/TX bytes, in/out connections, and blocked packets into rolling buffers."""

    def __init__(self):
        self.rx_mbps: list[float] = []
        self.tx_mbps: list[float] = []
        self.conn_in: list[float] = []
        self.conn_out: list[float] = []
        self.blocked: list[float] = []
        self._last_rx = 0
        self._last_tx = 0
        self._last_blocked = 0
        self._last_time = 0.0
        self._max_samples = 60

    def _read_counters(self):
        rx = tx = 0
        try:
            with open("/proc/net/dev") as f:
                for line in f:
                    if ":" not in line:
                        continue
                    iface, rest = line.split(":", 1)
                    if iface.strip() == "lo":
                        continue
                    parts = rest.split()
                    if len(parts) >= 9:
                        rx += int(parts[0])
                        tx += int(parts[8])
        except (OSError, ValueError, IndexError):
            pass
        return rx, tx

    def _read_blocked(self) -> int:
        try:
            data = _run(_FIREWALL_CORE, ["--status"])
            for line in data.splitlines():
                if line.startswith("blocked_packets="):
                    return int(line.split("=", 1)[1] or 0)
        except (ValueError, OSError):
            pass
        return 0

    def _read_conns(self):
        inc = out = 0
        try:
            r = subprocess.run(
                ["ss", "-tn", "state", "established"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            for line in r.stdout.splitlines():
                fields = line.split()
                if len(fields) < 4:
                    continue
                local = fields[2]
                port = local.rsplit(":", 1)[-1]
                if not port.isdigit():
                    continue
                if int(port) < 32768:
                    inc += 1
                else:
                    out += 1
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
        return inc, out

    def sample(self) -> None:
        rx, tx = self._read_counters()
        inc, out = self._read_conns()
        blocked = self._read_blocked()
        now = time.monotonic()
        if self._last_time > 0:
            dt = now - self._last_time
            if dt > 0:
                self.rx_mbps.append((rx - self._last_rx) * 8 / (dt * 1e6))
                self.tx_mbps.append((tx - self._last_tx) * 8 / (dt * 1e6))
                self.conn_in.append(float(inc))
                self.conn_out.append(float(out))
                self.blocked.append(float(blocked - self._last_blocked))
                for buf in (self.rx_mbps, self.tx_mbps, self.conn_in, self.conn_out, self.blocked):
                    if len(buf) > self._max_samples:
                        buf.pop(0)
        self._last_rx = rx
        self._last_tx = tx
        self._last_blocked = blocked
        self._last_time = now

    def max_rate(self) -> float:
        all_vals = self.rx_mbps + self.tx_mbps
        return max(all_vals) if all_vals else 1.0


class FirewallTrafficGraph(Gtk.DrawingArea):
    """Live RX/TX throughput + in/out connection counts on a single sparkline."""

    def __init__(self) -> None:
        super().__init__()
        self.set_hexpand(True)
        self.set_size_request(-1, 170)
        self.set_valign(Gtk.Align.FILL)

        self._stats = FirewallTrafficStats()
        self.set_draw_func(self._on_draw)
        self.connect("destroy", self._on_destroy)

        self._timer = 0

    def start(self) -> None:
        if self._timer == 0:
            self._stats.sample()
            self._timer = GLib.timeout_add(1000, self._tick)

    def stop(self) -> None:
        if self._timer != 0:
            GLib.source_remove(self._timer)
            self._timer = 0

    def _tick(self) -> bool:
        self._stats.sample()
        self.queue_draw()
        return True

    def _on_destroy(self, *_args) -> None:
        self.stop()

    def _on_draw(self, _da, cr, w, h) -> None:
        if w < 10 or h < 10:
            return
        st = self._stats
        if len(st.rx_mbps) < 2:
            cr.set_operator(cairo.Operator.CLEAR)
            cr.paint()
            cr.set_operator(cairo.Operator.OVER)
            cr.set_source_rgba(0.5, 0.5, 0.5, 0.4)
            cr.set_font_size(10)
            cr.move_to(w / 2 - 40, h / 2)
            cr.show_text("Collecting traffic\u2026")
            return

        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        rx_c = (0.3, 0.6, 1.0, 0.95)
        tx_c = (1.0, 0.65, 0.1, 0.95)
        in_c = (0.2, 1.0, 0.5, 0.95)
        out_c = (1.0, 0.33, 0.7, 0.95)
        blk_c = (1.0, 0.2, 0.2, 0.95)

        lines = [
            (st.rx_mbps, rx_c, "RX"),
            (st.tx_mbps, tx_c, "TX"),
            (st.blocked, blk_c, "BLK"),
            (st.conn_in, in_c, "In"),
            (st.conn_out, out_c, "Out"),
        ]

        margin_t, margin_b = 8, 16
        margin_l, margin_r = 8, 110
        plot_w = w - margin_l - margin_r
        plot_h = h - margin_t - margin_b
        if plot_w <= 0 or plot_h <= 0:
            return

        for data, _color, _label in lines:
            if not data:
                continue
            mx = max(data)
            if mx < 0.001:
                continue
            n = len(data)
            if n < 2:
                continue
            step = plot_w / (n - 1)
            cr.set_source_rgba(*_color)
            cr.set_line_width(1.3)
            cr.set_line_cap(1)
            cr.set_line_join(1)
            cr.move_to(margin_l, margin_t + plot_h - (data[0] / mx) * plot_h)
            for i in range(1, n):
                cr.line_to(margin_l + i * step, margin_t + plot_h - (data[i] / mx) * plot_h)
            cr.stroke()

        cr.set_font_size(9)
        y_pos = margin_t + 4
        rx_cur = st.rx_mbps[-1] if st.rx_mbps else 0
        tx_cur = st.tx_mbps[-1] if st.tx_mbps else 0
        in_cur = int(st.conn_in[-1]) if st.conn_in else 0
        out_cur = int(st.conn_out[-1]) if st.conn_out else 0
        blk_cur = int(st.blocked[-1]) if st.blocked else 0
        for color, label, text in [
            (rx_c, "RX", f"{rx_cur:.2f} Mb/s"),
            (tx_c, "TX", f"{tx_cur:.2f} Mb/s"),
            (blk_c, "BLK", f"{blk_cur} pkts"),
            (in_c, "IN", f"{in_cur} conns"),
            (out_c, "OUT", f"{out_cur} conns"),
        ]:
            cr.set_source_rgba(*color)
            cr.move_to(w - margin_r + 4, y_pos)
            cr.show_text(f"{label}: {text}")
            y_pos += 16


class SecurityPageBase:
    """Common scaffolding for the Firewall / SSH / Faillock pages.

    Provides the privileged action runner (``_pkexec``) and the no-op
    lifecycle the window expects from standalone pages. Subclasses set
    ``self._applying`` to suppress handler echoes during state application
    and implement ``_reload()`` to refresh their own slice of data.
    """

    def __init__(self, window):
        self._window = window
        self._can_sudo = _can_sudo()
        self._applying = False
        self._dirty = False
        self._on_dirty_changed = None

    def _pkexec(self, script: str, args: list[str], success: str, refresh: bool = False, extra_args: list | None = None) -> None:
        self._window.show_toast("Applying\u2026", timeout=3)

        def worker():
            cmds = [["sudo", "-n", script, *args]]
            for e_script, e_args in extra_args or []:
                cmds.append(["sudo", "-n", e_script, *e_args])
            try:
                r = subprocess.run(cmds[0], capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
            except Exception as e:
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=str(e), timeout=6))
                return
            out = (r.stdout or "") + (r.stderr or "")
            err = (r.stderr or "").lower()
            sudo_failed = ("password" in err or "not permitted" in err or
                           "not in the sudoers" in err or "no password was provided" in err)
            ok = (r.returncode == 0 or "OK|" in out) and not sudo_failed
            if ok:
                for c in cmds[1:]:
                    try:
                        subprocess.run(c, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
                    except Exception:
                        pass
                GLib.idle_add(lambda: self._window.show_toast(success, timeout=4))
                if refresh:
                    GLib.idle_add(self._reload)
                return

            if not sudo_failed:
                tail = "\n".join(out.strip().splitlines()[-8:])
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=tail or str(r.returncode), timeout=8))
                if refresh:
                    GLib.idle_add(self._reload)
                return

            full_cmds = [["pkexec", "bash", script, *args]]
            for e_script, e_args in extra_args or []:
                full_cmds.append(["pkexec", "bash", e_script, *e_args])
            try:
                r = subprocess.run(full_cmds[0], capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
            except Exception as e:
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=str(e), timeout=6))
                return
            out = (r.stdout or "") + (r.stderr or "")
            ok = r.returncode == 0 or "OK|" in out
            if ok:
                for c in full_cmds[1:]:
                    try:
                        subprocess.run(c, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
                    except Exception:
                        pass
                GLib.idle_add(lambda: self._window.show_toast(success, timeout=4))
            else:
                tail = "\n".join(out.strip().splitlines()[-8:])
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=tail or str(r.returncode), timeout=8))
            if refresh:
                GLib.idle_add(self._reload)

        threading.Thread(target=worker, daemon=True).start()

    def _run_ssh(self, args: list[str], success: str) -> None:
        self._pkexec(_SSH_CORE, args, success, refresh=True)

    def _reload(self) -> None:
        """Refresh the page's data. Overridden by each subclass."""

    def on_shown(self) -> None:
        """Called when the page becomes the visible child. Override as needed."""

    def on_hidden(self) -> None:
        """Called when the page stops being the visible child. Override as needed."""

    # ── Lifecycle (no-op for these read-mostly pages) ──

    def missing_count(self) -> int:
        return 0

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        self._dirty = False

    def discard(self) -> None:
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return iter(())

    def flush_pending(self) -> None:
        pass

    def destroy(self) -> None:
        pass