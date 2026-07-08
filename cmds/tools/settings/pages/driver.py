import os
import subprocess
import threading
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GdkPixbuf, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_DRIVER_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "driver_core.sh")
_BRAND_DIR = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "assets", "brands")
_DRIVER_ICON = "application-x-firmware-symbolic"


def _run(args: list[str], timeout: int = 15) -> str:
    try:
        r = subprocess.run(
            ["bash", _DRIVER_CORE, *args],
            capture_output=True, text=True, timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


class DriverPage:
    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._dirty = False
        self._on_dirty_changed = None
        self._tick_source = None
        self._scan_data: list[dict] = []
        self._pkg_data: list[dict] = []
        self._conflicts: list[str] = []
        self._missing_pkgs: list[str] = []
        self._components: dict[str, list[dict]] = {}
        self._sys_status: dict[str, str] = {}
        self._specs: dict[str, dict] = {}
        self._env_status: str = ""
        self._temps: dict[str, int] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh driver scan")
        refresh_btn.connect("clicked", lambda _b: self._full_refresh())
        header.pack_start(refresh_btn)

        spinner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        spinner_box.set_valign(Gtk.Align.CENTER)
        spinner_box.set_halign(Gtk.Align.CENTER)
        spinner_box.set_margin_top(48)
        spinner = Gtk.Spinner()
        spinner.set_size_request(32, 32)
        spinner.start()
        spinner_box.append(spinner)
        lbl = Gtk.Label(label="Scanning hardware\u2026")
        lbl.add_css_class("dim-label")
        spinner_box.append(lbl)
        self._content_box.append(spinner_box)

        self._load_data()

        return toolbar_view

    def _load_data(self) -> None:
        def worker():
            scan = _run(["--scan"])
            pkgs = _run(["--packages"])
            conflicts = _run(["--conflicts"])
            specs = _run(["--hardware-specs"])
            env = _run(["--check-env"])
            temps = _run(["--temps"])
            GLib.idle_add(self._on_data_loaded, scan, pkgs, conflicts, specs, env, temps)
        threading.Thread(target=worker, daemon=True).start()

    def _on_data_loaded(self, scan: str, pkgs: str, conflicts: str, specs: str, env: str, temps: str) -> None:
        self._parse_scan(scan)
        self._parse_packages(pkgs)
        self._conflicts = [c for c in conflicts.splitlines() if c.strip()]
        self._parse_specs(specs)
        self._env_status = env.replace("ENV|", "").strip() if "ENV|" in env else ""
        self._parse_temps(temps)

        self._missing_pkgs = []
        for comp in self._scan_data:
            m = comp.get("missing", "")
            if m:
                self._missing_pkgs.extend(m.split())
        self._missing_pkgs = sorted(set(self._missing_pkgs))

        self._rebuild_ui()
        update = getattr(self._window, "_update_sidebar_badges", None)
        if update:
            update()

    def _parse_scan(self, raw: str) -> None:
        self._scan_data = []
        self._components = {}
        self._sys_status = {}
        for line in raw.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split("|", 5)
            if len(parts) < 6:
                continue
            typ, vendor, model, driver, pkgs, missing = (
                parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]
            )
            entry = {
                "type": typ, "vendor": vendor, "model": model,
                "driver": driver, "pkgs": pkgs, "missing": missing,
            }
            self._scan_data.append(entry)
            if typ in ("SYS", "WARN"):
                self._sys_status[vendor] = model
            else:
                self._components.setdefault(typ, []).append(entry)

    def _parse_packages(self, raw: str) -> None:
        self._pkg_data = []
        for line in raw.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split("|", 4)
            if len(parts) < 5 or parts[0] != "PKG":
                continue
            self._pkg_data.append({
                "type": parts[1], "name": parts[2],
                "version": parts[3], "status": parts[4],
            })

    def _parse_specs(self, raw: str) -> None:
        self._specs = {}
        for line in raw.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split("|", 1)
            if len(parts) < 2:
                continue
            typ = parts[0]
            rest = parts[1].split("|")
            if typ == "CPU" and len(rest) >= 2:
                self._specs["cpu"] = {"cores": rest[0], "threads": rest[1]}
            elif typ == "GPU" and len(rest) >= 4:
                self._specs["gpu"] = {
                    "vendor": rest[0], "count": rest[1],
                    "unit": rest[2], "device_id": rest[3],
                }
            elif typ == "NPU" and len(rest) >= 1:
                self._specs["npu"] = {"tops": rest[0], "model": rest[2] if len(rest) >= 3 else ""}

    def _parse_temps(self, raw: str) -> None:
        self._temps = {}
        for line in raw.splitlines():
            line = line.strip()
            if not line or "|" not in line:
                continue
            parts = line.split("|", 1)
            if len(parts) == 2 and parts[1].isdigit():
                self._temps[parts[0]] = int(parts[1])

    def _make_warning_row(self, title: str, subtitle: str, btn_label: str, on_click) -> Adw.ActionRow:
        row = Adw.ActionRow(title=title, subtitle=subtitle)
        row.add_css_class("warning-row")
        icon = Gtk.Image.new_from_icon_name("dialog-warning-symbolic")
        icon.set_valign(Gtk.Align.CENTER)
        row.add_prefix(icon)
        btn = Gtk.Button(label=btn_label)
        btn.add_css_class("suggested-action")
        btn.set_valign(Gtk.Align.CENTER)
        btn.connect("clicked", on_click)
        row.add_suffix(btn)
        return row

    def _rebuild_ui(self) -> None:
        for child in list(self._content_box):
            self._content_box.remove(child)

        self._build_hero_card()

        group = Adw.PreferencesGroup()
        any_warning = False

        if self._missing_pkgs:
            count = len(self._missing_pkgs)
            sub = ", ".join(self._missing_pkgs[:5])
            if len(self._missing_pkgs) > 5:
                sub += f" and {len(self._missing_pkgs) - 5} more"
            group.add(self._make_warning_row(
                f"{count} driver package{'s' if count > 1 else ''} need{'s' if count == 1 else ''} to be installed",
                sub, "Install All", lambda _b: self._install_missing(),
            ))
            any_warning = True

        if self._conflicts:
            group.add(self._make_warning_row(
                f"{len(self._conflicts)} driver conflict{'s' if len(self._conflicts) > 1 else ''} detected",
                self._conflicts[0], "Fix", lambda _b: self._run_terminal("retro driver fix-conflicts"),
            ))
            any_warning = True

        if getattr(self, "_env_status", None) in ("missing", "stale"):
            group.add(self._make_warning_row(
                "Missing Environment Variables",
                "The env file is missing GPU variables — this may lead to system instability",
                "Fix", lambda _b: self._run_terminal("retro driver hypr"),
            ))
            any_warning = True

        if any_warning:
            self._content_box.append(group)

        self._build_hardware_section()

    def _resolve_brand_path(self, vendor: str, component: str, model: str = "") -> str | None:
        if vendor == "intel":
            if component == "gpu":
                if any(k in model for k in ("Arc", "Meteor", "Lunar", "Battlemage")):
                    return os.path.join(_BRAND_DIR, "intel-arc.png")
                return os.path.join(_BRAND_DIR, "intel-core.png")
            return os.path.join(_BRAND_DIR, "intel-core.png")
        if vendor == "nvidia":
            if "RTX" in model:
                return os.path.join(_BRAND_DIR, "nvidia-rtx.png")
            return os.path.join(_BRAND_DIR, "nvidia-gtx.png")
        if vendor == "amd":
            if component == "gpu" and "Radeon" in model:
                return os.path.join(_BRAND_DIR, "amd-radeon.png")
            return os.path.join(_BRAND_DIR, "amd.png")
        return None

    @staticmethod
    def _clean_model(model: str, typ: str = "") -> str:
        m = model
        if typ == "cpu":
            m = m.replace("(R)", "").replace("(TM)", "").replace("(r)", "").replace("(tm)", "")
            m = m.replace("  ", " ").strip()
        elif typ == "gpu":
            if "[" in m and "]" in m:
                inner = m[m.index("[") + 1:m.index("]")]
                if inner:
                    return inner
            m = m.split(" [")[0]
            for prefix in ("Intel Corporation ", "Advanced Micro Devices, Inc. ", "NVIDIA Corporation "):
                if m.startswith(prefix):
                    m = m[len(prefix):]
                    break
        return m.strip()

    def _build_hero_card(self) -> None:
        gpu_entry = None
        cpu_entry = None
        for comp in self._scan_data:
            if comp["type"] == "GPU":
                gpu_entry = comp
            elif comp["type"] == "CPU":
                cpu_entry = comp

        cpu_path = self._resolve_brand_path(cpu_entry["vendor"], "cpu") if cpu_entry else None
        gpu_path = self._resolve_brand_path(gpu_entry["vendor"], "gpu", gpu_entry["model"]) if gpu_entry else None

        if not cpu_path and not gpu_path:
            return

        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        card.add_css_class("hero-card")
        card.set_valign(Gtk.Align.CENTER)

        logo_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        logo_box.set_halign(Gtk.Align.START)
        logo_box.set_margin_end(12)

        def _make_logo(path: str) -> None:
            try:
                src = GdkPixbuf.Pixbuf.new_from_file(path)
                pb = src.scale_simple(100, 100, GdkPixbuf.InterpType.NEAREST)
                pic = Gtk.Picture.new_for_pixbuf(pb)
                pic.set_size_request(100, 100)
                logo_box.append(pic)
            except Exception:
                pass

        if cpu_path and os.path.exists(cpu_path):
            _make_logo(cpu_path)

        plus = Gtk.Label(label="+")
        plus.add_css_class("heading")
        plus.set_valign(Gtk.Align.CENTER)
        logo_box.append(plus)

        if gpu_path and os.path.exists(gpu_path):
            _make_logo(gpu_path)

        card.append(logo_box)

        center = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        center.set_hexpand(True)

        title_lbl = Gtk.Label(label="System Architecture")
        title_lbl.add_css_class("title-2")
        title_lbl.set_halign(Gtk.Align.START)

        cpu_name = self._clean_model(cpu_entry["model"], "cpu") if cpu_entry else ""
        gpu_name = self._clean_model(gpu_entry["model"], "gpu") if gpu_entry else ""
        combo = f"{cpu_name} + {gpu_name}" if cpu_name and gpu_name else cpu_name or gpu_name
        combo_lbl = Gtk.Label(label=combo)
        combo_lbl.set_halign(Gtk.Align.START)
        combo_lbl.set_ellipsize(3)

        tech_parts = []
        cpu_s = self._specs.get("cpu", {})
        if cpu_s:
            tech_parts.append(f"{cpu_s.get('cores', '?')}C/{cpu_s.get('threads', '?')}T")
        gpu_s = self._specs.get("gpu", {})
        if gpu_s and gpu_s.get("count"):
            tech_parts.append(f"{gpu_s['count']} {gpu_s['unit']}")
        npu_s = self._specs.get("npu", {})
        if npu_s and npu_s.get("tops") and npu_s["tops"] != "0":
            tech_parts.append(f"NPU {npu_s['tops']} TOPS")
        tech_lbl = Gtk.Label(label=" \u00b7 ".join(tech_parts) if tech_parts else "")
        tech_lbl.add_css_class("dim-label")
        tech_lbl.set_halign(Gtk.Align.START)

        sys_parts = []
        for key, label in (("multilib", "Multilib"), ("rebar", "Resizable BAR")):
            val = self._sys_status.get(key, "")
            sys_parts.append(f"{label}: {val.capitalize() if val else 'Unknown'}")
        sys_lbl = Gtk.Label(label=" \u00b7 ".join(sys_parts))
        sys_lbl.add_css_class("dim-label")
        sys_lbl.set_halign(Gtk.Align.START)

        center.append(title_lbl)
        center.append(combo_lbl)
        center.append(tech_lbl)
        center.append(sys_lbl)
        card.append(center)

        total = len(self._pkg_data)
        installed = sum(1 for p in self._pkg_data if p["status"] == "installed")
        status_text = f"{installed}/{total} Installed" if total else "Ready"
        status_lbl = Gtk.Label(label=status_text)
        status_lbl.add_css_class("pill")
        status_lbl.add_css_class("success" if not self._missing_pkgs else "error")
        status_lbl.set_valign(Gtk.Align.CENTER)
        card.append(status_lbl)

        self._content_box.append(card)

    def _build_hardware_section(self) -> None:
        group = Adw.PreferencesGroup(title="Hardware Overview")

        type_labels = {
            "GPU": ("GPU", "video-display-symbolic"),
            "CPU": ("CPU", "cpu-symbolic"),
            "NPU": ("NPU", "system-run-symbolic"),
            "NET": ("Network", "network-wireless-symbolic"),
            "AUDIO": ("Audio", "audio-speakers-symbolic"),
        }

        for typ in ("GPU", "CPU", "NPU", "NET", "AUDIO"):
            entries = self._components.get(typ, [])
            if not entries:
                continue
            label, icon = type_labels.get(typ, (typ, "computer-symbolic"))
            for comp in entries:
                self._build_hw_row(group, label, comp, icon)
                label = None

        self._build_packages_expander(group)

        if self._components:
            self._content_box.append(group)

    def _build_packages_expander(self, group: Adw.PreferencesGroup) -> None:
        if not self._pkg_data:
            return

        type_labels = {
            "GPU": "GPU", "CPU": "CPU", "NPU": "NPU", "NET": "Network",
            "BT": "Bluetooth", "FW": "Firmware", "OTHER": "Other",
        }

        by_type: dict[str, list[dict]] = {}
        for p in self._pkg_data:
            by_type.setdefault(p["type"], []).append(p)

        total = len(self._pkg_data)
        installed = sum(1 for p in self._pkg_data if p["status"] == "installed")
        missing = total - installed

        expander = Adw.ExpanderRow(
            title=f"Packages ({installed}/{total} installed)",
            subtitle=f"{missing} missing \u2014 expand to see details" if missing else "All driver packages present",
        )
        expander.add_prefix(Gtk.Image.new_from_icon_name("package-symbolic"))

        for typ in ("GPU", "CPU", "NPU", "NET", "BT", "FW", "OTHER"):
            entries = by_type.get(typ, [])
            if not entries:
                continue
            parts = []
            for p in entries:
                if p["status"] == "installed":
                    parts.append(f"{p['name']} {p['version']}")
                else:
                    parts.append(f"<span color='red'>{p['name']}</span>")
            label = type_labels.get(typ, typ)
            sub = Adw.ActionRow(title=label, subtitle=", ".join(parts) if parts else "")
            sub.set_activatable(False)
            expander.add_row(sub)

        group.add(expander)

    def _build_hw_row(self, group: Adw.PreferencesGroup, label: str | None, comp: dict, icon: str) -> None:
        title = label or comp["type"]
        parts = []
        if comp["model"]:
            parts.append(comp["model"])
        if comp["driver"]:
            parts.append(comp["driver"])
        subtitle = " \u00b7 ".join(parts) if parts else ""

        row = Adw.ActionRow(title=title, subtitle=subtitle)
        if label:
            row.add_prefix(Gtk.Image.new_from_icon_name(icon))

        missing = comp.get("missing", "")
        if missing:
            badge = Gtk.Label(label=f"{len(missing.split())} missing")
            badge.add_css_class("error")
            badge.set_valign(Gtk.Align.CENTER)
            row.add_suffix(badge)
        else:
            check = Gtk.Label(label="\u2713")
            check.add_css_class("success")
            check.set_valign(Gtk.Align.CENTER)
            row.add_suffix(check)

        t = self._temps.get(comp["type"])
        if t is not None and t > 0:
            tlbl = Gtk.Label(label=f"{t}\u00b0C")
            tlbl.add_css_class("temp-badge")
            tlbl.set_valign(Gtk.Align.CENTER)
            row.add_suffix(tlbl)

        group.add(row)

    def _build_packages_section(self) -> None:
        if not self._pkg_data:
            return

        type_labels = {
            "GPU": "GPU", "CPU": "CPU", "NPU": "NPU", "NET": "Network",
            "BT": "Bluetooth", "FW": "Firmware", "OTHER": "Other",
        }

        by_type: dict[str, list[dict]] = {}
        for p in self._pkg_data:
            by_type.setdefault(p["type"], []).append(p)

        total = len(self._pkg_data)
        installed = sum(1 for p in self._pkg_data if p["status"] == "installed")
        missing = total - installed

        group = Adw.PreferencesGroup(title="Driver Packages")
        if missing:
            expander = Adw.ExpanderRow(
                title=f"Packages ({installed}/{total} installed)",
                subtitle=f"{missing} missing \u2014 expand to see details",
            )
            expander.add_prefix(Gtk.Image.new_from_icon_name("package-symbolic"))
        else:
            expander = Adw.ExpanderRow(
                title=f"Packages ({installed}/{total} installed)",
                subtitle="All driver packages present",
            )
            expander.add_prefix(Gtk.Image.new_from_icon_name("package-symbolic"))

        for typ in ("GPU", "CPU", "NPU", "NET", "BT", "FW", "OTHER"):
            entries = by_type.get(typ, [])
            if not entries:
                continue
            parts = []
            for p in entries:
                if p["status"] == "installed":
                    parts.append(f"{p['name']} {p['version']}")
                else:
                    parts.append(f"<span color='red'>{p['name']}</span>")
            label = type_labels.get(typ, typ)
            sub = Adw.ActionRow(title=label, subtitle=", ".join(parts) if parts else "")
            sub.set_activatable(False)
            expander.add_row(sub)

        group.add(expander)
        self._content_box.append(group)

    def _install_missing(self) -> None:
        if not self._missing_pkgs:
            self._window.show_toast("No missing drivers to install")
            return
        self._run_terminal("retro driver install")
        GLib.timeout_add(2000, self._delayed_refresh)

    def _full_refresh(self) -> None:
        self._load_data()

    def _delayed_refresh(self) -> None:
        self._load_data()

    @staticmethod
    def _run_terminal(command: str) -> None:
        escaped = command.replace("'", "'\\''")
        cmd = f"kitty -- bash -c '{escaped}; echo; echo Press Enter to close.; read'"
        lua = f'hl.dsp.exec_cmd("{cmd}", {{ float = true, size = {{ 800, 500 }}, center = true }})'
        subprocess.Popen(
            ["hyprctl", "dispatch", lua],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def missing_count(self) -> int:
        return len(self._missing_pkgs)

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        self._dirty = False

    def discard(self) -> None:
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._dirty:
            yield PendingChange(
                category="Drivers",
                title="Driver Configuration",
                subtitle="Driver settings changed",
                navigate_to="driver",
                icon=_DRIVER_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "driver:overview", "label": "Hardware Overview",
             "description": "GPU, CPU, NPU, network, audio, bluetooth, firmware detection",
             "_group_id": "driver", "_group_label": "Drivers", "_section_label": "Hardware"},
            {"key": "driver:packages", "label": "Driver Packages",
             "description": "Installed and missing driver packages with versions",
             "_group_id": "driver", "_group_label": "Drivers", "_section_label": "Packages"},
            {"key": "driver:status", "label": "System Status",
             "description": "Multilib, Resizable BAR, driver conflicts",
             "_group_id": "driver", "_group_label": "Drivers", "_section_label": "Status"},
            {"key": "driver:actions", "label": "Actions",
             "description": "Install missing drivers, fix conflicts, generate env, firmware",
             "_group_id": "driver", "_group_label": "Drivers", "_section_label": "Actions"},
        ]

    def destroy(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None
