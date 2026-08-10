"""Wallpaper selection page — grid with thumbnails."""

import os
import subprocess
import threading
from pathlib import Path

from gi.repository import Adw, GdkPixbuf, GLib, Gtk

from lib.python.variable import get_var, get_module_default
from settings.ui import make_page_layout
from settings.ui.row_actions import RowActions

FRAME_CACHE = Path.home() / ".config" / "retro" / "wallpaper_frames"
WALLPAPER_CORE = Path(os.environ.get("RETRO_DIR", "")) / "scripts" / "wallpaper_core.sh"


def _list_wallpapers(collection: str | None = None) -> list[dict]:
    current = get_var("WALL_CURRENT", "")
    wall_dir = Path.home() / ".config" / "retro" / "wallpapers"
    if collection is None:
        collection = get_var("RETRO_WALL_COLLECTION", "retro")

    res_map: dict[str, str] = {}
    result = subprocess.run(
        ["bash", str(WALLPAPER_CORE), "--list-with-res", collection or ""],
        capture_output=True, text=True, timeout=15,
    )
    for line in result.stdout.strip().split("\n"):
        if "|" not in line:
            continue
        name, res = line.split("|", 1)
        res_map[name] = res

    search_root = wall_dir / collection if collection and collection != "all" else wall_dir
    wallpapers = []
    for f in sorted(FRAME_CACHE.glob("*.png")):
        orig_name = f.name[:-4]
        matches = list(search_root.rglob(orig_name))
        if not matches:
            continue
        full_path = str(matches[0])
        res = res_map.get(orig_name, "?")
        if res == "?":
            continue
        is_video = orig_name.endswith((".mp4", ".mkv", ".webm"))
        display = Path(orig_name).stem.replace("-", " ").title()
        tags = f'{display.lower()} {"live" if is_video else "static"} {res}'
        wallpapers.append({
            "name": display,
            "path": full_path,
            "orig_name": orig_name,
            "thumb": str(f),
            "active": orig_name == os.path.basename(current),
            "type": "live" if is_video else "static",
            "resolution": res,
            "_search_tags": tags,
        })
    wallpapers.sort(key=lambda w: (0 if w["active"] else 1, w["name"]))
    return wallpapers


def _set_wallpaper(path: str) -> bool:
    result = subprocess.run(
        ["bash", str(WALLPAPER_CORE), "--set", path],
        capture_output=True, text=True, timeout=15,
    )
    return result.stdout.strip().startswith("OK")


def _rename_wallpaper(old_path: str, new_stem: str) -> bool:
    old = Path(old_path)
    if not old.exists():
        return False
    new_stem = new_stem.strip()
    if not new_stem:
        return False
    ext = old.suffix
    new_name = f"{new_stem}{ext}"
    new_path = old.parent / new_name
    if new_path.exists():
        return False
    old.rename(new_path)

    thumb = FRAME_CACHE / f"{old.name}.png"
    if thumb.is_symlink() or thumb.exists():
        new_thumb = FRAME_CACHE / f"{new_name}.png"
        if thumb.is_symlink():
            thumb.unlink()
            os.symlink(str(new_path), str(new_thumb))
        else:
            thumb.rename(new_thumb)

    for c in FRAME_CACHE.glob(f"{old.name}.colors*"):
        new_c = FRAME_CACHE / c.name.replace(old.name, new_name)
        c.rename(new_c)
    return True


def _delete_wallpaper(path: str) -> bool:
    p = Path(path)
    if not p.exists():
        return False
    for f in FRAME_CACHE.glob(f"{p.name}*"):
        f.unlink()
    p.unlink()
    return True


class WallpapersPage:
    def __init__(self, window):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._flow_box = None
        self._search_entry = None
        self._all_wallpapers: list[dict] = []
        self._search_term = ""
        self._dirty = False
        self._notify_dirty = lambda: None
        self._pending_static: bool | None = None
        self._pending_static_bat: bool | None = None
        self._pending_collection: str | None = None
        self._pending_slideshow: bool | None = None
        self._pending_interval: int | None = None
        self._pending_res_map: str | None = None
        self._collections: list[str] = []
        self._needs_opt = False
        self._static_row: Gtk.Widget | None = None
        self._bat_row: Gtk.Widget | None = None
        self._col_row: Gtk.Widget | None = None
        self._col_delete_btn: Gtk.Widget | None = None
        repo_walls = Path(os.environ.get("RETRO_DIR", "")) / "wallpapers"
        self._repo_collections: list[str] = []
        if repo_walls.is_dir():
            self._repo_collections = [p.name for p in repo_walls.iterdir() if p.is_dir()]
        self._slide_row: Gtk.Widget | None = None
        self._interval_row: Gtk.Widget | None = None
        self._res_row: Gtk.Widget | None = None
        self._static_switch: Gtk.Widget | None = None
        self._bat_switch: Gtk.Widget | None = None
        self._slide_switch: Gtk.Widget | None = None
        self._interval_spin: Gtk.SpinButton | None = None
        self._spin_w: Gtk.SpinButton | None = None
        self._spin_h: Gtk.SpinButton | None = None
        self._opt_row: Adw.ActionRow | None = None
        self._gpu_row: Gtk.Widget | None = None
        self._pending_gpu: str | None = None
        self._gpu_modes: list[str] = []
        self._setting_value = False
        self._static_actions: RowActions | None = None
        self._bat_actions: RowActions | None = None
        self._col_actions: RowActions | None = None
        self._slide_actions: RowActions | None = None
        self._interval_actions: RowActions | None = None
        self._res_actions: RowActions | None = None
        self._gpu_actions: RowActions | None = None

    def _refresh_managed(self) -> None:
        for row, var, actions in (
            (self._static_row, "WALL_STATIC_FORCED", self._static_actions),
            (self._bat_row, "WALL_STATIC_ON_BAT", self._bat_actions),
            (self._col_row, "RETRO_WALL_COLLECTION", self._col_actions),
            (self._slide_row, "WALL_SLIDESHOW_ACTIVE", self._slide_actions),
            (self._interval_row, "WALL_SLIDESHOW_INTERVAL", self._interval_actions),
            (self._res_row, "WALL_RES_MAP", self._res_actions),
            (self._gpu_row, "WALL_GPU_OFFLOAD", self._gpu_actions),
        ):
            if row is None or actions is None:
                continue
            live = get_var(var, "")
            default = get_module_default(var)
            if not default:
                default = live
            effective = self._pending_for(var, live)
            is_managed = effective != default
            is_dirty = self._has_pending(var)
            is_saved = live != default
            actions.update(is_managed=is_managed, is_dirty=is_dirty, is_saved=is_saved)

    def _pending_for(self, var_name: str, fallback: str = "") -> str:
        val = self._get_pending(var_name)
        return val if val is not None else fallback

    def _get_pending(self, var_name: str) -> str | None:
        if var_name == "WALL_STATIC_FORCED":
            if self._pending_static is None:
                return None
            return "true" if self._pending_static else "false"
        if var_name == "WALL_STATIC_ON_BAT":
            if self._pending_static_bat is None:
                return None
            return "true" if self._pending_static_bat else "false"
        if var_name == "RETRO_WALL_COLLECTION":
            return self._pending_collection
        if var_name == "WALL_SLIDESHOW_ACTIVE":
            if self._pending_slideshow is None:
                return None
            return "true" if self._pending_slideshow else "false"
        if var_name == "WALL_SLIDESHOW_INTERVAL":
            return str(self._pending_interval) if self._pending_interval is not None else None
        if var_name == "WALL_RES_MAP":
            return self._pending_res_map
        if var_name == "WALL_GPU_OFFLOAD":
            return self._pending_gpu
        return None

    def _has_pending(self, var_name: str) -> bool:
        if var_name == "WALL_STATIC_FORCED":
            return self._pending_static is not None
        if var_name == "WALL_STATIC_ON_BAT":
            return self._pending_static_bat is not None
        if var_name == "RETRO_WALL_COLLECTION":
            return self._pending_collection is not None
        if var_name == "WALL_SLIDESHOW_ACTIVE":
            return self._pending_slideshow is not None
        if var_name == "WALL_SLIDESHOW_INTERVAL":
            return self._pending_interval is not None
        if var_name == "WALL_RES_MAP":
            return self._pending_res_map is not None
        if var_name == "WALL_GPU_OFFLOAD":
            return self._pending_gpu is not None
        return False

    def _set_pending(self, var_name: str, value: str):
        if var_name == "WALL_STATIC_FORCED":
            self._pending_static = value == "true"
        elif var_name == "WALL_STATIC_ON_BAT":
            self._pending_static_bat = value == "true"
        elif var_name == "RETRO_WALL_COLLECTION":
            self._pending_collection = value
        elif var_name == "WALL_SLIDESHOW_ACTIVE":
            self._pending_slideshow = value == "true"
        elif var_name == "WALL_SLIDESHOW_INTERVAL":
            self._pending_interval = int(value) if value.isdigit() else None  # type: ignore[arg-type]
        elif var_name == "WALL_RES_MAP":
            self._pending_res_map = value
        elif var_name == "WALL_GPU_OFFLOAD":
            self._pending_gpu = value

    def _clear_pending(self, var_name: str):
        if var_name == "WALL_STATIC_FORCED":
            self._pending_static = None
        elif var_name == "WALL_STATIC_ON_BAT":
            self._pending_static_bat = None
        elif var_name == "RETRO_WALL_COLLECTION":
            self._pending_collection = None
        elif var_name == "WALL_SLIDESHOW_ACTIVE":
            self._pending_slideshow = None
        elif var_name == "WALL_SLIDESHOW_INTERVAL":
            self._pending_interval = None
        elif var_name == "WALL_RES_MAP":
            self._pending_res_map = None
        elif var_name == "WALL_GPU_OFFLOAD":
            self._pending_gpu = None

    def _set_widget_value(self, var_name: str, value: str):
        self._setting_value = True
        if var_name == "WALL_STATIC_FORCED":
            if self._static_switch is not None:
                self._static_switch.set_active(value == "true")  # type: ignore[union-attr]
        elif var_name == "WALL_STATIC_ON_BAT":
            if self._bat_switch is not None:
                self._bat_switch.set_active(value == "true")  # type: ignore[union-attr]
        elif var_name == "RETRO_WALL_COLLECTION":
            def_val = value
            if self._col_row is not None and def_val in self._collections:
                self._col_row.set_selected(self._collections.index(def_val))  # type: ignore[union-attr]
        elif var_name == "WALL_SLIDESHOW_ACTIVE":
            if self._slide_switch is not None:
                self._slide_switch.set_active(value == "true")  # type: ignore[union-attr]
        elif var_name == "WALL_SLIDESHOW_INTERVAL":
            if self._interval_spin is not None and value.isdigit():
                self._interval_spin.set_value(float(value))
        elif var_name == "WALL_RES_MAP":
            w, h = (value.split("x") + ["1920", "1080"])[:2]
            if self._spin_w is not None:
                self._spin_w.set_value(float(w))
            if self._spin_h is not None:
                self._spin_h.set_value(float(h))
        elif var_name == "WALL_GPU_OFFLOAD":
            if self._gpu_row is not None and value in self._gpu_modes:
                self._gpu_row.set_selected(self._gpu_modes.index(value))  # type: ignore[union-attr]
        self._setting_value = False

    def _discard_var(self, var_name: str):
        live = get_var(var_name, get_module_default(var_name))
        self._set_widget_value(var_name, live)
        self._clear_pending(var_name)
        self._check_dirty()
        self._refresh_managed()

    def _reset_var(self, var_name: str):
        default = get_module_default(var_name)
        self._set_widget_value(var_name, default)
        self._set_pending(var_name, default)
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _check_dirty(self):
        any_dirty = any(
            self._has_pending(v)
            for v in (
                "WALL_STATIC_FORCED", "WALL_STATIC_ON_BAT", "RETRO_WALL_COLLECTION",
                "WALL_SLIDESHOW_ACTIVE", "WALL_SLIDESHOW_INTERVAL", "WALL_RES_MAP",
                "WALL_GPU_OFFLOAD",
            )
        )
        if any_dirty != self._dirty:
            self._dirty = any_dirty
            if not any_dirty:
                self._notify_dirty()

    def _parse_res(self, res_str: str) -> tuple[int, int]:
        try:
            s = res_str.rsplit("|", 1)[-1] if "|" in res_str else res_str
            if "x" in s:
                parts = s.split("x")
                return int(parts[0]), int(parts[1])
        except (ValueError, IndexError):
            pass
        return 0, 0

    def _check_needs_optimization(self) -> bool:
        target = get_var("WALL_RES_MAP", "")
        tw, th = self._parse_res(target)
        if tw == 0 or th == 0:
            return False
        for wp in self._all_wallpapers:
            w, h = self._parse_res(wp.get("resolution", ""))
            if w > tw or h > th:
                return True
        return False

    def needs_optimization(self) -> bool:
        return self._needs_opt

    def _refresh_opt_banner(self):
        if self._opt_row is None:
            return
        self._needs_opt = self._check_needs_optimization()
        self._opt_row.set_visible(self._needs_opt)

    def _on_sync(self, _btn):
        self._window.show_toast("Syncing wallpapers\u2026", timeout=5)
        proc = subprocess.Popen(
            ["retro", "wallpaper", "sync"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        GLib.child_watch_add(proc.pid, lambda *_: (
            self._window.show_toast("Sync complete", timeout=2),
            self._refresh(),
        ))

    def _on_optimize_clicked(self):
        proc = subprocess.Popen(
            ["retro", "wallpaper", "optimize"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self._window.show_toast("Optimizing wallpapers\u2026", timeout=3)
        GLib.child_watch_add(proc.pid, lambda *_: (self._refresh(), self._notify_dirty()))

    def build(self, header: Adw.HeaderBar | None = None) -> Gtk.Widget:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)

        if header:
            sync_btn = Gtk.Button(icon_name="view-refresh-symbolic")
            sync_btn.set_tooltip_text("Sync from repository")
            sync_btn.add_css_class("flat")
            sync_btn.connect("clicked", self._on_sync)
            header.pack_start(sync_btn)

            new_col_btn = Gtk.Button(icon_name="folder-pictures-symbolic")
            new_col_btn.set_tooltip_text("New collection\u2026")
            new_col_btn.add_css_class("flat")
            new_col_btn.connect("clicked", self._on_new_collection)
            header.pack_start(new_col_btn)

            add_btn = Gtk.Button(icon_name="list-add-symbolic")
            add_btn.set_tooltip_text("Add wallpapers\u2026")
            add_btn.add_css_class("flat")
            add_btn.connect("clicked", self._on_add)
            header.pack_start(add_btn)

        pref_group = Adw.PreferencesGroup()

        # Optimization warning row (shown when wallpapers exceed target res)
        self._opt_row = Adw.ActionRow(
            title="Wallpapers Not Optimized",
            subtitle="Some wallpapers exceed the target resolution. Optimize them to reduce power usage and improve performance.",
        )
        self._opt_row.add_css_class("warning-row")
        opt_icon = Gtk.Image.new_from_icon_name("dialog-warning-symbolic")
        opt_icon.set_valign(Gtk.Align.CENTER)
        self._opt_row.add_prefix(opt_icon)
        opt_btn = Gtk.Button(label="Optimize")
        opt_btn.add_css_class("suggested-action")
        opt_btn.set_valign(Gtk.Align.CENTER)
        opt_btn.connect("clicked", lambda *_: self._on_optimize_clicked())
        self._opt_row.add_suffix(opt_btn)
        self._opt_row.set_visible(False)
        pref_group.add(self._opt_row)

        # Settings — Force Static Wallpaper
        static_row = Adw.SwitchRow(title="Force Static Wallpaper")
        static_row.set_subtitle("Forces all wallpapers to run in static mode")
        static_row.set_active(get_var("WALL_STATIC_FORCED", "false") == "true")
        static_row.connect("notify::active", self._on_static_toggled)
        self._static_actions = RowActions(
            static_row,
            on_discard=lambda: self._discard_var("WALL_STATIC_FORCED"),
            on_reset=lambda: self._reset_var("WALL_STATIC_FORCED"),
        )
        static_row.add_suffix(self._static_actions.box)
        self._static_actions.reorder_first()
        pref_group.add(static_row)
        self._static_row = static_row
        self._static_switch = static_row

        bat_row = Adw.SwitchRow(title="Static on Battery")
        bat_row.set_subtitle("Switches to static wallpapers when on battery power")
        bat_row.set_active(get_var("WALL_STATIC_ON_BAT", "false") == "true")
        bat_row.connect("notify::active", self._on_static_bat_toggled)
        self._bat_actions = RowActions(
            bat_row,
            on_discard=lambda: self._discard_var("WALL_STATIC_ON_BAT"),
            on_reset=lambda: self._reset_var("WALL_STATIC_ON_BAT"),
        )
        bat_row.add_suffix(self._bat_actions.box)
        self._bat_actions.reorder_first()
        pref_group.add(bat_row)
        self._bat_row = bat_row
        self._bat_switch = bat_row

        col_result = subprocess.run(
            ["bash", str(WALLPAPER_CORE), "--collection", "list"],
            capture_output=True, text=True, timeout=10,
        )
        collections = [l.strip() for l in col_result.stdout.split("\n") if l.strip()]
        collections.sort()
        collections.insert(0, "all")
        self._collections = collections
        col_display = [c[0].upper() + c[1:] if c else c for c in collections]
        col_model = Gtk.StringList.new(col_display)
        current_col = get_var("RETRO_WALL_COLLECTION", "retro")
        col_idx = collections.index(current_col) if current_col in collections else 0
        col_row = Adw.ComboRow(title="Collection")
        col_row.set_subtitle("Select the wallpaper collection to browse")
        col_row.set_model(col_model)
        col_row.set_selected(col_idx)
        self._col_actions = RowActions(
            col_row,
            on_discard=lambda: self._discard_var("RETRO_WALL_COLLECTION"),
            on_reset=lambda: self._reset_var("RETRO_WALL_COLLECTION"),
        )
        col_row.add_suffix(self._col_actions.box)
        self._col_actions.reorder_first()

        delete_col_btn = Gtk.Button(icon_name="user-trash-symbolic")
        delete_col_btn.set_tooltip_text("Delete collection")
        delete_col_btn.add_css_class("flat")
        delete_col_btn.set_valign(Gtk.Align.CENTER)
        delete_col_btn.connect("clicked", self._on_delete_collection)
        col_row.add_suffix(delete_col_btn)
        self._col_delete_btn = delete_col_btn

        col_row.connect("notify::selected", self._on_collection_changed)
        pref_group.add(col_row)
        self._col_row = col_row
        self._update_col_delete_visibility()

        # Slideshow
        slide_row = Adw.SwitchRow(title="Enable Slideshow")
        slide_row.set_subtitle("Enables automatic cycling through multiple wallpapers in your collection.")
        slide_row.set_active(get_var("WALL_SLIDESHOW_ACTIVE", "false") == "true")
        slide_row.connect("notify::active", self._on_slideshow_toggled)
        self._slide_actions = RowActions(
            slide_row,
            on_discard=lambda: self._discard_var("WALL_SLIDESHOW_ACTIVE"),
            on_reset=lambda: self._reset_var("WALL_SLIDESHOW_ACTIVE"),
        )
        slide_row.add_suffix(self._slide_actions.box)
        self._slide_actions.reorder_first()
        pref_group.add(slide_row)
        self._slide_row = slide_row
        self._slide_switch = slide_row

        adj = Gtk.Adjustment(value=int(get_var("WALL_SLIDESHOW_INTERVAL", "300")), lower=30, upper=86400, step_increment=30, page_increment=300)
        interval_row = Adw.ActionRow(title="Slideshow Interval (seconds)")
        interval_row.set_subtitle("Controls how long each wallpaper is displayed before switching to the next one. Minimum 30 seconds.")
        interval_spin = Gtk.SpinButton(adjustment=adj, digits=0)
        interval_spin.set_valign(Gtk.Align.CENTER)
        interval_spin.connect("notify::value", self._on_interval_changed)
        interval_row.add_suffix(interval_spin)
        self._interval_actions = RowActions(
            interval_row,
            on_discard=lambda: self._discard_var("WALL_SLIDESHOW_INTERVAL"),
            on_reset=lambda: self._reset_var("WALL_SLIDESHOW_INTERVAL"),
        )
        interval_row.add_suffix(self._interval_actions.box)
        self._interval_actions.reorder_first()
        interval_row.set_visible(slide_row.get_active())
        slide_row.connect("notify::active", lambda sw, _ps: interval_row.set_visible(sw.get_active()))
        pref_group.add(interval_row)
        self._interval_row = interval_row
        self._interval_spin = interval_spin

        # Resolution map — W x H spinners
        current_res = get_var("WALL_RES_MAP", "")
        try:
            cur_res = current_res.rsplit("|", 1)[-1] if "|" in current_res else current_res
            if "x" in cur_res:
                parts = cur_res.split("x")
                cur_w, cur_h = parts[0], parts[1]
            else:
                cur_w, cur_h = "1920", "1080"
        except (ValueError, IndexError):
            cur_w, cur_h = "1920", "1080"
        res_row = Adw.ActionRow(title="Wallpaper Resolution")
        current_res_str = f"{cur_w}x{cur_h}"
        res_row.set_subtitle("Set a custom width and height to optimize wallpapers for your display")
        adj_w = Gtk.Adjustment(value=int(cur_w), lower=1, upper=99999, step_increment=1, page_increment=100)
        adj_h = Gtk.Adjustment(value=int(cur_h), lower=1, upper=99999, step_increment=1, page_increment=100)
        spin_w = Gtk.SpinButton(adjustment=adj_w, digits=0)
        spin_h = Gtk.SpinButton(adjustment=adj_h, digits=0)
        spin_w.set_valign(Gtk.Align.CENTER)
        spin_h.set_valign(Gtk.Align.CENTER)
        spin_w.connect("notify::value", self._on_res_apply)
        spin_h.connect("notify::value", self._on_res_apply)
        res_row.add_suffix(spin_w)
        self._res_actions = RowActions(
            res_row,
            on_discard=lambda: self._discard_var("WALL_RES_MAP"),
            on_reset=lambda: self._reset_var("WALL_RES_MAP"),
        )
        res_row.add_suffix(self._res_actions.box)
        self._res_actions.reorder_first()
        res_row.add_suffix(spin_h)
        pref_group.add(res_row)
        self._res_row = res_row
        self._spin_w = spin_w
        self._spin_h = spin_h

        # GPU Offload
        gpu_modes = ["auto", "nvidia", "amd", "intel", "off"]
        self._gpu_modes = gpu_modes
        gpu_display = ["Auto (detect)", "Nvidia", "AMD", "Intel", "Off (CPU only)"]
        gpu_model = Gtk.StringList.new(gpu_display)
        current_gpu = get_var("WALL_GPU_OFFLOAD", "auto")
        gpu_idx = gpu_modes.index(current_gpu) if current_gpu in gpu_modes else 0
        gpu_row = Adw.ComboRow(title="GPU Offload")
        gpu_row.set_subtitle("Select GPU offload mode for video wallpaper rendering")
        gpu_row.set_model(gpu_model)
        gpu_row.set_selected(gpu_idx)
        gpu_row.connect("notify::selected", self._on_gpu_changed, gpu_modes)
        self._gpu_actions = RowActions(
            gpu_row,
            on_discard=lambda: self._discard_var("WALL_GPU_OFFLOAD"),
            on_reset=lambda: self._reset_var("WALL_GPU_OFFLOAD"),
        )
        gpu_row.add_suffix(self._gpu_actions.box)
        self._gpu_actions.reorder_first()
        pref_group.add(gpu_row)
        self._gpu_row = gpu_row

        content_box.append(pref_group)

        search_entry = Gtk.SearchEntry()
        search_entry.set_placeholder_text("Search wallpapers\u2026")
        search_entry.set_margin_start(12)
        search_entry.set_margin_end(12)
        search_entry.set_margin_top(12)
        search_entry.set_margin_bottom(4)
        search_entry.connect("search-changed", self._on_search)
        content_box.append(search_entry)

        flow = Gtk.FlowBox()
        flow.set_max_children_per_line(5)
        flow.set_min_children_per_line(2)
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_column_spacing(10)
        flow.set_row_spacing(10)
        flow.set_margin_start(12)
        flow.set_margin_end(12)
        flow.set_margin_top(8)
        flow.set_margin_bottom(12)
        flow.set_vexpand(True)
        content_box.append(flow)

        self._content_box = content_box
        self._flow_box = flow
        self._search_entry = search_entry

        spinner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        spinner_box.set_valign(Gtk.Align.CENTER)
        spinner_box.set_halign(Gtk.Align.CENTER)
        spinner_box.set_margin_top(48)
        spinner = Gtk.Spinner()
        spinner.set_size_request(32, 32)
        spinner.start()
        spinner_box.append(spinner)
        lbl = Gtk.Label(label="Loading wallpapers\u2026")
        lbl.add_css_class("dim-label")
        spinner_box.append(lbl)
        self._spinner_box = spinner_box
        content_box.append(spinner_box)

        self._load_wallpapers_async()

        return toolbar

    def _load_wallpapers_async(self) -> None:
        def worker():
            wallpapers = _list_wallpapers(self._active_collection())
            GLib.idle_add(self._on_wallpapers_loaded, wallpapers)
        threading.Thread(target=worker, daemon=True).start()

    def _active_collection(self) -> str:
        if self._pending_collection is not None:
            return self._pending_collection
        return self._selected_collection()

    def _on_wallpapers_loaded(self, wallpapers: list[dict]) -> None:
        self._all_wallpapers = wallpapers
        if self._spinner_box is not None and self._content_box is not None:
            self._content_box.remove(self._spinner_box)
            self._spinner_box = None
        self._rebuild()
        self._needs_opt = self._check_needs_optimization()
        self._refresh_opt_banner()
        self._refresh_managed()

    def _refresh(self):
        self._search_term = self._search_entry.get_text().strip().lower() if self._search_entry else ""
        def worker():
            wallpapers = _list_wallpapers(self._active_collection())
            GLib.idle_add(self._on_refreshed, wallpapers)
        threading.Thread(target=worker, daemon=True).start()

    def _on_refreshed(self, wallpapers: list[dict]) -> None:
        self._all_wallpapers = wallpapers
        self._rebuild()
        self._refresh_opt_banner()

    def _on_search(self, _entry):
        term = self._search_entry.get_text().strip().lower()  # type: ignore[union-attr]
        self._search_term = term if len(term) >= 3 else ""
        self._rebuild()

    def _make_flowbox(self) -> Gtk.FlowBox:
        flow = Gtk.FlowBox()
        flow.set_max_children_per_line(5)
        flow.set_min_children_per_line(2)
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_column_spacing(10)
        flow.set_row_spacing(10)
        flow.set_margin_start(12)
        flow.set_margin_end(12)
        flow.set_margin_top(8)
        flow.set_margin_bottom(12)
        flow.set_vexpand(True)
        return flow

    def get_search_entries(self) -> list[dict]:
        return [
            {
                "key": "wallpapers:static_forced",
                "label": "Force Static Wallpaper",
                "description": "Forces all wallpapers to run in static mode",
                "_group_id": "wallpapers",
                "_group_label": "Wallpapers",
                "_section_label": "Settings",
            },
            {
                "key": "wallpapers:static_on_bat",
                "label": "Static on Battery",
                "description": "Switches to static wallpapers when on battery power",
                "_group_id": "wallpapers",
                "_group_label": "Wallpapers",
                "_section_label": "Settings",
            },
            {
                "key": "wallpapers:gpu_offload",
                "label": "GPU Offload",
                "description": "Select GPU offload mode for video wallpaper rendering",
                "_group_id": "wallpapers",
                "_group_label": "Wallpapers",
                "_section_label": "Settings",
            },
            {
                "key": "wallpapers:collection",
                "label": "Wallpaper Collection",
                "description": "Switch between wallpaper collections",
                "_group_id": "wallpapers",
                "_group_label": "Wallpapers",
                "_section_label": "Settings",
            },
            {
                "key": "wallpapers:slideshow",
                "label": "Enable Slideshow",
                "description": "Enables automatic cycling through multiple wallpapers in your collection",
                "_group_id": "wallpapers",
                "_group_label": "Wallpapers",
                "_section_label": "Settings",
            },
            {
                "key": "wallpapers:slideshow_interval",
                "label": "Slideshow Interval",
                "description": "Controls how long each wallpaper is displayed before switching to the next one",
                "_group_id": "wallpapers",
                "_group_label": "Wallpapers",
                "_section_label": "Settings",
            },
            {
                "key": "wallpapers:res_map",
                "label": "Wallpaper Resolution",
                "description": "Set a custom render resolution per monitor",
                "_group_id": "wallpapers",
                "_group_label": "Wallpapers",
                "_section_label": "Settings",
            },
        ]

    def _on_static_toggled(self, switch, _pspec):
        if self._setting_value:
            return
        self._pending_static = switch.get_active()
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _on_static_bat_toggled(self, switch, _pspec):
        if self._setting_value:
            return
        self._pending_static_bat = switch.get_active()
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _on_slideshow_toggled(self, switch, _pspec):
        if self._setting_value:
            return
        self._pending_slideshow = switch.get_active()
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _on_interval_changed(self, spin, _pspec):
        if self._setting_value:
            return
        self._pending_interval = int(spin.get_value())
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def _on_res_apply(self, spin, _pspec):
        if self._setting_value:
            return
        w = int(self._spin_w.get_value()) if self._spin_w is not None else 1920
        h = int(self._spin_h.get_value()) if self._spin_h is not None else 1080
        text = f"{w}x{h}"
        if text != get_var("WALL_RES_MAP", ""):
            self._pending_res_map = text
            self._dirty = True
            self._notify_dirty()
            self._refresh_managed()

    def _on_collection_changed(self, row, _pspec):
        if self._setting_value:
            return
        idx = row.get_selected()
        if idx < 0 or idx >= len(self._collections):
            return
        name = self._collections[idx]
        if name == get_var("RETRO_WALL_COLLECTION", ""):
            return
        from lib.python.variable import set_var
        set_var("RETRO_WALL_COLLECTION", name)
        self._pending_collection = name
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()
        self._update_col_delete_visibility()
        self._refresh()

    def _update_col_delete_visibility(self) -> None:
        if self._col_delete_btn is None:
            return
        name = self._selected_collection()
        self._col_delete_btn.set_visible(name not in ("all", "") and name not in self._repo_collections)

    def _on_delete_collection(self, _btn) -> None:
        name = self._selected_collection()
        if not name or name in ("all", "") or name in self._repo_collections:
            self._window.show_toast("Only custom collections can be deleted", timeout=2)
            return
        dialog = Adw.AlertDialog(
            heading="Delete Collection?",
            body=f'Delete "{name}" and all its wallpapers? This cannot be undone.',
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("delete", "Delete")
        dialog.set_default_response("delete")
        dialog.set_close_response("cancel")
        dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)

        def _on_response(dialog_obj, response):
            if response != "delete":
                return

            def worker():
                result = subprocess.run(
                    ["bash", str(WALLPAPER_CORE), "--collection-delete", name],
                    capture_output=True, text=True, timeout=15,
                )
                ok = "result=ok" in result.stdout
                GLib.idle_add(self._on_collection_deleted, name, ok)

            threading.Thread(target=worker, daemon=True).start()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    def _on_collection_deleted(self, name: str, ok: bool) -> None:
        if ok:
            self._window.show_toast(f"Collection deleted: {name}", timeout=2)
        else:
            self._window.show_toast("Failed to delete collection", timeout=3)
        self._refresh_collections(select=None)
        self._refresh()

    def _on_gpu_changed(self, row, _pspec, modes: list[str]):
        if self._setting_value:
            return
        idx = row.get_selected()
        if idx < 0 or idx >= len(modes):
            return
        name = modes[idx]
        if name == get_var("WALL_GPU_OFFLOAD", ""):
            return
        self._pending_gpu = name
        self._dirty = True
        self._notify_dirty()
        self._refresh_managed()

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self):
        self._dirty = False
        self._pending_static = None
        self._pending_static_bat = None
        self._pending_collection = None
        self._pending_slideshow = None
        self._pending_interval = None
        self._pending_res_map = None
        self._pending_gpu = None
        self._refresh_managed()

    def flush_pending(self):
        if self._pending_static is not None:
            subprocess.Popen(
                ["retro", "wallpaper", "static", "true" if self._pending_static else "false"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        if self._pending_static_bat is not None:
            from lib.python.variable import set_var
            set_var("WALL_STATIC_ON_BAT", "true" if self._pending_static_bat else "false")
            subprocess.Popen(
                ["retro", "app", "all", "refresh"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        if self._pending_collection is not None:
            subprocess.Popen(
                ["retro", "wallpaper", "collection", self._pending_collection],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            self._window.show_toast(f"Collection: {self._pending_collection}", timeout=2)
            GLib.timeout_add(500, self._refresh)

        if self._pending_slideshow is not None:
            subprocess.Popen(
                ["retro", "wallpaper", "slideshow", "true" if self._pending_slideshow else "false"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        elif self._pending_interval is not None:
            from lib.python.variable import set_var
            set_var("WALL_SLIDESHOW_INTERVAL", str(self._pending_interval))
            if get_var("WALL_SLIDESHOW_ACTIVE", "false") == "true":
                subprocess.run(
                    ["retro", "wallpaper", "slideshow", "false"],
                    capture_output=True, text=True, timeout=10,
                )
                def _re_enable() -> bool:
                    subprocess.Popen(
                        ["retro", "wallpaper", "slideshow", "true"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    )
                    return False
                GLib.timeout_add(500, _re_enable)

        if self._pending_res_map is not None:
            from lib.python.variable import set_var
            set_var("WALL_RES_MAP", self._pending_res_map)
            subprocess.Popen(
                ["retro", "wallpaper", "optimize"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        if self._pending_gpu is not None:
            subprocess.Popen(
                ["retro", "wallpaper", "gpu", self._pending_gpu],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        self.mark_saved()

    def _rebuild(self):
        if self._content_box is None:
            return
        # Build cards for matching wallpapers only
        matching = self._all_wallpapers
        if self._search_term:
            matching = [w for w in matching if self._search_term in w.get("_search_tags", "")]
        new_flow = self._make_flowbox()
        for wp in matching:
            card = self._make_card(wp)
            new_flow.append(card)
        # Replace old FlowBox
        if self._flow_box is not None:
            self._content_box.remove(self._flow_box)
        self._flow_box = new_flow
        self._content_box.append(self._flow_box)
        self._flow_box.show()

    def _make_card(self, wp: dict) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_halign(Gtk.Align.CENTER)

        thumb_path = wp.get("thumb", "")
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(thumb_path, 520, 292, True)
            pic = Gtk.Picture.new_for_pixbuf(pb)
            pic.set_content_fit(Gtk.ContentFit.COVER)
            pic.add_css_class("wallpaper-thumb")
            pic.set_can_shrink(True)
            pic.set_size_request(260, 146)
        except Exception:
            pic = Gtk.Picture.new_for_filename("")
            pic.set_size_request(260, 146)

        name_label = Gtk.Label(label=wp.get("name", ""))
        name_label.set_ellipsize(3)  # type: ignore[arg-type]
        name_label.set_max_width_chars(24)

        box.append(pic)

        name_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        name_box.set_halign(Gtk.Align.CENTER)
        name_box.append(name_label)
        box.append(name_box)

        badge_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        badge_box.set_halign(Gtk.Align.CENTER)

        is_live = wp.get("type") == "live"
        type_badge = Gtk.Label(label="Live" if is_live else "Static")
        type_badge.add_css_class("badge")
        type_badge.add_css_class("live-badge" if is_live else "static-badge")
        badge_box.append(type_badge)

        # Warning icon if wallpaper exceeds target resolution
        target = get_var("WALL_RES_MAP", "")
        tw, th = self._parse_res(target)
        w, h = self._parse_res(wp.get("resolution", ""))
        if tw > 0 and th > 0 and (w > tw or h > th):
            unopt = Gtk.Label(label="Unoptimized")
            unopt.add_css_class("badge")
            unopt.add_css_class("unoptimized-badge")
            badge_box.prepend(unopt)

        res = wp.get("resolution", "")
        if res and res != "?":
            res_label = Gtk.Label(label=res)
            res_label.add_css_class("badge")
            res_label.add_css_class("res-badge")
            badge_box.append(res_label)

        if wp.get("active"):
            active_badge = Gtk.Label(label="Active")
            active_badge.add_css_class("badge")
            active_badge.add_css_class("active-badge")
            badge_box.append(active_badge)

        box.append(badge_box)

        actions_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        actions_box.set_halign(Gtk.Align.CENTER)

        edit_btn = Gtk.Button(icon_name="document-edit-symbolic")
        edit_btn.set_tooltip_text("Rename")
        edit_btn.add_css_class("flat")
        edit_btn.connect("clicked", self._on_rename, wp)

        trash_btn = Gtk.Button(icon_name="user-trash-symbolic")
        trash_btn.set_tooltip_text("Delete")
        trash_btn.add_css_class("flat")
        trash_btn.connect("clicked", self._on_delete, wp)

        actions_box.append(edit_btn)
        actions_box.append(trash_btn)
        box.append(actions_box)

        gesture = Gtk.GestureClick()
        gesture.connect("pressed", self._on_click, wp.get("path", ""), wp.get("name", ""))
        pic.add_controller(gesture)
        return box

    def _on_rename(self, _btn, wp: dict):
        orig = wp.get("orig_name", "")
        current_stem = Path(orig).stem

        entry = Gtk.Entry()
        entry.set_text(current_stem)
        entry.set_activates_default(True)

        dialog = Adw.AlertDialog(
            heading="Rename Wallpaper",
            body="Enter a new name (file format stays the same).",
            extra_child=entry,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("rename", "Rename")
        dialog.set_default_response("rename")
        dialog.set_close_response("cancel")

        def _on_response(dialog_obj, response):
            if response == "rename":
                raw = entry.get_text().strip()
                if not raw:
                    return
                new_stem = Path(raw).stem
                path = wp.get("path", "")
                was_active = wp.get("active", False)
                if path and Path(path).exists() and _rename_wallpaper(path, new_stem):
                    self._window.show_toast("Wallpaper renamed", timeout=2)
                    self._refresh()
                    if was_active:
                        new_path = str(Path(path).parent / f"{new_stem}{Path(path).suffix}")
                        if Path(new_path).exists():
                            proc = subprocess.Popen(
                                ["bash", str(WALLPAPER_CORE), "--set", new_path],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            )
                            GLib.child_watch_add(proc.pid, lambda *_: None)
        dialog.connect("response", _on_response)
        dialog.present(self._window)

    def _on_delete(self, _btn, wp: dict):
        dialog = Adw.AlertDialog(
            heading="Delete Wallpaper?",
            body=f'Delete "{wp.get("name", "")}"? This cannot be undone.',
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("delete", "Delete")
        dialog.set_default_response("delete")
        dialog.set_close_response("cancel")
        dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)

        def _on_response(dialog_obj, response):
            if response == "delete":
                path = wp.get("path", "")
                if path and Path(path).exists() and _delete_wallpaper(path):
                    if wp.get("active"):
                        self._window.show_toast("Active wallpaper deleted", timeout=3)
                    else:
                        self._window.show_toast("Wallpaper deleted", timeout=2)
                    self._refresh()
        dialog.connect("response", _on_response)
        dialog.present(self._window)

    def _on_new_collection(self, _btn):
        entry = Gtk.Entry()
        entry.set_activates_default(True)
        entry.set_placeholder_text("e.g. My Favorites")

        dialog = Adw.AlertDialog(
            heading="New Collection",
            body="Enter a name for the new wallpaper collection.",
            extra_child=entry,
        )
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("create", "Create")
        dialog.set_default_response("create")
        dialog.set_close_response("cancel")

        def _on_response(dialog_obj, response):
            if response != "create":
                return
            name = entry.get_text().strip().replace("/", "_").replace(" ", "_")
            if not name:
                self._window.show_toast("Collection name cannot be empty", timeout=2)
                return

            def worker():
                subprocess.run(
                    ["bash", str(WALLPAPER_CORE), "--collection-create", name],
                    capture_output=True, text=True, timeout=15,
                )
                GLib.idle_add(self._on_collection_created, name)

            threading.Thread(target=worker, daemon=True).start()

        dialog.connect("response", _on_response)
        dialog.present(self._window)

    def _on_collection_created(self, name: str) -> None:
        self._refresh_collections(select=name)
        self._window.show_toast(f"Collection created: {name}", timeout=2)
        self._refresh()

    def _refresh_collections(self, select: str | None = None) -> None:
        col_result = subprocess.run(
            ["bash", str(WALLPAPER_CORE), "--collection", "list"],
            capture_output=True, text=True, timeout=10,
        )
        collections = [l.strip() for l in col_result.stdout.split("\n") if l.strip()]
        collections.sort()
        collections.insert(0, "all")
        self._collections = collections
        if self._col_row is None:
            return
        col_display = [c[0].upper() + c[1:] if c else c for c in collections]
        if select and select in collections:
            idx = collections.index(select)
        else:
            current_col = get_var("RETRO_WALL_COLLECTION", "retro")
            idx = collections.index(current_col) if current_col in collections else 0
        self._setting_value = True
        self._col_row.set_model(Gtk.StringList.new(col_display))
        self._col_row.set_selected(idx)
        self._setting_value = False
        self._update_col_delete_visibility()

    def _on_add(self, _btn):
        dialog = Gtk.FileChooserNative.new(
            title="Select Wallpapers",
            parent=self._window,
            action=Gtk.FileChooserAction.OPEN,
            accept_label="Add",
            cancel_label="Cancel",
        )
        dialog.set_select_multiple(True)
        all_formats = Gtk.FileFilter.new()
        all_formats.set_name("Images & Videos")
        for pat in ("*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.webm"):
            all_formats.add_pattern(pat)
        dialog.add_filter(all_formats)
        dialog.connect("response", self._on_files_chosen)
        dialog.show()

    def _on_files_chosen(self, dialog, response):
        if response == Gtk.ResponseType.ACCEPT:
            files = dialog.get_files()
            paths = []
            for i in range(files.get_n_items()):
                f = files.get_item(i)
                p = f.get_path() if f else None
                if p:
                    paths.append(p)
            dialog.destroy()
            if not paths:
                return
            self._add_to_collection(paths)
        else:
            dialog.destroy()

    def _add_to_collection(self, paths: list[str]) -> None:
        collection = self._selected_collection()

        if collection == "all":
            entry = Gtk.Entry()
            entry.set_activates_default(True)
            entry.set_placeholder_text("Collection name")

            dialog = Adw.AlertDialog(
                heading="Choose a Collection",
                body="Selecting \u201call\u201d isn\u2019t allowed. Enter a collection name to add these wallpapers to:",
                extra_child=entry,
            )
            dialog.add_response("cancel", "Cancel")
            dialog.add_response("add", "Add Here")
            dialog.set_default_response("add")
            dialog.set_close_response("cancel")

            def _on_response(dialog_obj, response):
                if response != "add":
                    return
                name = entry.get_text().strip().replace("/", "_").replace(" ", "_")
                if not name:
                    self._window.show_toast("Collection name cannot be empty", timeout=2)
                    return

                def worker():
                    subprocess.run(
                        ["bash", str(WALLPAPER_CORE), "--collection-create", name],
                        capture_output=True, text=True, timeout=15,
                    )
                    self._add_files_worker(paths, name)
                    GLib.idle_add(self._on_files_added, name)

                threading.Thread(target=worker, daemon=True).start()

            dialog.connect("response", _on_response)
            dialog.present(self._window)
            return

        self._add_files(paths, collection)

    def _add_files(self, paths: list[str], collection: str) -> None:
        self._window.show_toast("Adding wallpapers\u2026", timeout=2)
        threading.Thread(
            target=self._add_files_worker, args=(paths, collection), daemon=True,
        ).start()

    def _add_files_worker(self, paths: list[str], collection: str) -> None:
        added = 0
        errors = 0
        for p in paths:
            result = subprocess.run(
                ["bash", str(WALLPAPER_CORE), "--add", p, collection],
                capture_output=True, text=True, timeout=30,
            )
            if "result=error" in result.stdout:
                errors += 1
            else:
                added += 1
        GLib.idle_add(self._on_files_done, added, errors, collection)

    def _on_files_done(self, added: int, errors: int, collection: str) -> None:
        if added:
            self._window.show_toast(
                f"Added {added} wallpaper(s) to {collection}", timeout=2,
            )
        if errors:
            self._window.show_toast(f"{errors} file(s) failed", timeout=3)
        self._refresh()

    def _on_files_added(self, name: str) -> None:
        self._refresh_collections(select=name)

    def _selected_collection(self) -> str:
        if self._col_row is not None:
            idx = self._col_row.get_selected()
            if 0 <= idx < len(self._collections):
                return self._collections[idx]
        return get_var("RETRO_WALL_COLLECTION", "retro")

    def _on_click(self, _gesture, _n_press, _x, _y, path: str, display: str):
        if not path or not Path(path).exists():
            self._window.show_toast(f"Wallpaper not found: {display}", timeout=3)
            return

        proc = subprocess.Popen(
            ["bash", str(WALLPAPER_CORE), "--set", path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        GLib.child_watch_add(proc.pid, self._on_set_done, display)

    def _on_set_done(self, pid: int, status: int, display: str) -> None:
        if status == 0:
            self._window.show_toast(f"Wallpaper set: {display}", timeout=2)
            self._refresh()
        else:
            self._window.show_toast(f"Failed to set: {display}", timeout=3)

