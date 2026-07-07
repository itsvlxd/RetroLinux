"""Audio management page — volume, devices, EQ, EasyEffects, stutter fix."""

import json
import os
import subprocess
import threading
from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk, Pango

from settings.core.pending import PendingChange
from settings.core.spectrum_engine import SpectrumEngine
from settings.ui import make_page_layout
from settings.ui.row_actions import RowActions
from settings.ui.spectrum import AudioSpectrumWidget

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_AUDIO_CORE = os.path.join(os.environ.get("RETRO_DIR", "/opt/retrolinux"), "scripts", "audio_core.sh")
_AUDIO_ICON = "audio-volume-high-symbolic"

_CRASH_DEFAULTS = {
    "AUDIO_RESTART_ON_CRASH": "true",
    "AUDIO_RESTART_ON_CRASH_THRESHOLD": "20",
    "AUDIO_RESTART_ON_CRASH_NOTIFY": "true",
}


def _find_mic_source() -> str:
    """Find the first hardware mic PulseAudio source name, skipping EasyEffects and monitors."""
    try:
        r = subprocess.run(["pactl", "list", "sources", "short"],
                           capture_output=True, text=True, timeout=5)
        for line in r.stdout.strip().splitlines():
            parts = line.split()
            if len(parts) < 2:
                continue
            name = parts[1]
            if "Easy Effects" in name or "easyeffects" in name or ".monitor" in name:
                continue
            return name
    except Exception:
        pass
    return "@DEFAULT_SOURCE@"


def _make_device_factory() -> Gtk.SignalListItemFactory:
    """Factory for device combo items that truncates the start of long names."""
    factory = Gtk.SignalListItemFactory()

    def setup(_f, item):
        label = Gtk.Label(xalign=1.0)
        label.set_ellipsize(Pango.EllipsizeMode.START)
        label.set_max_width_chars(30)
        item.set_child(label)

    def bind(_f, item):
        label = item.get_child()
        label.set_text(item.get_item().get_string())

    factory.connect("setup", setup)
    factory.connect("bind", bind)
    return factory


class AudioPage:
    """Audio management — volume, output/input, priority, EQ, EasyEffects."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._dirty = False
        self._on_dirty_changed = None
        self._orig: dict[str, str] = {}
        self._pending: dict[str, str] = {}
        self._setting_value = False
        self._status: dict[str, str] = {}
        self._sinks: list[dict] = []
        self._sources: list[dict] = []
        self._profiles: list[str] = []
        self._tick_source = None
        self._spectrum_widget: AudioSpectrumWidget | None = None
        self._spectrum_engine: SpectrumEngine | None = None
        self._spectrum_in_widget: AudioSpectrumWidget | None = None
        self._spectrum_in_engine: SpectrumEngine | None = None

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar_view, _, self._content_box, _ = make_page_layout(header=header)

        add_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_btn.set_tooltip_text("Download EQ presets")
        add_btn.connect("clicked", lambda _b: self._show_download_dialog())
        header.pack_start(add_btn)

        self._load_data()

        # Output + Input spectrums side-by-side
        spectrum_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        spectrum_box.set_homogeneous(True)

        out_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        out_lbl = Gtk.Label(label="Output")
        out_lbl.set_xalign(0.5)
        out_lbl.add_css_class("heading")
        out_lbl.set_margin_top(8)
        out_col.append(out_lbl)
        out_col.append(self._build_spectrum_widget("out"))
        spectrum_box.append(out_col)

        in_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        in_lbl = Gtk.Label(label="Input")
        in_lbl.set_xalign(0.5)
        in_lbl.add_css_class("heading")
        in_lbl.set_margin_top(8)
        in_col.append(in_lbl)
        in_col.append(self._build_spectrum_widget("in"))
        spectrum_box.append(in_col)

        self._content_box.append(spectrum_box)

        # Audio Configuration (volume, devices, EQ)
        acg = Adw.PreferencesGroup(title="Audio Configuration")
        self._build_volume_controls(acg)
        self._build_eq_section(acg)
        self._content_box.append(acg)

        # Device priority (managed settings)
        pg = Adw.PreferencesGroup(title="Device Priority",
                                  description="Set preferred devices. Primary is restored when available; fallback is used when primary is not.")
        self._priority_rows: list[tuple] = []
        self._build_priority_section(pg)
        self._content_box.append(pg)

        # Advanced (EasyEffects + fix stutter)
        ag = Adw.PreferencesGroup(title="Advanced")
        self._build_crash_config(ag)
        self._build_ee_section(ag)
        self._build_advanced_section(ag)
        self._content_box.append(ag)

        self._tick_source = GLib.timeout_add(5000, self._tick)

        GLib.idle_add(self._refresh_managed)

        return toolbar_view

    # ── Data loading ──

    def _load_data(self) -> None:
        from lib.python.variable import get_var as _g

        self._status = {}
        try:
            r = subprocess.run(
                ["bash", _AUDIO_CORE, "--status"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            for line in r.stdout.strip().splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    self._status[k] = v
        except Exception:
            pass

        self._sinks = []
        try:
            r = subprocess.run(
                ["bash", _AUDIO_CORE, "--get-sinks"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            for sid in r.stdout.strip().splitlines():
                sid = sid.strip()
                if not sid:
                    continue
                try:
                    name = subprocess.run(
                        ["bash", _AUDIO_CORE, "--get-sink-name", sid],
                        capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
                    ).stdout.strip()
                    pname = subprocess.run(
                        ["bash", _AUDIO_CORE, "--get-sink-persistent-name", sid],
                        capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
                    ).stdout.strip()
                except Exception:
                    continue
                self._sinks.append({"id": sid, "name": name or sid, "persistent": pname})
        except Exception:
            pass

        self._sources = []
        try:
            r = subprocess.run(
                ["bash", _AUDIO_CORE, "--get-sources"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            for sid in r.stdout.strip().splitlines():
                sid = sid.strip()
                if not sid:
                    continue
                try:
                    name = subprocess.run(
                        ["bash", _AUDIO_CORE, "--get-source-name", sid],
                        capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
                    ).stdout.strip()
                    pname = subprocess.run(
                        ["bash", _AUDIO_CORE, "--get-source-persistent-name", sid],
                        capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
                    ).stdout.strip()
                except Exception:
                    continue
                self._sources.append({"id": sid, "name": name or sid, "persistent": pname})
        except Exception:
            pass

        # Priority from variables
        self._orig = {
            "primary_sink": _g("AUDIO_PRIMARY_SINK", ""),
            "fallback_sink": _g("AUDIO_FALLBACK_SINK", ""),
            "primary_source": _g("AUDIO_PRIMARY_SOURCE", ""),
            "fallback_source": _g("AUDIO_FALLBACK_SOURCE", ""),
            "eq_preset": _g("AUDIO_EQ_PRESET", ""),
            "crash_restart": _g("AUDIO_RESTART_ON_CRASH", _CRASH_DEFAULTS["AUDIO_RESTART_ON_CRASH"]),
            "crash_threshold": _g("AUDIO_RESTART_ON_CRASH_THRESHOLD", _CRASH_DEFAULTS["AUDIO_RESTART_ON_CRASH_THRESHOLD"]),
            "crash_notify": _g("AUDIO_RESTART_ON_CRASH_NOTIFY", _CRASH_DEFAULTS["AUDIO_RESTART_ON_CRASH_NOTIFY"]),
        }
        self._status["eq_preset"] = self._orig["eq_preset"]

        # Merge configured-but-disconnected priority devices into lists
        existing_sink_persist = {d["persistent"] for d in self._sinks if d["persistent"]}
        existing_src_persist = {d["persistent"] for d in self._sources if d["persistent"]}
        for var_key in ("primary_sink", "fallback_sink"):
            pname = self._orig.get(var_key, "")
            if pname and pname not in existing_sink_persist:
                self._sinks.append({"id": "", "name": pname, "persistent": pname})
                existing_sink_persist.add(pname)
        for var_key in ("primary_source", "fallback_source"):
            pname = self._orig.get(var_key, "")
            if pname and pname not in existing_src_persist:
                self._sources.append({"id": "", "name": pname, "persistent": pname})
                existing_src_persist.add(pname)
        self._profiles = []
        try:
            r = subprocess.run(
                ["bash", _AUDIO_CORE, "--eq-list"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            self._profiles = sorted(l.strip() for l in r.stdout.strip().splitlines() if l.strip())
        except Exception:
            pass

        self._cur_output_idx = 0
        self._cur_input_idx = 0
        cur_sink = self._status.get("sink", "")
        cur_source = self._status.get("source", "")
        for i, sink in enumerate(self._sinks):
            if sink["id"] == cur_sink:
                self._cur_output_idx = i
                break
        for i, src in enumerate(self._sources):
            if src["id"] == cur_source:
                self._cur_input_idx = i
                break

    def _full_refresh(self) -> None:
        self._load_data()
        GLib.idle_add(self._rebuild_priority_models)
        GLib.idle_add(self._rebuild_eq_list)
        GLib.idle_add(self._rebuild_volume_models)
        GLib.idle_add(self._refresh_managed)

    # ── Volume controls (immediate) ──

    def _build_volume_controls(self, group: Adw.PreferencesGroup) -> None:
        vol_str = self._status.get("sink_volume", "0")
        try:
            vol_val = int(vol_str)
        except ValueError:
            vol_val = 0

        adj = Gtk.Adjustment(value=float(vol_val), lower=0, upper=100, step_increment=1, page_increment=10)
        spin = Gtk.SpinButton(adjustment=adj, digits=0)
        spin.set_valign(Gtk.Align.CENTER)
        spin.connect("notify::value", self._on_volume_spin)
        pct = Gtk.Label(label="%"); pct.set_valign(Gtk.Align.CENTER); pct.set_opacity(0.7); pct.set_margin_start(4)
        vol_row = Adw.ActionRow(title="Volume", subtitle="Output volume level")
        vol_row.add_suffix(pct); vol_row.add_suffix(spin)
        group.add(vol_row)
        self._volume_spin = spin

        mic_vol_str = self._status.get("source_volume", "0")
        try:
            mic_vol_val = int(mic_vol_str)
        except ValueError:
            mic_vol_val = 0
        mic_adj = Gtk.Adjustment(value=float(mic_vol_val), lower=0, upper=100, step_increment=1, page_increment=10)
        mic_spin = Gtk.SpinButton(adjustment=mic_adj, digits=0)
        mic_spin.set_valign(Gtk.Align.CENTER)
        mic_spin.connect("notify::value", self._on_mic_volume_spin)
        mic_pct = Gtk.Label(label="%"); mic_pct.set_valign(Gtk.Align.CENTER); mic_pct.set_opacity(0.7); mic_pct.set_margin_start(4)
        mic_vol_row = Adw.ActionRow(title="Mic volume", subtitle="Input volume level")
        mic_vol_row.add_suffix(mic_pct); mic_vol_row.add_suffix(mic_spin)
        group.add(mic_vol_row)
        self._mic_volume_spin = mic_spin

        # Mute switches — read directly from PipeWire aliases (stable across restarts)
        def _read_mute(alias: str) -> bool:
            try:
                r = subprocess.run(
                    ["wpctl", "get-volume", alias],
                    capture_output=True, text=True, timeout=3,
                    stdin=subprocess.DEVNULL,
                )
                return "[MUTED]" in r.stdout
            except Exception:
                return False

        is_muted = _read_mute("@DEFAULT_AUDIO_SINK@")
        mute_row = Adw.SwitchRow(title="Mute output", subtitle="Toggle output mute")
        mute_row.set_active(is_muted)
        mute_row.connect("notify::active", self._on_mute_switched)
        group.add(mute_row)
        self._mute_switch = mute_row

        is_mic_muted = _read_mute("@DEFAULT_AUDIO_SOURCE@")
        mic_row = Adw.SwitchRow(title="Mute microphone", subtitle="Toggle microphone mute")
        mic_row.set_active(is_mic_muted)
        mic_row.connect("notify::active", self._on_mic_mute_switched)
        group.add(mic_row)
        self._mic_mute_switch = mic_row

        self._rebuild_volume_models(group)

    def _rebuild_volume_models(self, group: Adw.PreferencesGroup | None = None) -> None:
        sink_names = [d["name"] for d in self._sinks] if self._sinks else ["No devices"]
        src_names = [d["name"] for d in self._sources] if self._sources else ["No devices"]

        if hasattr(self, "_output_combo"):
            model = Gtk.StringList.new(sink_names)
            self._output_combo.set_model(model)
            if self._cur_output_idx < len(sink_names):
                self._output_combo.set_selected(self._cur_output_idx)
            return

        model = Gtk.StringList.new(sink_names)
        self._output_combo = Adw.ComboRow(title="Output device", subtitle="Default audio sink",
                                          model=model)
        self._output_combo.set_size_request(500, -1)
        self._output_combo.set_factory(_make_device_factory())
        self._output_combo.set_list_factory(_make_device_factory())
        self._output_combo.set_selected(min(self._cur_output_idx, len(sink_names) - 1))
        self._output_combo.connect("notify::selected", self._on_output_changed)
        if group:
            group.add(self._output_combo)

        model2 = Gtk.StringList.new(src_names)
        self._input_combo = Adw.ComboRow(title="Input device", subtitle="Default audio source",
                                         model=model2)
        self._input_combo.set_size_request(500, -1)
        self._input_combo.set_factory(_make_device_factory())
        self._input_combo.set_list_factory(_make_device_factory())
        self._input_combo.set_selected(min(self._cur_input_idx, len(src_names) - 1))
        self._input_combo.connect("notify::selected", self._on_input_changed)
        if group:
            group.add(self._input_combo)

    def _on_volume_spin(self, spin: Gtk.SpinButton, _pspec) -> None:
        if self._setting_value:
            return
        val = int(spin.get_value())
        subprocess.run(
            ["bash", _AUDIO_CORE, "--set-volume", str(val)],
            capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
        )

    def _on_mic_volume_spin(self, spin: Gtk.SpinButton, _pspec) -> None:
        if self._setting_value:
            return
        val = int(spin.get_value())
        subprocess.run(
            ["bash", _AUDIO_CORE, "--set-source-volume", str(val)],
            capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
        )

    def _on_mute_switched(self, sw: Adw.SwitchRow, _pspec) -> None:
        state = "true" if sw.get_active() else "false"
        subprocess.run(
            ["bash", _AUDIO_CORE, "--set-mute", state],
            capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
        )

    def _on_mic_mute_switched(self, sw: Adw.SwitchRow, _pspec) -> None:
        state = "true" if sw.get_active() else "false"
        subprocess.run(
            ["bash", _AUDIO_CORE, "--set-mic-mute", state],
            capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
        )

    def _on_output_changed(self, combo: Adw.ComboRow, _pspec) -> None:
        idx = combo.get_selected()
        if 0 <= idx < len(self._sinks):
            sid = self._sinks[idx]["id"]
            subprocess.run(
                ["bash", _AUDIO_CORE, "--set-sink", sid],
                capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
            )

    def _on_input_changed(self, combo: Adw.ComboRow, _pspec) -> None:
        idx = combo.get_selected()
        if 0 <= idx < len(self._sources):
            sid = self._sources[idx]["id"]
            subprocess.run(
                ["bash", _AUDIO_CORE, "--set-source", sid],
                capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
            )

    # ── Spectrum visualizer ──

    @staticmethod
    def _make_section_label(text: str) -> Gtk.Label:
        lbl = Gtk.Label(label=text)
        lbl.set_xalign(0)
        lbl.set_margin_top(16)
        lbl.set_margin_start(4)
        lbl.add_css_class("heading")
        return lbl

    def _build_spectrum_widget(self, kind: str) -> AudioSpectrumWidget:
        widget = AudioSpectrumWidget()
        if kind == "out":
            self._spectrum_widget = widget
            self._start_spectrum_engine("out")
        else:
            self._spectrum_in_widget = widget
            self._start_spectrum_engine("in")
        return widget

    def _start_spectrum_engine(self, kind: str) -> None:
        if kind == "out":
            if self._spectrum_engine:
                self._stop_spectrum_engine("out")
            pipeline = (
                "pulsesrc device=@DEFAULT_MONITOR@ "
                "! audioconvert ! audio/x-raw,format=F32LE,channels=1 "
                "! spectrum bands=512 interval=40000000 post-messages=true "
                "! fakesink"
            )
            self._spectrum_engine = SpectrumEngine(
                lambda b: self._on_spectrum_data(b, "out"),
                pipeline,
                scale_floor=0.08,
            )
            self._spectrum_engine.start()
        else:
            if self._spectrum_in_engine:
                self._stop_spectrum_engine("in")
            mic_source = _find_mic_source()
            pipeline = (
                f"pulsesrc device='{mic_source}' "
                "! audioconvert ! audio/x-raw,format=F32LE,channels=1 "
                "! spectrum bands=512 interval=40000000 post-messages=true "
                "! fakesink"
            )
            self._spectrum_in_engine = SpectrumEngine(
                lambda b: self._on_spectrum_data(b, "in"),
                pipeline,
                db_floor=-65,
                noise_gate=0.12,
                scale_floor=1.2,
            )
            self._spectrum_in_engine.start()

    def _stop_spectrum_engine(self, kind: str) -> None:
        if kind == "out":
            if self._spectrum_engine:
                self._spectrum_engine.stop()
                self._spectrum_engine = None
        else:
            if self._spectrum_in_engine:
                self._spectrum_in_engine.stop()
                self._spectrum_in_engine = None

    def _on_spectrum_data(self, bars: list[float], kind: str) -> None:
        if kind == "out" and self._spectrum_widget:
            self._spectrum_widget.set_bars(bars)
        elif kind == "in" and self._spectrum_in_widget:
            self._spectrum_in_widget.set_bars(bars)

    # ── Device priority (managed) ──

    def _build_priority_section(self, group: Adw.PreferencesGroup) -> None:
        self._priority_rows = []

        for var, key, label, subtitle, dev_list in [
            ("AUDIO_PRIMARY_SINK", "primary_sink", "Primary Output",
             "Preferred output device (restored when available)", self._sinks),
            ("AUDIO_FALLBACK_SINK", "fallback_sink", "Fallback Output",
             "Used when primary is unavailable", self._sinks),
            ("AUDIO_PRIMARY_SOURCE", "primary_source", "Primary Input",
             "Preferred input device (restored when available)", self._sources),
            ("AUDIO_FALLBACK_SOURCE", "fallback_source", "Fallback Input",
             "Used when primary is unavailable", self._sources),
        ]:
            is_fallback = "fallback" in key
            names = ["None (no fallback)"] + [d["name"] for d in dev_list] if is_fallback else [d["name"] for d in dev_list]
            model = Gtk.StringList.new(names)

            current = self._orig.get(key, "")
            sel = 0
            if is_fallback and not current:
                sel = 0
            elif current:
                found = False
                for i, d in enumerate(dev_list):
                    if d["persistent"] == current:
                        sel = i + (1 if is_fallback else 0)
                        found = True
                        break
                if not found:
                    sel = 0 if is_fallback else 0

            row = Adw.ComboRow(title=label, subtitle=subtitle, model=model)
            row.set_factory(_make_device_factory())
            row.set_list_factory(_make_device_factory())
            row.set_selected(sel)
            row.connect("notify::selected", self._on_priority_changed, var, key, dev_list, is_fallback)

            actions = RowActions(
                row,
                on_discard=lambda v=var, k=key: self._discard_priority(v, k),
                on_reset=lambda v=var, k=key: self._reset_priority(v, k),
            )
            row.add_suffix(actions.box)
            actions.reorder_first()
            group.add(row)

            self._priority_rows.append((var, key, row, actions, dev_list, is_fallback))

    def _on_priority_changed(self, combo: Adw.ComboRow, _pspec, var: str, key: str, dev_list: list[dict], is_fallback: bool) -> None:
        if self._setting_value:
            return
        idx = combo.get_selected()
        if is_fallback:
            if idx == 0:
                self._pending[var] = ""
            elif 0 <= idx - 1 < len(dev_list):
                self._pending[var] = dev_list[idx - 1]["persistent"]
        elif 0 <= idx < len(dev_list):
            self._pending[var] = dev_list[idx]["persistent"]
        self._dirty = True
        if self._on_dirty_changed:
            self._on_dirty_changed()
        GLib.idle_add(self._refresh_managed)

    def _discard_priority(self, var: str, key: str) -> None:
        from lib.python.variable import get_var as _g
        live = _g(var, "")
        self._set_priority_widget(key, live)
        self._pending.pop(var, None)
        self._check_dirty()
        self._refresh_managed()

    def _reset_priority(self, var: str, key: str) -> None:
        default = ""
        self._set_priority_widget(key, default)
        self._pending[var] = default
        self._dirty = True
        if self._on_dirty_changed:
            self._on_dirty_changed()
        self._refresh_managed()

    def _set_priority_widget(self, key: str, val: str) -> None:
        self._setting_value = True
        for var, pk, row, _actions, dev_list, is_fallback in self._priority_rows:
            if pk == key:
                if is_fallback:
                    if not val:
                        row.set_selected(0)
                    else:
                        for i, d in enumerate(dev_list):
                            if d["persistent"] == val:
                                row.set_selected(i + 1)
                                break
                        else:
                            row.set_selected(0)
                else:
                    for i, d in enumerate(dev_list):
                        if d["persistent"] == val:
                            row.set_selected(i)
                            break
                    else:
                        row.set_selected(0)
                break
        self._setting_value = False

    def _rebuild_priority_models(self) -> None:
        for var, key, row, actions, dev_list, is_fallback in self._priority_rows:
            names = ["None (no fallback)"] + [d["name"] for d in dev_list] if is_fallback else [d["name"] for d in dev_list]
            model = Gtk.StringList.new(names)
            row.set_model(model)
            current = self._orig.get(key, "")
            if is_fallback and not current:
                row.set_selected(0)
            elif current:
                found = False
                for i, d in enumerate(dev_list):
                    if d["persistent"] == current:
                        row.set_selected(i + (1 if is_fallback else 0))
                        found = True
                        break
                if not found:
                    row.set_selected(0 if is_fallback else 0)
            else:
                row.set_selected(0 if is_fallback else 0)

    # ── Managed indicators ──

    def _refresh_managed(self) -> None:
        from lib.python.variable import get_var as _g
        from lib.python.variable import get_module_default as _md
        for var, key, _row, actions, _dl, _fb in self._priority_rows:
            cur = self._pending.get(var, self._orig.get(key, ""))
            live = _g(var, "")
            default = _md(var) or ""
            is_managed = cur != default
            is_dirty = cur != live
            is_saved = live != default
            actions.update(is_managed=is_managed, is_dirty=is_dirty, is_saved=is_saved)
        for var, key, _widget, actions in self._crash_rows:
            cur = self._get_crash_cur(key)
            live = _g(var, _CRASH_DEFAULTS.get(var, ""))
            default = _CRASH_DEFAULTS.get(var, "")
            is_managed = cur != default
            is_dirty = cur != live
            is_saved = live != default
            actions.update(is_managed=is_managed, is_dirty=is_dirty, is_saved=is_saved)

    def _check_dirty(self) -> None:
        was = self._dirty
        self._dirty = bool(self._pending)
        if not self._dirty:
            for var, key, _widget, _actions in self._crash_rows:
                if self._get_crash_cur(key) != self._orig.get(key, ""):
                    self._dirty = True
                    break
        if was != self._dirty and self._on_dirty_changed:
            self._on_dirty_changed()

    # ── EQ profiles ──

    def _build_eq_section(self, group: Adw.PreferencesGroup) -> None:
        profile_names = ["None"] + [p.replace(".json", "") for p in self._profiles]
        model = Gtk.StringList.new(profile_names)
        current = self._status.get("eq_preset", "")
        sel = 0
        if current:
            for i, p in enumerate(self._profiles):
                display = p.replace(".json", "")
                if display == current:
                    sel = i + 1
                    break

        self._eq_combo = Adw.ComboRow(title="EQ Profile", subtitle="Select an equalizer preset to apply",
                                      model=model)
        self._eq_combo.set_selected(sel)
        self._eq_combo.set_size_request(500, -1)
        self._eq_combo.connect("notify::selected", self._on_eq_selected)
        group.add(self._eq_combo)

        delete_btn = Gtk.Button(icon_name="user-trash-symbolic")
        delete_btn.set_valign(Gtk.Align.CENTER)
        delete_btn.set_tooltip_text("Delete current profile")
        delete_btn.connect("clicked", lambda _b: self._delete_selected_eq())
        self._eq_combo.add_suffix(delete_btn)
        self._eq_combo.set_activatable_widget(None)

    def _rebuild_eq_list(self) -> None:
        if not hasattr(self, "_eq_combo"):
            return
        profile_names = ["None"] + [p.replace(".json", "") for p in self._profiles]
        model = Gtk.StringList.new(profile_names)
        self._eq_combo.set_model(model)
        current = self._status.get("eq_preset", "")
        sel = 0
        if current:
            for i, p in enumerate(self._profiles):
                display = p.replace(".json", "")
                if display == current:
                    sel = i + 1
                    break
        self._eq_combo.set_selected(sel)

    def _on_eq_selected(self, combo: Adw.ComboRow, _pspec) -> None:
        idx = combo.get_selected()
        if idx <= 0:
            return
        profile_name = self._profiles[idx - 1].replace(".json", "")
        subprocess.Popen(
            ["retro", "audio", "eq", profile_name],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        from lib.python.variable import set_var
        set_var("AUDIO_EQ_PRESET", profile_name)
        self._status["eq_preset"] = profile_name
        self._window.show_toast(f"Applied: {profile_name}")

    def _delete_selected_eq(self) -> None:
        idx = self._eq_combo.get_selected()
        if idx <= 0:
            self._window.show_toast("No profile selected", timeout=3)
            return
        profile = self._profiles[idx - 1]
        from settings.ui import confirm

        def do_delete():
            eq_dir = os.path.expanduser("~/.local/share/easyeffects/output")
            found = False
            for f in os.listdir(eq_dir):
                if f == profile or f == f"{profile}.json":
                    os.remove(os.path.join(eq_dir, f))
                    found = True
                    break
            if found:
                self._window.show_toast(f"Deleted {profile.replace('.json', '')}")
                self._full_refresh()
            else:
                self._window.show_toast("Profile not found", timeout=5)

        confirm(
            self._window,
            heading=f"Delete EQ profile \u201c{profile.replace('.json', '')}\u201d?",
            body="This will permanently remove the profile file.",
            label="Delete",
            on_confirm=do_delete,
        )

    def _show_download_dialog(self) -> None:
        repos = [
            ("JackHack96", "Popular gaming EQ presets"),
            ("wwmm", "Official EasyEffects repo"),
            ("Bundy01", "Various audio profiles"),
            ("Digitalone1", "DTS/Atmos alternatives"),
            ("ShadowOne333", "Gaming presets"),
        ]

        dialog = Adw.Dialog()
        dialog.set_title("Download EQ Presets")
        dialog.set_content_width(500)
        dialog.set_content_height(350)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        close_btn = Gtk.Button(label="Close")
        close_btn.connect("clicked", lambda _b: dialog.close())
        header.pack_start(close_btn)
        toolbar.add_top_bar(header)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(500)
        clamp.set_tightening_threshold(400)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        label = Gtk.Label(label="Choose a repository to download EQ presets from:")
        label.set_halign(Gtk.Align.START)
        label.add_css_class("dim-label")
        box.append(label)

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)

        for repo, desc in repos:
            row = Adw.ActionRow(title=repo, subtitle=desc)
            btn = Gtk.Button(label="Download")
            btn.add_css_class("suggested-action")
            btn.set_valign(Gtk.Align.CENTER)
            btn.connect("clicked", lambda _b, r=repo: (dialog.close(), self._do_download(r)))
            row.add_suffix(btn)
            listbox.append(row)

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
        dialog.present(self._window)

    def _do_download(self, repo: str) -> None:
        self._window.show_toast(f"Downloading presets from {repo}\u2026")
        subprocess.Popen(
            ["bash", _AUDIO_CORE, "--eq-download", repo],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        GLib.timeout_add(5000, self._full_refresh)

    # ── EasyEffects ──

    def _build_ee_section(self, group: Adw.PreferencesGroup) -> None:
        ee_status = self._status.get("easyeffects", "Stopped")
        ee_lbl = Gtk.Label(label=ee_status)
        ee_lbl.set_valign(Gtk.Align.CENTER)
        ee_lbl.add_css_class("badge")

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        btn_box.set_valign(Gtk.Align.CENTER)

        start_btn = Gtk.Button(label="Start")
        start_btn.set_sensitive(ee_status != "Running")
        start_btn.connect("clicked", lambda _b: self._ee_action("start"))
        btn_box.append(start_btn)

        stop_btn = Gtk.Button(label="Stop")
        stop_btn.set_sensitive(ee_status == "Running")
        stop_btn.connect("clicked", lambda _b: self._ee_action("stop"))
        btn_box.append(stop_btn)

        restart_btn = Gtk.Button(label="Restart")
        restart_btn.add_css_class("suggested-action")
        restart_btn.connect("clicked", lambda _b: self._ee_action("restart"))
        btn_box.append(restart_btn)

        open_btn = Gtk.Button(icon_name="window-new-symbolic")
        open_btn.set_tooltip_text("Open EasyEffects GUI")
        open_btn.connect("clicked", lambda _b: self._open_easyeffects())
        btn_box.append(open_btn)

        row = Adw.ActionRow(title="EasyEffects", subtitle="Audio processing engine — EQ, noise reduction, spatial audio")
        suffix_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        suffix_box.set_valign(Gtk.Align.CENTER)
        suffix_box.append(ee_lbl)
        suffix_box.append(btn_box)
        row.add_suffix(suffix_box)
        group.add(row)
        self._ee_status_lbl = ee_lbl
        self._ee_start_btn = start_btn
        self._ee_stop_btn = stop_btn

    def _ee_action(self, action: str) -> None:
        try:
            if action == "restart":
                subprocess.run(
                    ["bash", _AUDIO_CORE, "--ee-stop"],
                    capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL,
                )
                import time; time.sleep(1)
                r = subprocess.run(
                    ["bash", _AUDIO_CORE, "--ee-start"],
                    capture_output=True, text=True, timeout=5, stdin=subprocess.DEVNULL,
                )
                if "Started" in r.stdout:
                    self._window.show_toast("EasyEffects restarted")
                else:
                    self._window.show_toast("Failed to restart EasyEffects", timeout=5)
            else:
                r = subprocess.run(
                    ["bash", _AUDIO_CORE, f"--ee-{action}"],
                    capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL,
                )
                if action == "start":
                    if "Already running" in r.stdout:
                        self._window.show_toast("EasyEffects is already running")
                    elif "Started" in r.stdout:
                        self._window.show_toast("EasyEffects started")
                    else:
                        self._window.show_toast("Failed to start EasyEffects", timeout=5)
                elif action == "stop":
                    if "Not running" in r.stdout:
                        self._window.show_toast("EasyEffects is not running")
                    elif "Stopped" in r.stdout:
                        self._window.show_toast("EasyEffects stopped")
                    else:
                        self._window.show_toast("Failed to stop EasyEffects", timeout=5)
        except Exception:
            self._window.show_toast(f"Failed to {action} EasyEffects", timeout=5)
        GLib.timeout_add(1000, self._update_ee_status)

    def _update_ee_status(self) -> bool:
        try:
            r = subprocess.run(
                ["bash", _AUDIO_CORE, "--status"],
                capture_output=True, text=True, timeout=3, stdin=subprocess.DEVNULL,
            )
            for line in r.stdout.strip().splitlines():
                if line.startswith("easyeffects:"):
                    status = line.split(":", 1)[1]
                    self._ee_status_lbl.set_label(status)
                    running = status == "Running"
                    if hasattr(self, "_ee_start_btn"):
                        self._ee_start_btn.set_sensitive(not running)
                    if hasattr(self, "_ee_stop_btn"):
                        self._ee_stop_btn.set_sensitive(running)
                    break
        except Exception:
            pass
        return False

    @staticmethod
    def _open_easyeffects() -> None:
        subprocess.Popen(
            ["easyeffects"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    # ── Advanced ──

    def _build_crash_config(self, group: Adw.PreferencesGroup) -> None:
        self._crash_rows: list[tuple] = []

        sw = Adw.SwitchRow(
            title="Audio Auto-restart on crash",
            subtitle="Restart EasyEffects daemon automatically when it crashes",
        )
        sw.set_active(self._orig.get("crash_restart", "true") == "true")
        sw.connect("notify::active", self._on_crash_switch, "AUDIO_RESTART_ON_CRASH", "crash_restart")
        group.add(sw)
        sa = RowActions(sw,
                        on_discard=lambda: self._discard_crash("AUDIO_RESTART_ON_CRASH", "crash_restart"),
                        on_reset=lambda: self._reset_crash("AUDIO_RESTART_ON_CRASH", "crash_restart"))
        sw.add_suffix(sa.box)
        sa.reorder_first()
        self._crash_rows.append(("AUDIO_RESTART_ON_CRASH", "crash_restart", sw, sa))

        adj = Gtk.Adjustment(value=float(self._orig.get("crash_threshold", "20")), lower=5, upper=120, step_increment=5, page_increment=10)
        spin = Gtk.SpinButton(adjustment=adj, digits=0)
        spin.set_valign(Gtk.Align.CENTER)
        spin.connect("notify::value", self._on_crash_spin)
        tr = Adw.ActionRow(title="Audio Restart delay", subtitle="Seconds to wait before restarting crashed daemon")
        tr.add_suffix(spin)
        group.add(tr)
        self._crash_spin = spin
        ta = RowActions(tr,
                        on_discard=lambda: self._discard_crash("AUDIO_RESTART_ON_CRASH_THRESHOLD", "crash_threshold"),
                        on_reset=lambda: self._reset_crash("AUDIO_RESTART_ON_CRASH_THRESHOLD", "crash_threshold"))
        tr.add_suffix(ta.box)
        ta.reorder_first()
        self._crash_rows.append(("AUDIO_RESTART_ON_CRASH_THRESHOLD", "crash_threshold", spin, ta))

        nsw = Adw.SwitchRow(
            title="Audio Crash notification",
            subtitle="Show a desktop notification when EasyEffects is restarted",
        )
        nsw.set_active(self._orig.get("crash_notify", "true") == "true")
        nsw.connect("notify::active", self._on_crash_switch, "AUDIO_RESTART_ON_CRASH_NOTIFY", "crash_notify")
        group.add(nsw)
        na = RowActions(nsw,
                        on_discard=lambda: self._discard_crash("AUDIO_RESTART_ON_CRASH_NOTIFY", "crash_notify"),
                        on_reset=lambda: self._reset_crash("AUDIO_RESTART_ON_CRASH_NOTIFY", "crash_notify"))
        nsw.add_suffix(na.box)
        na.reorder_first()
        self._crash_rows.append(("AUDIO_RESTART_ON_CRASH_NOTIFY", "crash_notify", nsw, na))

    def _on_crash_switch(self, sw: Adw.SwitchRow, _pspec, var: str, key: str) -> None:
        if self._setting_value:
            return
        self._pending[var] = "true" if sw.get_active() else "false"
        self._dirty = True
        if self._on_dirty_changed:
            self._on_dirty_changed()
        GLib.idle_add(self._refresh_managed)

    def _on_crash_spin(self, spin: Gtk.SpinButton, _pspec) -> None:
        if self._setting_value:
            return
        self._pending["AUDIO_RESTART_ON_CRASH_THRESHOLD"] = str(int(spin.get_value()))
        self._dirty = True
        if self._on_dirty_changed:
            self._on_dirty_changed()
        GLib.idle_add(self._refresh_managed)

    def _discard_crash(self, var: str, key: str) -> None:
        from lib.python.variable import get_var as _g
        live = _g(var, "")
        self._set_crash_widget(key, live)
        self._pending.pop(var, None)
        self._check_dirty()
        self._refresh_managed()

    def _reset_crash(self, var: str, key: str) -> None:
        default = _CRASH_DEFAULTS.get(var, "")
        self._set_crash_widget(key, default)
        self._pending[var] = default
        self._dirty = True
        if self._on_dirty_changed:
            self._on_dirty_changed()
        self._refresh_managed()

    def _set_crash_widget(self, key: str, val: str) -> None:
        self._setting_value = True
        if key == "crash_threshold":
            try:
                self._crash_spin.set_value(float(val))
            except (ValueError, AttributeError):
                self._crash_spin.set_value(20)
        else:
            for var, pk, widget, _actions in self._crash_rows:
                if pk == key:
                    widget.set_active(val == "true")
                    break
        self._setting_value = False

    def _get_crash_cur(self, key: str) -> str:
        if key == "crash_threshold":
            try:
                return str(int(self._crash_spin.get_value()))
            except (ValueError, AttributeError):
                return "20"
        for var, pk, widget, _actions in self._crash_rows:
            if pk == key:
                return "true" if widget.get_active() else "false"
        return ""

    def _build_advanced_section(self, group: Adw.PreferencesGroup) -> None:
        fix_btn = Gtk.Button(label="Fix Audio Stutter")
        fix_btn.add_css_class("destructive-action")
        fix_btn.set_valign(Gtk.Align.CENTER)
        fix_btn.connect("clicked", lambda _b: self._fix_stutter())

        row = Adw.ActionRow(
            title="Fix audio crackling",
            subtitle="Restarts audio services with P-core CPU affinity for Intel hybrid CPUs",
        )
        row.add_suffix(fix_btn)
        group.add(row)

    def _fix_stutter(self) -> None:
        self._launch_kitty(
            f"bash {_AUDIO_CORE} --fix-stutter && "
            f"echo; echo 'Audio services have been restarted with P-core affinity.'; "
            f"echo Press Enter to close.; read"
        )
        self._window.show_toast("Fixing audio stutter in terminal\u2026", timeout=3)

    @staticmethod
    def _launch_kitty(command: str) -> None:
        cmd = f"kitty -- bash -c '{command}'"
        lua = f'hl.dsp.exec_cmd("{cmd}", {{ float = true, size = {{ 800, 500 }}, center = true }})'
        subprocess.Popen(
            ["hyprctl", "dispatch", lua],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    # ── Periodic tick ──

    def _tick(self) -> bool:
        threading.Thread(target=self._tick_worker, daemon=True).start()
        return True

    def _tick_worker(self) -> None:
        try:
            r = subprocess.run(
                ["bash", _AUDIO_CORE, "--status"],
                capture_output=True, text=True, timeout=5,
                stdin=subprocess.DEVNULL,
            )
            GLib.idle_add(self._apply_status, r.stdout)
        except Exception:
            pass

    def _apply_status(self, output: str) -> None:
        status: dict[str, str] = {}
        for line in output.strip().splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                status[k] = v
        self._status.update(status)

        self._setting_value = True

        if "sink_volume" in status and hasattr(self, "_volume_spin"):
            self._volume_spin.set_value(float(status["sink_volume"]))
        if "source_volume" in status and hasattr(self, "_mic_volume_spin"):
            self._mic_volume_spin.set_value(float(status["source_volume"]))

        if "sink_mute" in status and hasattr(self, "_mute_switch"):
            self._mute_switch.set_active(status["sink_mute"] == "true")
        if "source_mute" in status and hasattr(self, "_mic_mute_switch"):
            self._mic_mute_switch.set_active(status["source_mute"] == "true")

        cur_sink = status.get("sink", "")
        cur_source = status.get("source", "")
        if cur_sink and hasattr(self, "_output_combo"):
            for i, s in enumerate(self._sinks):
                if s["id"] == cur_sink:
                    self._output_combo.set_selected(i)
                    break
        if cur_source and hasattr(self, "_input_combo"):
            for i, s in enumerate(self._sources):
                if s["id"] == cur_source:
                    self._input_combo.set_selected(i)
                    break

        self._setting_value = False

        ee = status.get("easyeffects", "")
        if ee and hasattr(self, "_ee_status_lbl"):
            self._ee_status_lbl.set_label(ee)
            running = ee == "Running"
            if hasattr(self, "_ee_start_btn"):
                self._ee_start_btn.set_sensitive(not running)
            if hasattr(self, "_ee_stop_btn"):
                self._ee_stop_btn.set_sensitive(running)

    # ── Save lifecycle ──

    def is_dirty(self) -> bool:
        return self._dirty

    def mark_saved(self) -> None:
        if not self._dirty and not self._pending:
            return
        from lib.python.variable import set_var as _set_var

        ps = self._pending.get("AUDIO_PRIMARY_SINK", self._orig.get("primary_sink", ""))
        fs = self._pending.get("AUDIO_FALLBACK_SINK", self._orig.get("fallback_sink", ""))
        pp = self._pending.get("AUDIO_PRIMARY_SOURCE", self._orig.get("primary_source", ""))
        fp = self._pending.get("AUDIO_FALLBACK_SOURCE", self._orig.get("fallback_source", ""))

        sink_dirty = "AUDIO_PRIMARY_SINK" in self._pending or "AUDIO_FALLBACK_SINK" in self._pending
        src_dirty = "AUDIO_PRIMARY_SOURCE" in self._pending or "AUDIO_FALLBACK_SOURCE" in self._pending

        if sink_dirty:
            subprocess.run(
                ["bash", _AUDIO_CORE, "--audio-priority-set", "sink", ps, fs],
                capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL,
            )
        if src_dirty:
            subprocess.run(
                ["bash", _AUDIO_CORE, "--audio-priority-set", "source", pp, fp],
                capture_output=True, text=True, timeout=10, stdin=subprocess.DEVNULL,
            )

        for var, val in self._pending.items():
            if var not in ("AUDIO_PRIMARY_SINK", "AUDIO_FALLBACK_SINK",
                           "AUDIO_PRIMARY_SOURCE", "AUDIO_FALLBACK_SOURCE"):
                _set_var(var, val)

        self._pending.clear()
        self._orig = {
            "primary_sink": ps,
            "fallback_sink": fs,
            "primary_source": pp,
            "fallback_source": fp,
            "eq_preset": self._status.get("eq_preset", ""),
            "crash_restart": self._get_crash_cur("crash_restart"),
            "crash_threshold": self._get_crash_cur("crash_threshold"),
            "crash_notify": self._get_crash_cur("crash_notify"),
        }
        self._dirty = False
        self._refresh_managed()

    def discard(self) -> None:
        for var, key, _row, _actions, _dl, _fb in self._priority_rows:
            self._set_priority_widget(key, self._orig.get(key, ""))
        for var, key, _widget, _actions in self._crash_rows:
            self._set_crash_widget(key, self._orig.get(key, ""))
        self._pending.clear()
        self._dirty = False

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if self._dirty:
            yield PendingChange(
                category="Audio",
                title="Audio Configuration",
                subtitle="Device priority or EQ changed",
                navigate_to="audio",
                icon=_AUDIO_ICON,
                kind="modified",
                revert=self.discard,
            )

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "audio:volume", "label": "Volume & Devices",
             "description": "Volume level, mute, microphone mute, output and input selectors",
             "_group_id": "audio", "_group_label": "Audio", "_section_label": "Volume & Devices"},
            {"key": "audio:priority", "label": "Device Priority",
             "description": "Primary and fallback output/input devices",
             "_group_id": "audio", "_group_label": "Audio", "_section_label": "Device Priority"},
            {"key": "audio:eq", "label": "EQ Profiles",
             "description": "Apply, delete, and download equalizer presets",
             "_group_id": "audio", "_group_label": "Audio", "_section_label": "Equalizer Profiles"},
            {"key": "audio:ee", "label": "EasyEffects",
             "description": "Start, stop, restart, and open EasyEffects GUI",
             "_group_id": "audio", "_group_label": "Audio", "_section_label": "EasyEffects"},
            {"key": "audio:crash_restart", "label": "Audio Auto-restart on crash",
             "description": "Restart EasyEffects automatically when it crashes",
             "_group_id": "audio", "_group_label": "Audio", "_section_label": "Crash Recovery"},
            {"key": "audio:crash_threshold", "label": "Audio Restart delay",
             "description": "Seconds to wait before restarting crashed EasyEffects",
             "_group_id": "audio", "_group_label": "Audio", "_section_label": "Crash Recovery"},
            {"key": "audio:crash_notify", "label": "Audio Crash notification",
             "description": "Show desktop notification when EasyEffects is restarted",
             "_group_id": "audio", "_group_label": "Audio", "_section_label": "Crash Recovery"},
            {"key": "audio:spectrum", "label": "Audio Spectrum",
             "description": "Enable real-time frequency spectrum visualizer",
             "_group_id": "audio", "_group_label": "Audio", "_section_label": "Audio Spectrum"},
        ]

    def destroy(self) -> None:
        if self._tick_source:
            GLib.source_remove(self._tick_source)
            self._tick_source = None
        self._stop_spectrum_engine("out")
        self._stop_spectrum_engine("in")
        if self._spectrum_widget:
            self._spectrum_widget.stop()
            self._spectrum_widget = None
        if self._spectrum_in_widget:
            self._spectrum_in_widget.stop()
            self._spectrum_in_widget = None
