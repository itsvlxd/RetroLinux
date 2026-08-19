import os
import re
import subprocess
import threading
import time
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GdkPixbuf, GLib, Gtk

from settings.core.pending import PendingChange
from settings.core.system_info import gpu_memory_label, memory_summary
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
        self._updates: list[str] = []
        self._current_driver: str = ""
        self._memory_summary: str = ""
        self._gpu_mem_label: str = ""
        self._can_sudo: bool = False
        self._blacklisted: list[str] = []
        self._modules_load: list[str] = []
        self._modprobe_files: list[dict] = []
        self._module_states: dict[str, str] = {}
        self._all_modules: list[dict] = []
        self._module_desc_cache: dict[str, dict] = {}
        self._extra_missing: str = ""
        self._extra_installed: str = ""
        self._load_gen = 0

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh driver scan")
        refresh_btn.connect("clicked", lambda _b: self._full_refresh())
        header.pack_start(refresh_btn)

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_tooltip_text("Install optional drivers\u2026")
        add_btn.add_css_class("flat")
        add_btn.connect("clicked", lambda _b: self._open_driver_bundles())
        header.pack_start(add_btn)

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
        self._load_gen += 1
        gen = self._load_gen

        def worker():
            scan = _run(["--scan"])
            pkgs = _run(["--packages"])
            conflicts = _run(["--conflicts"])
            specs = _run(["--hardware-specs"])
            env = _run(["--check-env"])
            temps = _run(["--temps"])
            updates = _run(["--check-updates"])
            current = _run(["--current-driver"])
            mem = memory_summary()
            gpu_mem = gpu_memory_label()
            blacklisted = _run(["--blacklist-list"])
            modules_load = _run(["--modules-load-list"])
            modprobe_files = _run(["--modprobe-files"])
            module_list = _run(["--module-list"])
            extra = _run(["--extra-list"])
            extra_installed = _run(["--extra-installed"])
            GLib.idle_add(self._on_data_loaded, gen, scan, pkgs, conflicts, specs, env, temps, updates, current, mem, gpu_mem, blacklisted, modules_load, modprobe_files, module_list, extra, extra_installed)
        threading.Thread(target=worker, daemon=True).start()

    def _on_data_loaded(self, gen: int, scan: str, pkgs: str, conflicts: str, specs: str, env: str, temps: str, updates: str, current: str, mem: str, gpu_mem: str, blacklisted: str = "", modules_load: str = "", modprobe_files: str = "", module_list: str = "", extra: str = "", extra_installed: str = "") -> None:
        if gen != self._load_gen:
            return
        self._parse_scan(scan)
        self._parse_packages(pkgs)
        self._conflicts = [c for c in conflicts.splitlines() if c.strip()]
        self._parse_specs(specs)
        self._env_status = env.replace("ENV|", "").strip() if "ENV|" in env else ""
        self._parse_temps(temps)
        self._memory_summary = mem
        self._gpu_mem_label = gpu_mem
        self._can_sudo = _can_sudo()

        self._blacklisted = []
        for line in blacklisted.splitlines():
            if line.startswith("BLACKLIST|"):
                self._blacklisted.append(line.split("|", 1)[1])

        self._modules_load = []
        for line in modules_load.splitlines():
            if line.startswith("LOAD|"):
                self._modules_load.append(line.split("|", 1)[1])

        self._modprobe_files = []
        current_file = None
        for line in modprobe_files.splitlines():
            if line.startswith("FILE|"):
                current_file = {"name": line.split("|", 1)[1], "lines": []}
                self._modprobe_files.append(current_file)
            elif line.startswith("CONTENT|") and current_file is not None:
                current_file["lines"].append(line.split("|", 1)[1])

        self._all_modules = []
        for line in module_list.splitlines():
            if line.startswith("MODULE|"):
                parts = line.split("|")
                name = parts[1].strip() if len(parts) > 1 else ""
                category = parts[2].strip() if len(parts) > 2 else "other"
                if name:
                    self._all_modules.append({"name": name, "category": category})
        self._all_modules.sort(key=lambda m: m["name"])

        self._updates = []
        if "UPDATES|" in updates:
            parts = updates.split("|", 2)
            if len(parts) >= 3 and parts[1].isdigit() and int(parts[1]) > 0:
                self._updates = parts[2].strip().split()

        self._current_driver = current.strip() if current else ""

        self._extra_missing = ""
        if extra.strip() and extra.strip() != "NONE":
            self._extra_missing = extra.strip()

        self._extra_installed = ""
        if extra_installed.strip() and extra_installed.strip() != "NONE":
            self._extra_installed = extra_installed.strip()

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
            parts = line.split("|", 6)
            if len(parts) < 6:
                continue
            typ, vendor, model, driver, pkgs, missing = parts[:6]
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

    def _make_warning_row(self, title: str, subtitle: str, btn_label: str, on_click, icon_name: str = "dialog-warning-symbolic", css_class: str = "warning-row") -> Adw.ActionRow:
        row = Adw.ActionRow(title=title, subtitle=subtitle)
        row.add_css_class(css_class)
        icon = Gtk.Image.new_from_icon_name(icon_name)
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

        for comp in self._scan_data:
            if comp["type"] == "GPU" and comp["vendor"] == "intel" and self._current_driver == "i915":
                if any(k in comp["model"] for k in ("Meteor", "Arrow", "Lunar", "Battlemage")):
                    group.add(self._make_warning_row(
                        "Legacy i915 driver in use",
                        "Meteor Lake+ GPU should use the modern xe driver for better performance and power management",
                        "Switch to xe", lambda _b: self._run_terminal("retro driver switch xe"),
                    ))
                    any_warning = True
                    break

        if self._updates:
            sub = ", ".join(self._updates[:5])
            if len(self._updates) > 5:
                sub += f" and {len(self._updates) - 5} more"
            group.add(self._make_warning_row(
                f"{len(self._updates)} driver update{'s' if len(self._updates) > 1 else ''} available",
                sub, "Update All", lambda _b: self._run_terminal("retro driver update"),
            ))
            any_warning = True

        if any_warning:
            self._content_box.append(group)

        self._build_hardware_section()

        self._build_advanced_section()

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
                pb = GdkPixbuf.Pixbuf.new_from_file(path)
                pic = Gtk.Picture.new_for_pixbuf(pb)
                pic.set_content_fit(Gtk.ContentFit.CONTAIN)
                pic.set_size_request(64, 64)
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

        for typ in ("CPU", "GPU", "NPU", "NET", "AUDIO"):
            entries = self._components.get(typ, [])
            if not entries:
                continue
            label, icon = type_labels.get(typ, (typ, "computer-symbolic"))
            for comp in entries:
                self._build_hw_row(group, label, comp, icon)
                label = None
            if typ == "CPU" and self._memory_summary:
                self._add_memory_row(group)

        self._build_packages_expander(group)

        if self._components:
            self._content_box.append(group)

    def _add_memory_row(self, group: Adw.PreferencesGroup) -> None:
        mem_row = Adw.ActionRow(title="Memory", subtitle=self._memory_summary)
        mem_row.add_prefix(Gtk.Image.new_from_icon_name("memory-symbolic"))
        check = Gtk.Label(label="\u2713")
        check.add_css_class("success")
        check.set_valign(Gtk.Align.CENTER)
        mem_row.add_suffix(check)
        group.add(mem_row)

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
        if comp["type"] == "GPU" and self._gpu_mem_label:
            parts.append(self._gpu_mem_label)
        subtitle = " \u00b7 ".join(parts) if parts else ""

        row = Adw.ActionRow(title=title, subtitle=subtitle)
        if label:
            row.add_prefix(Gtk.Image.new_from_icon_name(icon))

        missing = comp.get("missing", "")
        if comp.get("type") == "NET" and comp.get("driver") == "none":
            badge = Gtk.Label(label="No driver")
            badge.add_css_class("error")
            badge.set_valign(Gtk.Align.CENTER)
            row.add_suffix(badge)
        elif comp.get("type") == "NPU":
            badge = Gtk.Label(label="Optional")
            badge.add_css_class("dim-label")
            badge.set_valign(Gtk.Align.CENTER)
            row.add_suffix(badge)
        elif missing:
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

        if comp["type"] == "GPU" and comp["vendor"] == "intel":
            opts = Gtk.StringList.new(["i915", "xe"])
            drop = Gtk.DropDown(model=opts)
            drop.set_selected(1 if self._current_driver == "xe" else 0)
            drop.set_valign(Gtk.Align.CENTER)
            drop.connect("notify::selected", self._on_dropdown_driver_switch, drop)
            row.add_suffix(drop)

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

    def _build_advanced_section(self) -> None:
        group = Adw.PreferencesGroup(title="Advanced")
        group.set_description("Modprobe blacklists, modules-load and live module control")

        if not self._can_sudo:
            row = Adw.ActionRow(title="Elevated access required")
            row.set_subtitle("Join the wheel/sudo group to manage kernel modules")
            group.add(row)
            self._content_box.append(group)
            return

        bl_expander = Adw.ExpanderRow(title="Blacklisted modules")
        bl_expander.add_prefix(Gtk.Image.new_from_icon_name("action-unavailable-symbolic"))
        if self._blacklisted:
            for mod in self._blacklisted:
                bl_expander.add_row(self._make_blacklist_row(mod))
        else:
            empty = Adw.ActionRow(title="No modules blacklisted")
            empty.set_activatable(False)
            bl_expander.add_row(empty)
        group.add(bl_expander)

        bl_add_row = Adw.ActionRow(title="Blacklist a module", subtitle="Pick a module to blacklist")
        bl_add_row.add_suffix(self._module_picker("", self._on_pick_blacklist))
        group.add(bl_add_row)

        load_expander = Adw.ExpanderRow(title="Modules loaded at boot (modules-load.d)")
        load_expander.add_prefix(Gtk.Image.new_from_icon_name("system-run-symbolic"))
        if self._modules_load:
            for mod in self._modules_load:
                load_expander.add_row(self._make_modules_load_row(mod))
        else:
            empty = Adw.ActionRow(title="No extra modules forced at boot")
            empty.set_activatable(False)
            load_expander.add_row(empty)
        group.add(load_expander)

        boot_add_row = Adw.ActionRow(title="Load module at boot", subtitle="Pick a module to load on startup")
        boot_add_row.add_suffix(self._module_picker("", self._on_pick_boot))
        group.add(boot_add_row)

        files_expander = Adw.ExpanderRow(title="modprobe.d configuration files")
        files_expander.add_prefix(Gtk.Image.new_from_icon_name("text-x-script-symbolic"))
        for f in self._modprobe_files:
            files_expander.add_row(self._make_file_row(f))
        if not self._modprobe_files:
            empty = Adw.ActionRow(title="No modprobe.d files")
            empty.set_activatable(False)
            files_expander.add_row(empty)
        group.add(files_expander)

        self._content_box.append(group)

    def _make_blacklist_row(self, mod: str) -> Adw.ActionRow:
        row = Adw.ActionRow(title=mod, subtitle="blacklisted in /etc/modprobe.d")
        rm_btn = Gtk.Button(icon_name="edit-delete-symbolic")
        rm_btn.set_tooltip_text("Remove from blacklist")
        rm_btn.add_css_class("flat")
        rm_btn.connect("clicked", lambda _b, m=mod: self._pkexec_action(
            ["--blacklist-remove", m],
            success=f"Unblacklisted {m}", refresh=True,
        ))
        row.add_suffix(rm_btn)
        return row

    def _make_modules_load_row(self, mod: str) -> Adw.ActionRow:
        row = Adw.ActionRow(title=mod, subtitle="loaded at boot")
        rm_btn = Gtk.Button(icon_name="edit-delete-symbolic")
        rm_btn.set_tooltip_text("Remove from boot load")
        rm_btn.add_css_class("flat")
        rm_btn.connect("clicked", lambda _b, m=mod: self._pkexec_action(
            ["--modules-load-remove", m],
            success=f"Removed {m} from boot load", refresh=True,
        ))
        row.add_suffix(rm_btn)
        return row

    def _make_file_row(self, f: dict) -> Adw.ActionRow:
        name = f.get("name", "")
        content = "\n".join(f.get("lines", [])) or "(empty)"
        row = Adw.ActionRow(title=name)
        sub = Gtk.Label(label=content)
        sub.set_wrap(True)
        sub.set_xalign(0.0)
        sub.set_max_width_chars(60)
        sub.add_css_class("dim-label")
        sub.add_css_class("caption")
        sub.set_margin_top(4)
        row.add_suffix(sub)
        row.set_activatable(False)
        return row

    _MODULE_ICONS = {
        "network": "network-wireless-symbolic",
        "display": "video-display-symbolic",
        "media": "camera-video-symbolic",
        "input": "input-keyboard-symbolic",
        "audio": "audio-speakers-symbolic",
        "bluetooth": "bluetooth-symbolic",
        "storage": "drive-harddisk-symbolic",
        "usb": "usb-symbolic",
        "serial": "serial-symbolic",
        "hid": "input-gaming-symbolic",
        "thermal": "thermometer-symbolic",
        "crypto": "security-high-symbolic",
        "filesystem": "folder-symbolic",
        "arch": "cpu-symbolic",
        "dkms": "application-x-addon-symbolic",
        "staging": "dialog-warning-symbolic",
        "other": "application-x-executable-symbolic",
    }

    def _module_icon(self, category: str) -> Gtk.Image:
        icon = Gtk.Image.new_from_icon_name(self._MODULE_ICONS.get(category, "application-x-executable-symbolic"))
        icon.set_pixel_size(16)
        return icon

    def _module_picker(self, current: str, on_pick) -> Gtk.Button:
        _PAGE = 25
        btn = Gtk.Button(label=current or "Choose module\u2026")
        btn.set_valign(Gtk.Align.CENTER)
        btn.set_size_request(-1, 28)
        btn.set_tooltip_text("Choose a kernel module\u2026")

        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search modules\u2026")
        search.set_hexpand(True)

        categories = ["all"] + [c for c in self._category_names() if c != "all"]
        cat_model = Gtk.StringList.new([c.title() for c in categories])
        cat_dd = Gtk.DropDown(model=cat_model)
        cat_dd.set_selected(0)
        cat_dd.set_tooltip_text("Filter by category")

        search_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        search_row.set_margin_top(8)
        search_row.set_margin_start(8)
        search_row.set_margin_end(8)
        search_row.set_margin_bottom(4)
        search_row.append(search)
        search_row.append(cat_dd)

        picker_list = Gtk.ListBox()
        picker_list.set_selection_mode(Gtk.SelectionMode.SINGLE)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(picker_list)
        scrolled.set_min_content_height(200)
        scrolled.set_max_content_height(320)
        scrolled.set_vexpand(True)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        vbox.set_size_request(360, -1)
        vbox.append(search_row)
        vbox.append(scrolled)

        popover = Gtk.Popover()
        popover.set_parent(btn)
        popover.set_child(vbox)

        state = {
            "search": search, "cat": cat_dd, "list": picker_list,
            "scrolled": scrolled, "popover": popover, "on_pick": on_pick,
            "page": 0, "query": "", "category": "all", "done": False,
        }

        def matches_all() -> list[dict]:
            q = state["query"].strip().lower()
            cat = state["category"]
            result = []
            for m in self._all_modules:
                if cat != "all" and m.get("category", "other") != cat:
                    continue
                if q and q not in m["name"].lower():
                    continue
                result.append(m)
            return result

        def append_chunk() -> None:
            matches = matches_all()
            total = len(matches)
            if total == 0:
                empty = Gtk.Label(label="No modules found")
                empty.add_css_class("dim-label")
                empty.set_margin_top(12)
                empty.set_margin_bottom(12)
                empty.set_halign(Gtk.Align.CENTER)
                picker_list.append(empty)
                state["done"] = True
                return
            start = state["page"] * _PAGE
            end = min(start + _PAGE, total)
            chunk = matches[start:end]
            state["done"] = end >= total
            self._load_descs(chunk)
            existing = set()
            child = picker_list.get_first_child()
            while child is not None:
                existing.add(child.get_title())
                child = child.get_next_sibling()
            for m in chunk:
                if m["name"] in existing:
                    continue
                picker_list.append(self._make_module_row(m))
            if not state["done"]:
                GLib.idle_add(load_more_if_needed)

        def fill() -> None:
            while child := picker_list.get_first_child():
                picker_list.remove(child)
            state["page"] = 0
            state["done"] = False
            append_chunk()

        def load_more_if_needed() -> None:
            if state["done"]:
                return
            adj = scrolled.get_vadjustment()
            if adj is not None and adj.get_upper() - (adj.get_value() + adj.get_page_size()) < 40:
                state["page"] += 1
                append_chunk()

        def on_search_changed(_e) -> None:
            state["query"] = search.get_text()
            fill()

        def on_cat_changed(_d, _pspec) -> None:
            idx = cat_dd.get_selected()
            state["category"] = categories[idx] if 0 <= idx < len(categories) else "all"
            fill()

        def on_row_activated(_list, row: Gtk.ListBoxRow) -> None:
            mod = row.get_title()
            popover.popdown()
            on_pick(mod)

        adj = scrolled.get_vadjustment()
        if adj is not None:
            adj.connect("value-changed", lambda _a: load_more_if_needed())

        search.connect("search-changed", on_search_changed)
        cat_dd.connect("notify::selected", on_cat_changed)
        picker_list.connect("row-activated", on_row_activated)
        btn.connect("clicked", lambda _b: self._toggle_picker(popover, fill))
        popover.connect("closed", lambda _p: search.set_text(""))
        return btn

    def _toggle_picker(self, popover: Gtk.Popover, fill) -> None:
        if popover.get_visible():
            popover.popdown()
        else:
            fill()
            popover.popup()
    def _category_names(self) -> list[str]:
        names = {m.get("category", "other") for m in self._all_modules}
        return sorted(names) or ["other"]

    def _load_descs(self, chunk: list[dict]) -> None:
        names = [m["name"] for m in chunk if m["name"] not in self._module_desc_cache]
        if not names:
            return
        out = _run(["--module-descs", *names])
        for line in out.splitlines():
            if line.startswith("DESC|"):
                _, name, desc = line.split("|", 2)
                self._module_desc_cache.setdefault(name, {})["desc"] = desc
        for name in names:
            self._module_desc_cache.setdefault(name, {})

    def _make_module_row(self, m: dict) -> Adw.ActionRow:
        row = Adw.ActionRow(title=m["name"])
        row.add_css_class("module-picker-row")
        row.add_prefix(self._module_icon(m.get("category", "other")))
        desc = self._module_desc_cache.get(m["name"], {}).get("desc", "")
        if desc:
            row.set_subtitle(desc[:80] + ("\u2026" if len(desc) > 80 else ""))
        info_btn = Gtk.Button(icon_name="help-about-symbolic")
        info_btn.add_css_class("flat")
        info_btn.set_tooltip_text("Module details")
        info_btn.set_size_request(-1, 28)
        info_btn.connect("clicked", lambda _b, mod=m: self._show_module_info(info_btn, mod))
        row.add_suffix(info_btn)
        row.set_activatable(True)
        return row

    def _show_module_info(self, anchor: Gtk.Widget, m: dict) -> None:
        info = dict(self._module_desc_cache.get(m["name"]) or {})
        if len(info) <= 1:
            full = _run(["--module-info", m["name"]])
            for line in full.splitlines():
                if "|" in line:
                    k, _, v = line.partition("|")
                    info[k.lower()] = v
            self._module_desc_cache[m["name"]] = info
        lines = []
        lines.append(f"<b>{GLib.markup_escape_text(m['name'])}</b>")
        if info.get("desc"):
            lines.append(GLib.markup_escape_text(info["desc"]))
        fields = [
            ("Author", "author"), ("License", "license"), ("Version", "version"),
            ("Depends", "depends"), ("Firmware", "firmware"), ("Built-in", "builtin"),
            ("Category", "category"),
        ]
        for label, key in fields:
            val = info.get(key)
            if val:
                lines.append(f"<b>{GLib.markup_escape_text(label)}:</b> {GLib.markup_escape_text(val)}")
        body = "\n".join(lines)
        pop = Gtk.Popover()
        pop.set_parent(anchor)
        label = Gtk.Label(label=body)
        label.set_use_markup(True)
        label.set_wrap(True)
        label.set_max_width_chars(60)
        label.set_margin_top(8)
        label.set_margin_bottom(8)
        label.set_margin_start(12)
        label.set_margin_end(12)
        pop.set_child(label)
        pop.popup()

    def _on_pick_blacklist(self, mod: str) -> None:
        self._validate_and_apply(mod, "blacklist")

    def _on_pick_boot(self, mod: str) -> None:
        self._validate_and_apply(mod, "boot")

    def _validate_and_apply(self, mod: str, kind: str) -> None:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", mod):
            self._window.show_toast("Invalid module name", timeout=4)
            return

        def check():
            res = _run(["--module-exists", mod])
            if res.startswith("EXISTS|"):
                canonical = res.split("|", 1)[1]
                if kind == "blacklist":
                    self._pkexec_action(["--blacklist-add", canonical], success=f"Blacklisted {canonical}", refresh=True)
                else:
                    self._pkexec_action(["--modules-load-add", canonical], success=f"Loading {canonical} at boot", refresh=True)
            else:
                GLib.idle_add(lambda: self._window.show_toast(f"Module not found: {mod}", timeout=4))

        threading.Thread(target=check, daemon=True).start()

    def _pkexec_action(self, args: list[str], success: str, refresh: bool = False) -> None:
        self._window.show_toast("Requesting elevated access\u2026", timeout=3)
        full_args = ["pkexec", "bash", _DRIVER_CORE, *args]

        def worker():
            try:
                r = subprocess.run(full_args, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
            except Exception as e:
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=str(e), timeout=6))
                return
            out = (r.stdout or "") + (r.stderr or "")
            if r.returncode == 0:
                GLib.idle_add(lambda: self._window.show_toast(success))
                if refresh:
                    GLib.idle_add(self._load_data)
            else:
                tail = "\n".join(out.strip().splitlines()[-8:])
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=tail or str(r.returncode), timeout=8))

        threading.Thread(target=worker, daemon=True).start()

    def _on_dropdown_driver_switch(self, _drop, _pspec, drop) -> None:
        idx = drop.get_selected()
        target = "xe" if idx == 1 else "i915"
        if target == self._current_driver:
            return
        self._run_terminal(f"retro driver switch {target}")
        self._window.show_toast(f"Switching to {target} driver in terminal\u2026", timeout=3)

    def _install_missing(self) -> None:
        if not self._missing_pkgs:
            self._window.show_toast("No missing drivers to install")
            return
        self._run_terminal("retro driver install")
        self._poll_main_install()

    def _poll_main_install(self, timeout_s: int = 120) -> None:
        deadline = time.time() + timeout_s

        def check():
            if time.time() > deadline:
                GLib.idle_add(self._delayed_refresh)
                return
            scan = _run(["--scan"])
            still_missing = False
            for line in scan.splitlines():
                if "|" in line and line.split("|", 6)[-1].strip():
                    still_missing = True
                    break
            if not still_missing:
                GLib.idle_add(self._delayed_refresh)
                return
            GLib.timeout_add(3000, check)
        GLib.timeout_add(1500, check)

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

    def _open_driver_bundles(self) -> None:
        dialog = DriverBundlesDialog(self._window, self)
        dialog.present(self._window)

    def missing_count(self) -> int:
        return len(self._missing_pkgs)
    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        self._dirty = False

    def discard(self) -> None:
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return iter([])

    def flush_pending(self) -> None:
        pass

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


class DriverBundlesDialog(Adw.Dialog):

    def __init__(self, window: "RetroSettingsWindow", page: DriverPage):
        super().__init__()
        self._window = window
        self._page = page
        self.set_title("Install Optional Drivers")
        self.set_content_width(560)
        self.set_content_height(440)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        close_btn = Gtk.Button(label="Close")
        close_btn.connect("clicked", lambda _b: self.close())
        header.pack_start(close_btn)
        toolbar.add_top_bar(header)

        self._listbox = Gtk.ListBox()
        self._listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._listbox.set_margin_top(8)
        self._listbox.set_margin_bottom(8)
        self._listbox.set_margin_start(8)
        self._listbox.set_margin_end(8)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_child(self._listbox)
        scrolled.set_vexpand(True)

        spinner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        spinner_box.set_valign(Gtk.Align.CENTER)
        spinner_box.set_halign(Gtk.Align.CENTER)
        spinner = Gtk.Spinner()
        spinner.set_size_request(28, 28)
        spinner.start()
        spinner_box.append(spinner)
        lbl = Gtk.Label(label="Loading optional drivers\u2026")
        lbl.add_css_class("dim-label")
        spinner_box.append(lbl)

        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        stack.add_named(scrolled, "list")
        stack.add_named(spinner_box, "spinner")
        stack.set_visible_child_name("spinner")
        self._stack = stack
        self._list_scrolled = scrolled

        clamp = Adw.Clamp()
        clamp.set_maximum_size(560)
        clamp.set_tightening_threshold(500)
        clamp.set_child(stack)

        toolbar.set_content(clamp)
        self.set_child(toolbar)
        self._clamp = clamp

        self._rows: dict[str, dict] = {}
        self._load()

    def _load(self) -> None:
        def worker():
            gaming = _run(["--profile-list", "gaming"])
            extra_missing = _run(["--extra-list"])
            extra_installed = _run(["--extra-installed"])
            GLib.idle_add(self._on_loaded, gaming, extra_missing, extra_installed)
        threading.Thread(target=worker, daemon=True).start()

    def _on_loaded(self, gaming: str, extra_missing: str, extra_installed: str) -> None:
        self._stack.set_visible_child_name("list")

        gaming_pkgs = self._parse_pkgs(gaming)

        def _split(s: str) -> list[str]:
            return s.split() if s.strip() and s.strip() != "NONE" else []

        installed_set = set(_split(extra_installed))
        extra_pkgs = []
        for p in sorted(set(_split(extra_missing)) | installed_set):
            extra_pkgs.append({
                "name": p,
                "version": "",
                "status": "installed" if p in installed_set else "missing",
            })
        extra_pkgs.sort(key=lambda d: d["name"])

        while child := self._listbox.get_first_child():
            self._listbox.remove(child)

        self._add_bundle_row(
            key="gaming",
            title="Gaming Drivers",
            subtitle="gamemode, gamescope, mangohud, vulkan-tools and GPU libs for gaming",
            icon="applications-games-symbolic",
            pkgs=gaming_pkgs,
            install_args=["--profile-install", "gaming"],
            remove_args=["--profile-remove", "gaming"],
        )
        self._add_bundle_row(
            key="extra",
            title="Extra Drivers",
            subtitle="AI / neural compute and NPU packages not installed by default",
            icon="system-run-symbolic",
            pkgs=extra_pkgs,
            install_args=["--install-extra"],
            remove_args=["--extra-uninstall", "--yes"],
        )

    @staticmethod
    def _parse_pkgs(raw: str) -> list[dict]:
        result = []
        for line in raw.splitlines():
            if not line.startswith("PKG|"):
                continue
            parts = line.split("|")
            if len(parts) < 5:
                continue
            name = parts[2]
            ver = parts[3]
            status = parts[4]
            result.append({"name": name, "version": ver, "status": status})
        return result

    def _add_bundle_row(self, key: str, title: str, subtitle: str, icon: str, pkgs: list[dict], install_args: list[str], remove_args: list[str]) -> None:
        installed = sum(1 for p in pkgs if p["status"] == "installed")
        total = len(pkgs)
        missing = total - installed

        exp = Adw.ExpanderRow(title=title)
        exp.add_prefix(Gtk.Image.new_from_icon_name(icon))
        exp.set_subtitle(f"{installed}/{total} installed \u00b7 {missing} missing")

        for p in pkgs:
            sub = Adw.ActionRow(title=p["name"], subtitle=p["version"] or "not installed")
            badge = Gtk.Label(label="Installed" if p["status"] == "installed" else "Missing")
            badge.add_css_class("success" if p["status"] == "installed" else "error")
            badge.set_valign(Gtk.Align.CENTER)
            sub.add_suffix(badge)
            sub.set_activatable(False)
            exp.add_row(sub)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        install_btn = Gtk.Button(label="Install")
        install_btn.add_css_class("suggested-action")
        install_btn.set_valign(Gtk.Align.CENTER)
        install_btn.set_visible(missing > 0 or total == 0)
        install_btn.connect("clicked", lambda _b: self._run_action(key, install_args, "install"))
        box.append(install_btn)

        remove_btn = Gtk.Button(label="Uninstall")
        remove_btn.add_css_class("destructive-action")
        remove_btn.set_valign(Gtk.Align.CENTER)
        remove_btn.set_visible(installed > 0)
        remove_btn.connect("clicked", lambda _b: self._run_action(key, remove_args, "remove"))
        box.append(remove_btn)

        exp.add_suffix(box)
        self._listbox.append(exp)
        self._rows[key] = {"expander": exp, "install_btn": install_btn, "remove_btn": remove_btn, "pkgs": pkgs}

    def _run_action(self, key: str, args: list[str], kind: str) -> None:
        self._window.show_toast(f"Requesting elevated access\u2026", timeout=3)
        full_args = ["pkexec", "bash", _DRIVER_CORE, *args]

        def worker():
            try:
                r = subprocess.run(full_args, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
            except Exception as e:
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=str(e), timeout=6))
                return
            out = (r.stdout or "") + (r.stderr or "")
            ok = r.returncode == 0
            msg = f"Optional drivers installed" if kind == "install" else f"Optional drivers removed"
            if ok:
                GLib.idle_add(lambda: self._window.show_toast(msg, timeout=4))
            else:
                tail = "\n".join(out.strip().splitlines()[-8:])
                GLib.idle_add(lambda: self._window.show_bug_toast("Action failed", detail=tail or str(r.returncode), timeout=8))
            GLib.idle_add(self._refresh_after_action)

        threading.Thread(target=worker, daemon=True).start()

    def _refresh_after_action(self) -> None:
        self._load()
        self._page._delayed_refresh()

