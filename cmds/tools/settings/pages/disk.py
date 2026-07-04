"""Disk management page — health, usage, mounts, and setup."""

import os
import subprocess
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING

from gi.repository import Adw, Gdk, GLib, Gtk, cairo

from settings.ui import clear_children, make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_RETRO_DIR = os.environ.get("RETRO_DIR", "/opt/retrolinux")
_DISK_CORE = os.path.join(_RETRO_DIR, "scripts", "disk_core.sh")


@dataclass
class DiskInfo:
    device: str
    disk_type: str
    model: str
    size: str
    used_pct: str
    health: str
    temp: str
    mounts: str
    wear_pct: str


# ── Module-level sidebar updater (callable from window.py without building DiskPage) ──


def update_disk_sidebar(window, disks: list[DiskInfo]) -> None:
    """Update the sidebar Disks row with a usage LevelBar."""
    try:
        sidebar = getattr(window, "_sidebar", None)
        if sidebar is None:
            return
        row = sidebar._rows_by_id.get("disks")
        if row is None:
            return

        if not hasattr(row, "_disk_sidebar_bar"):
            bar = Gtk.LevelBar()
            bar.set_min_value(0)
            bar.set_max_value(100)
            bar.set_size_request(50, 6)
            bar.set_valign(Gtk.Align.CENTER)
            pct_lbl = Gtk.Label()
            pct_lbl.set_valign(Gtk.Align.CENTER)
            pct_lbl.add_css_class("caption")
            box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
            box.append(bar)
            box.append(pct_lbl)
            row.add_suffix(box)
            row._disk_sidebar_bar = bar
            row._disk_sidebar_pct = pct_lbl

        if disks:
            avg_pct = sum(float(d.used_pct.rstrip("%") or 0) for d in disks) / len(disks)
            row._disk_sidebar_bar.set_value(avg_pct)
            row._disk_sidebar_bar.remove_css_class("level-bar-critical")
            row._disk_sidebar_bar.remove_css_class("level-bar-warning")
            if avg_pct > 95:
                row._disk_sidebar_bar.add_css_class("level-bar-critical")
            elif avg_pct > 80:
                row._disk_sidebar_bar.add_css_class("level-bar-warning")
            row._disk_sidebar_pct.set_label(f"{avg_pct:.0f}%")
        else:
            row._disk_sidebar_bar.set_value(0)
            row._disk_sidebar_pct.set_label("")
    except Exception:
        pass


# ── I/O stats collection ──


class DiskIOStats:
    """Reads /sys/block/<dev>/stat and maintains a rolling rate buffer."""

    def __init__(self, device: str):
        self._stat_path = f"/sys/block/{device.split('/')[-1]}/stat"
        self._last_read = 0
        self._last_write = 0
        self._last_time = 0.0
        self.reads: list[float] = []
        self.writes: list[float] = []
        self._max_samples = 60

    def sample(self) -> None:
        try:
            with open(self._stat_path) as f:
                parts = f.read().strip().split()
            read_sectors = int(parts[2])
            write_sectors = int(parts[6])
        except (FileNotFoundError, IndexError, ValueError, OSError):
            return

        now = time.monotonic()
        if self._last_time > 0:
            dt = now - self._last_time
            if dt > 0:
                read_mb = (read_sectors - self._last_read) * 512 / (1024 * 1024)
                write_mb = (write_sectors - self._last_write) * 512 / (1024 * 1024)
                self.reads.append(read_mb / dt)
                self.writes.append(write_mb / dt)
                if len(self.reads) > self._max_samples:
                    self.reads.pop(0)
                    self.writes.pop(0)

        self._last_read = read_sectors
        self._last_write = write_sectors
        self._last_time = now

    def max_rate(self) -> float:
        all_vals = self.reads + self.writes
        return max(all_vals) if all_vals else 1.0

    def clear(self) -> None:
        self.reads.clear()
        self.writes.clear()
        self._last_read = 0
        self._last_write = 0
        self._last_time = 0.0


# ── I/O sparkline graph ──


class DiskIOGraph(Gtk.DrawingArea):
    """Live I/O read/write sparkline rendered with Cairo."""

    def __init__(self, device: str):
        super().__init__()
        self.set_hexpand(True)
        self.set_size_request(-1, 80)
        self.set_valign(Gtk.Align.FILL)

        self._stats = DiskIOStats(device)
        self.set_draw_func(self._on_draw)
        self.connect("destroy", self._on_destroy)

        self._timer = GLib.timeout_add(1000, self._tick)
        self._stats.sample()

    def _tick(self) -> bool:
        self._stats.sample()
        self.queue_draw()
        return True

    def _on_destroy(self, *_args) -> None:
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0

    def _on_draw(self, _da: Gtk.DrawingArea, cr: cairo.Context, w: int, h: int) -> None:
        if w < 10 or h < 10:
            return

        reads = self._stats.reads
        writes = self._stats.writes
        n = len(reads)
        if n < 2:
            self._draw_no_data(cr, w, h)
            return

        mx = self._stats.max_rate()
        if mx < 0.001:
            mx = 1.0

        # Transparent background
        cr.set_operator(cairo.Operator.CLEAR)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        margin = 4
        plot_w = w - 2 * margin
        plot_h = h - 2 * margin

        def scale_y(val: float) -> float:
            return margin + plot_h - (val / mx) * plot_h

        self._draw_line(cr, reads, margin, plot_w, scale_y,
                        Gdk.RGBA(0.3, 0.6, 1.0, 0.9))   # blue reads
        self._draw_line(cr, writes, margin, plot_w, scale_y,
                        Gdk.RGBA(1.0, 0.65, 0.1, 0.9))  # orange writes

        # Y-axis labels
        cr.set_font_size(8)
        cr.set_source_rgba(0.5, 0.5, 0.5, 0.6)
        for pct, label in [(0, "0"), (50, f"{mx/2:.0f}"), (100, f"{mx:.0f}")]:
            y = margin + plot_h - (pct / 100) * plot_h
            cr.move_to(margin + 2, y - 2)
            cr.show_text(f"{label} MB/s")

        # Current R/W speeds top-right
        cr.set_font_size(9)
        cur_r = reads[-1]
        cur_w = writes[-1]
        cr.set_source_rgba(0.3, 0.6, 1.0, 0.9)
        cr.move_to(self.get_width() - 110, 12)
        cr.show_text(f"R: {cur_r:.1f} MB/s")
        cr.set_source_rgba(1.0, 0.65, 0.1, 0.9)
        cr.move_to(self.get_width() - 110, 24)
        cr.show_text(f"W: {cur_w:.1f} MB/s")

    def _draw_no_data(self, cr, w, h):
        cr.set_source_rgba(0.5, 0.5, 0.5, 0.4)
        cr.set_font_size(10)
        cr.move_to(w / 2 - 30, h / 2)
        cr.show_text("Collecting\u2026")

    @staticmethod
    def _draw_line(cr, data, margin, plot_w, scale_y, color):
        n = len(data)
        if n < 2:
            return
        step = plot_w / (n - 1) if n > 1 else plot_w

        cr.set_source_rgba(color.red, color.green, color.blue, color.alpha)
        cr.set_line_width(1.5)
        cr.set_line_cap(1)  # ROUND
        cr.set_line_join(1)  # ROUND

        first = True
        for i in range(n):
            x = margin + i * step
            y = scale_y(data[i])
            if first:
                cr.move_to(x, y)
                first = False
            else:
                cr.line_to(x, y)
        cr.stroke()


# ── Main page ──


class DiskPage:
    """Disk management page with health info, mount actions, and setup toggles."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._refreshable_box: Gtk.Box
        self._disks: list[DiskInfo] = []

        self._last_automount = True
        self._last_btrfs_quota = False
        self._automount_row: Adw.SwitchRow
        self._btrfs_quota_row: Adw.SwitchRow
        self._refreshing = False
        self._tick_id = 0
        self._overview_widgets: dict = {}
        self._disk_widgets: list[dict] = []
        self._disk_config_dirty = False
        self._on_dirty_changed = None

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh disk information")
        refresh_btn.connect("clicked", lambda _b: self._refresh())
        header.pack_start(refresh_btn)

        mount_btn = Gtk.Button(icon_name="list-add-symbolic")
        mount_btn.set_tooltip_text("Mount a disk")
        mount_btn.connect("clicked", lambda _b: self._show_mount_dialog())
        header.pack_start(mount_btn)

        self._refreshable_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self._content_box.append(self._refreshable_box)

        self._load_data()
        self._rebuild_refreshable()
        self._update_sidebar()

        self._tick_id = GLib.timeout_add(10000, self._tick)

        return toolbar_view

    # ── Data loading ──

    def _load_data(self) -> None:
        self._disks = []
        try:
            result = subprocess.run(
                ["bash", _DISK_CORE, "--status"],
                capture_output=True, text=True, timeout=15,
                stdin=subprocess.DEVNULL,
            )
            if result.returncode == 0:
                for line in result.stdout.strip().splitlines():
                    if not line.strip():
                        continue
                    parts = line.split("|")
                    if len(parts) >= 9:
                        self._disks.append(DiskInfo(
                            device=parts[0], disk_type=parts[1], model=parts[2],
                            size=parts[3], used_pct=parts[4], health=parts[5],
                            temp=parts[6], mounts=parts[7], wear_pct=parts[8],
                        ))
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
        self._disks.sort(key=lambda d: 1 if "USB" in d.disk_type or "Removable" in d.disk_type else 0)
        self._load_setup_config()

    def _load_setup_config(self) -> None:
        try:
            result = subprocess.run(
                ["bash", _DISK_CORE, "--setup-get"],
                capture_output=True, text=True, timeout=10,
                stdin=subprocess.DEVNULL,
            )
            if result.returncode == 0:
                for line in result.stdout.strip().splitlines():
                    if line.startswith("automount="):
                        self._last_automount = line.split("=", 1)[1].strip() == "true"
                    elif line.startswith("btrfs_quota="):
                        self._last_btrfs_quota = line.split("=", 1)[1].strip() == "true"
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass

    # ── UI building ──

    def _refresh(self) -> None:
        self._overview_widgets = {}
        self._disk_widgets = []
        self._load_data()
        self._rebuild_refreshable()

    def _tick(self) -> bool:
        if self._refreshing:
            return True
        self._refreshing = True
        try:
            old_disks = self._disks[:]
            self._load_data()

            if self._structure_changed(old_disks, self._disks):
                self._rebuild_refreshable()
            else:
                self._update_values()

            self._update_sidebar()
        finally:
            self._refreshing = False
        return True

    @staticmethod
    def _structure_changed(old: list[DiskInfo], new: list[DiskInfo]) -> bool:
        if len(old) != len(new):
            return True
        for a, b in zip(old, new):
            if a.device != b.device:
                return True
            if a.mounts.strip() != b.mounts.strip():
                return True
        return False

    def _update_values(self) -> None:
        if not self._disks or not self._overview_widgets:
            return

        total_gb = 0.0
        used_sum = 0.0
        has_failed = any(d.health.strip() == "FAILED" for d in self._disks)
        for d in self._disks:
            raw = d.size.upper().rstrip("GGBT")
            try:
                if "T" in d.size.upper():
                    total_gb += float(raw) * 1024
                else:
                    total_gb += float(raw)
            except ValueError:
                total_gb += 0
            try:
                used_sum += float(d.used_pct.rstrip("%") or 0)
            except ValueError:
                used_sum += 0

        avg_used = used_sum / len(self._disks)
        cap_str = f"{total_gb:.0f} GB" if total_gb < 1024 else f"{total_gb / 1024:.1f} TB"
        self._overview_widgets["row"].set_title(f"Total Capacity  {cap_str}")
        self._overview_widgets["cap_label"].set_label(f"Used {avg_used:.0f}%")
        state = "Degraded" if has_failed else "Normal"
        self._overview_widgets["chip"].set_label(state)
        self._overview_widgets["chip"].remove_css_class("health-passed")
        self._overview_widgets["chip"].remove_css_class("health-failed")
        self._overview_widgets["chip"].add_css_class("health-failed" if has_failed else "health-passed")

        for i, disk in enumerate(self._disks):
            if i >= len(self._disk_widgets):
                break
            w = self._disk_widgets[i]
            w["expander"].set_title(disk.device)
            w["expander"].set_subtitle(f"{disk.model}  ({disk.size})")

            is_passed = disk.health.strip() == "PASSED"
            w["health_lbl"].set_label(disk.health.strip())
            w["health_lbl"].remove_css_class("health-passed")
            w["health_lbl"].remove_css_class("health-failed")
            w["health_lbl"].add_css_class("health-passed" if is_passed else "health-failed")
            w["health_icon"].set_from_icon_name(
                "emblem-ok-symbolic" if is_passed else "emblem-important-symbolic",
            )

            w["temp_lbl"].remove_css_class("health-passed")
            w["temp_lbl"].remove_css_class("health-warning")
            w["temp_lbl"].remove_css_class("health-failed")
            try:
                tv = float(disk.temp)
                w["temp_lbl"].set_label(f"{disk.temp}°C")
                cls = "health-passed" if tv <= 40 else ("health-warning" if tv <= 60 else "health-failed")
                w["temp_lbl"].add_css_class(cls)
            except ValueError:
                w["temp_lbl"].set_label(disk.temp)

            try:
                uv = float(disk.used_pct.rstrip("%"))
                w["used_bar"].set_value(uv)
                w["used_bar"].remove_css_class("level-bar-critical")
                w["used_bar"].remove_css_class("level-bar-warning")
                if uv > 95:
                    w["used_bar"].add_css_class("level-bar-critical")
                elif uv > 80:
                    w["used_bar"].add_css_class("level-bar-warning")
            except ValueError:
                w["used_bar"].set_value(0)
            w["used_pct_lbl"].set_label(disk.used_pct)

    def _update_sidebar(self) -> None:
        update_disk_sidebar(self._window, self._disks)

    def _rebuild_refreshable(self) -> None:
        self._overview_widgets = {}
        self._disk_widgets = []
        clear_children(self._refreshable_box)

        overview_group = Adw.PreferencesGroup(title="Overview")
        self._populate_overview(overview_group)
        self._refreshable_box.append(overview_group)

        disks_group = Adw.PreferencesGroup(title="Disks")
        self._populate_disks(disks_group)
        self._refreshable_box.append(disks_group)

        config_group = Adw.PreferencesGroup(title="Disk Configuration")
        self._populate_config(config_group)
        self._refreshable_box.append(config_group)

    def _populate_overview(self, group: Adw.PreferencesGroup) -> None:
        self._overview_widgets = {}
        if not self._disks:
            row = Adw.ActionRow(title="No disk information available")
            row.set_sensitive(False)
            group.add(row)
            return

        total_gb = 0.0
        used_sum = 0.0
        has_failed = any(d.health.strip() == "FAILED" for d in self._disks)

        for d in self._disks:
            raw = d.size.upper().rstrip("GGBT")
            try:
                if "T" in d.size.upper():
                    total_gb += float(raw) * 1024
                else:
                    total_gb += float(raw)
            except ValueError:
                total_gb += 0
            try:
                used_sum += float(d.used_pct.rstrip("%") or 0)
            except ValueError:
                used_sum += 0

        avg_used = used_sum / len(self._disks)
        cap_str = f"{total_gb:.0f} GB" if total_gb < 1024 else f"{total_gb / 1024:.1f} TB"

        overview_row = Adw.ActionRow(title=f"Total Capacity  {cap_str}")
        state_label = Gtk.Label(label=f"Used {avg_used:.0f}%")
        state_label.set_halign(Gtk.Align.END)
        state_label.set_opacity(0.7)
        overview_row.add_suffix(state_label)
        chip = Gtk.Label(label="Degraded" if has_failed else "Normal")
        if has_failed:
            chip.add_css_class("health-failed")
        else:
            chip.add_css_class("health-passed")
        chip.set_margin_start(8)
        overview_row.add_suffix(chip)
        group.add(overview_row)

        self._overview_widgets = {
            "row": overview_row,
            "cap_label": state_label,
            "chip": chip,
        }

    def _populate_disks(self, group: Adw.PreferencesGroup) -> None:
        self._disk_widgets = []
        for idx, disk in enumerate(self._disks):
            expander = Adw.ExpanderRow(
                title=disk.device,
                subtitle=f"{disk.model}  ({disk.size})",
            )
            if idx == 0:
                expander.set_expanded(True)

            # I/O Sparkline (first row)
            graph = DiskIOGraph(disk.device)
            graph_row = Adw.ActionRow()
            graph_row.set_activatable(False)
            graph_row.set_child(graph)
            expander.add_row(graph_row)

            # Partition info (name + encryption status)
            expander.add_row(self._info_row("Partitions", self._get_partition_info(disk.device)))

            # Serial number
            serial = self._get_serial(disk.device)
            if serial:
                expander.add_row(self._info_row("Serial", serial))

            health_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            health_icon = Gtk.Image.new_from_icon_name(
                "emblem-ok-symbolic" if disk.health.strip() == "PASSED"
                else "emblem-important-symbolic",
            )
            health_box.append(health_icon)
            health_lbl = Gtk.Label(label=disk.health.strip())
            if disk.health.strip() == "PASSED":
                health_lbl.add_css_class("health-passed")
            else:
                health_lbl.add_css_class("health-failed")
            health_box.append(health_lbl)
            wp = disk.wear_pct.strip().rstrip("%")
            has_wear = wp not in ("", "0", "N/A", "?")
            if has_wear:
                wear_lbl = Gtk.Label(label=f"  ({wp}% Wear)")
                wear_lbl.set_opacity(0.7)
                health_box.append(wear_lbl)
            else:
                wear_lbl = None
            health_row = self._info_row("Health", health_box)
            expander.add_row(health_row)

            try:
                tv = float(disk.temp)
                temp_lbl = Gtk.Label(label=f"{disk.temp}°C")
                if tv <= 40:
                    temp_lbl.add_css_class("health-passed")
                elif tv <= 60:
                    temp_lbl.add_css_class("health-warning")
                else:
                    temp_lbl.add_css_class("health-failed")
            except ValueError:
                temp_lbl = Gtk.Label(label=disk.temp)
            temp_lbl.set_halign(Gtk.Align.END)
            temp_row = self._info_row("Temperature", temp_lbl)
            expander.add_row(temp_row)

            used_bar = Gtk.LevelBar()
            used_bar.set_min_value(0)
            used_bar.set_max_value(100)
            used_bar.set_size_request(200, 8)
            try:
                uv = float(disk.used_pct.rstrip("%"))
                used_bar.set_value(uv)
                if uv > 95:
                    used_bar.add_css_class("level-bar-critical")
                elif uv > 80:
                    used_bar.add_css_class("level-bar-warning")
            except ValueError:
                used_bar.set_value(0)
            used_pct_lbl = Gtk.Label(label=disk.used_pct)

            used_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            used_box.append(used_bar)
            used_box.append(used_pct_lbl)
            expander.add_row(self._info_row("Used", used_box))

            self._populate_mounts(expander, disk)

            group.add(expander)

            self._disk_widgets.append({
                "expander": expander,
                "health_lbl": health_lbl,
                "temp_lbl": temp_lbl,
                "used_bar": used_bar,
                "used_pct_lbl": used_pct_lbl,
                "health_icon": health_icon,
                "wear_lbl": wear_lbl,
            })

    def _populate_mounts(self, expander: Adw.ExpanderRow, disk: DiskInfo) -> None:
        if not disk.mounts.strip():
            if "USB" in disk.disk_type or "Removable" in disk.disk_type:
                row = Adw.ActionRow(title="Not mounted")
                row.set_subtitle("Removable drive detected — no active mount points")
                mount_btn = Gtk.Button(label="Auto Mount")
                mount_btn.set_valign(Gtk.Align.CENTER)
                mount_btn.add_css_class("suggested-action")
                mount_btn.connect("clicked", lambda _b, d=disk.device: self._auto_mount(d))
                row.add_suffix(mount_btn)
                expander.add_row(row)
            else:
                expander.add_row(self._info_row("Mounts", "None"))
            return

        for mount in disk.mounts.split(","):
            mount = mount.strip()
            if not mount:
                continue
            row = Adw.ActionRow(title="Mount", subtitle=mount)
            btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

            open_btn = Gtk.Button(icon_name="folder-open-symbolic")
            open_btn.set_valign(Gtk.Align.CENTER)
            open_btn.set_tooltip_text(f"Open {mount}")
            open_btn.connect("clicked", lambda _b, p=mount: self._open_mount(p))
            btn_box.append(open_btn)

            if mount not in ("/", "/boot", "/home"):
                unmount_btn = Gtk.Button(icon_name="media-eject-symbolic")
                unmount_btn.set_valign(Gtk.Align.CENTER)
                unmount_btn.set_tooltip_text(f"Unmount {mount}")
                unmount_btn.connect("clicked", lambda _b, p=mount: self._unmount(p))
                btn_box.append(unmount_btn)

            row.add_suffix(btn_box)
            expander.add_row(row)

    # ── Save lifecycle (duck-typed SectionPage) ──

    def is_dirty(self) -> bool:
        return self._disk_config_dirty

    def mark_saved(self) -> None:
        if not self._disk_config_dirty:
            return
        automount = "true" if self._automount_row.get_active() else "false"
        quota = "true" if self._btrfs_quota_row.get_active() else "false"
        try:
            result = subprocess.run(
                ["bash", _DISK_CORE, "--set-vars",
                 f"automount={automount}", f"btrfs_quota={quota}"],
                capture_output=True, text=True, timeout=15,
                stdin=subprocess.DEVNULL,
            )
            if result.returncode == 0 and result.stdout.strip().startswith("OK|"):
                self._last_automount = self._automount_row.get_active()
                self._last_btrfs_quota = self._btrfs_quota_row.get_active()
                self._disk_config_dirty = False
        except Exception:
            pass

    def discard(self) -> None:
        self._automount_row.set_active(self._last_automount)
        self._btrfs_quota_row.set_active(self._last_btrfs_quota)
        self._disk_config_dirty = False

    def iter_pending_changes(self):
        if self._disk_config_dirty:
            from settings.core.pending import PendingChange
            yield PendingChange(
                category="Disk Config",
                title="Disk Setup",
                subtitle="Automount and BTRFS quota settings",
                navigate_to="disks",
                icon="drive-harddisk-symbolic",
                kind="modified",
                revert=self.discard,
            )

    def _on_toggle_changed(self, *_args) -> None:
        if (self._automount_row.get_active() != self._last_automount
                or self._btrfs_quota_row.get_active() != self._last_btrfs_quota):
            if not self._disk_config_dirty:
                self._disk_config_dirty = True
                if self._on_dirty_changed:
                    self._on_dirty_changed()
        elif self._disk_config_dirty:
            self._disk_config_dirty = False
            if self._on_dirty_changed:
                self._on_dirty_changed()

    def _populate_config(self, group: Adw.PreferencesGroup) -> None:
        self._automount_row = Adw.SwitchRow(
            title="Automount",
            subtitle="Automatically mount external drives on login",
        )
        self._automount_row.set_active(self._last_automount)
        self._automount_row.connect("notify::active", self._on_toggle_changed)
        group.add(self._automount_row)

        self._btrfs_quota_row = Adw.SwitchRow(
            title="BTRFS Quota",
            subtitle="Enable BTRFS quota tracking for usage monitoring",
        )
        self._btrfs_quota_row.set_active(self._last_btrfs_quota)
        self._btrfs_quota_row.connect("notify::active", self._on_toggle_changed)
        group.add(self._btrfs_quota_row)

    @staticmethod
    def _get_serial(device: str) -> str:
        try:
            result = subprocess.run(
                ["lsblk", "-dnlo", "SERIAL", f"/dev/{device.split('/')[-1]}"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            return result.stdout.strip()
        except Exception:
            return ""

    @staticmethod
    def _get_partition_info(device: str) -> str:
        dev = device.split("/")[-1]
        parts = []
        try:
            result = subprocess.run(
                ["lsblk", "-nlo", "NAME,FSTYPE", f"/dev/{dev}"],
                capture_output=True, text=True, timeout=10,
                stdin=subprocess.DEVNULL,
            )
            lines = [l.strip().split(None, 1) for l in result.stdout.strip().splitlines() if l.strip()]
            for s in lines:
                name = s[0]
                if name == dev:
                    continue  # skip the disk itself
                fstype = s[1] if len(s) > 1 else ""
                if fstype == "crypto_LUKS":
                    parts.append(f"{name} (encrypted)")
                elif fstype:
                    parts.append(f"{name}  ({fstype})")
                elif parts:
                    parts.append(name)
        except Exception:
            pass
        return ",  ".join(parts) if parts else ""

    @staticmethod
    def _info_row(title: str, content: str | Gtk.Widget) -> Adw.ActionRow:
        row = Adw.ActionRow(title=title)
        if isinstance(content, Gtk.Widget):
            row.add_suffix(content)
        else:
            lbl = Gtk.Label(label=content)
            lbl.set_halign(Gtk.Align.END)
            lbl.set_opacity(0.8)
            row.add_suffix(lbl)
        return row

    # ── Mount / Unmount ──

    def _show_mount_dialog(self) -> None:
        MountDialog(self._window, self._mount_cb).present(self._window)

    def _mount_cb(self, dev: str, path: str | None) -> None:
        self._mount(dev, path)

    def _auto_mount(self, dev: str) -> None:
        try:
            result = subprocess.run(
                ["lsblk", "-nlo", "NAME", f"/dev/{dev}"],
                capture_output=True, text=True, timeout=10,
                stdin=subprocess.DEVNULL,
            )
            parts = [l.strip() for l in result.stdout.strip().splitlines() if l.strip()]
            parts = parts[1:] if len(parts) > 1 else [dev]
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            parts = [dev]

        for part in parts:
            self._mount(part, None)

        GLib.timeout_add(1500, self._refresh)

    def _mount(self, dev: str, path: str | None) -> None:
        cmd = ["bash", _DISK_CORE, "--mount", dev]
        if path:
            cmd.append(path)
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
            lines = result.stdout.strip().splitlines()
            if result.returncode == 0 and any(l.startswith("OK|") for l in lines):
                self._window.show_toast(f"Mounted /dev/{dev}")
            else:
                self._window.show_toast(f"Mount failed", timeout=5)
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as e:
            self._window.show_toast(f"Mount failed — {e}", timeout=5)

    def _open_mount(self, mount_path: str) -> None:
        from lib.python.variable import get_var
        try:
            fm = get_var("RETRO_FILEMANAGER_CMD") or "nemo"
            subprocess.Popen(
                [fm, mount_path],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except Exception as e:
            self._window.show_toast(f"Cannot open file manager — {e}", timeout=5)

    def _unmount(self, mount_path: str) -> None:
        from settings.ui import confirm

        def do_unmount():
            try:
                result = subprocess.run(
                    ["bash", _DISK_CORE, "--umount", mount_path],
                    capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL,
                )
                lines = result.stdout.strip().splitlines()
                if result.returncode == 0 and any(l.startswith("OK|") for l in lines):
                    self._window.show_toast(f"Unmounted {mount_path}")
                    GLib.timeout_add(1400, self._refresh)
                else:
                    self._window.show_toast(f"Unmount failed", timeout=5)
            except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as e:
                self._window.show_toast(f"Unmount failed — {e}", timeout=5)

        confirm(
            self._window,
            heading="Unmount?",
            body=f"Are you sure you want to unmount {mount_path}?",
            label="Unmount",
            on_confirm=do_unmount,
        )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "disks:status", "label": "Disk Status",
             "description": "Overview of storage capacity and health",
             "_group_id": "disks", "_group_label": "Disks", "_section_label": "Overview"},
            {"key": "disks:health", "label": "SMART Health",
             "description": "Per-disk health, temperature, and wear level",
             "_group_id": "disks", "_group_label": "Disks", "_section_label": "Disks"},
            {"key": "disks:automount", "label": "Automount",
             "description": "Automatically mount external drives on login",
             "_group_id": "disks", "_group_label": "Disks", "_section_label": "Disk Configuration"},
            {"key": "disks:btrfs_quota", "label": "BTRFS Quota",
             "description": "Enable BTRFS quota tracking for usage monitoring",
             "_group_id": "disks", "_group_label": "Disks", "_section_label": "Disk Configuration"},
        ]


class MountDialog(Adw.Dialog):
    """Proper Adw.Dialog for mounting a disk (matches window rules dialog pattern)."""

    def __init__(self, window: "RetroSettingsWindow", on_mount):
        super().__init__()
        self._window = window
        self._on_mount = on_mount
        self._devices: list[str] = []
        self.set_title("Mount a Disk")
        self.set_content_width(450)
        self.set_content_height(200)

        toolbar_view = Adw.ToolbarView()
        header = Adw.HeaderBar()

        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _b: self.close())
        header.pack_start(cancel_btn)

        self._mount_btn = Gtk.Button(label="Mount")
        self._mount_btn.add_css_class("suggested-action")
        self._mount_btn.connect("clicked", lambda _b: self._do_mount())
        self._mount_btn.set_sensitive(False)
        header.pack_end(self._mount_btn)

        toolbar_view.add_top_bar(header)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(450)
        clamp.set_tightening_threshold(400)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        group = Adw.PreferencesGroup()
        self._build_device_list()
        model = Gtk.StringList.new([d["label"] for d in self._devices])

        dev_row = Adw.ActionRow(title="Device")
        dropdown = Gtk.DropDown(model=model)
        dropdown.set_selected(Gtk.INVALID_LIST_POSITION)
        dropdown.connect("notify::selected", self._on_device_selected)
        dev_row.add_suffix(dropdown)
        self._dev_dropdown = dropdown
        group.add(dev_row)

        self._path_entry = Adw.EntryRow(title="Mount path (optional)")
        self._path_entry.set_show_apply_button(False)
        group.add(self._path_entry)

        box.append(group)
        clamp.set_child(box)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(clamp)
        scrolled.set_vexpand(True)

        toolbar_view.set_content(scrolled)
        self.set_child(toolbar_view)

    def _build_device_list(self) -> None:
        self._devices = []
        try:
            result = subprocess.run(
                ["bash", _DISK_CORE, "--list"],
                capture_output=True, text=True, timeout=10,
                stdin=subprocess.DEVNULL,
            )
            if result.returncode == 0:
                for line in result.stdout.strip().splitlines():
                    parts = line.split("|")
                    if len(parts) >= 4:
                        name = parts[0]
                        size = parts[1]
                        model = parts[2]
                        label = f"{name}  \u2014  {model}  ({size})"
                        self._devices.append({"dev": name, "label": label})
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
        if not self._devices:
            self._devices.append({"dev": "", "label": "No devices found"})

    def _on_device_selected(self, dropdown: Gtk.DropDown, _pspec) -> None:
        idx = dropdown.get_selected()
        self._mount_btn.set_sensitive(
            0 <= idx < len(self._devices) and bool(self._devices[idx]["dev"])
        )

    def _do_mount(self) -> None:
        idx = self._dev_dropdown.get_selected()
        if 0 <= idx < len(self._devices):
            dev = self._devices[idx]["dev"]
            path = self._path_entry.get_text().strip()
            if dev:
                self.close()
                self._on_mount(dev, path or None)
