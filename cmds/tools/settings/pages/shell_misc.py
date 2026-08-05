"""Shell Misc page — OCR, Weather, and Performance settings.

Configs:
- OCR  → ``system.json``  (only the ``ocr`` sub-object is managed)
- Weather     → ``weather.json``
- Performance → ``performance.json``

All three files are watched by the shell's ``FileView`` with ``watchChanges``,
so changes apply live without a shell restart.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk, Gio, GLib

from settings.core.pending import PendingChange
from settings.core.shell_config import (
    PERFORMANCE_DEFAULTS, SYSTEM_OCR_DEFAULTS, TOOLS_DEFAULTS, WEATHER_DEFAULTS,
    load_performance, load_system, load_tools, load_weather,
    save_performance, save_system, save_tools, save_weather,
)
from settings.ui import make_page_layout
from settings.ui.icons import MISC_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_OCR_KEYS = [
    ("eng", "English"),
    ("fra", "French"),
    ("deu", "German"),
    ("lat", "Latin"),
    ("pol", "Polish"),
    ("ron", "Romanian"),
    ("spa", "Spanish"),
    ("swe", "Swedish"),
    ("chi_sim", "Chinese (Simplified)"),
    ("chi_tra", "Chinese (Traditional)"),
    ("jpn", "Japanese"),
    ("kor", "Korean"),
]

_UNIT_OPTIONS = [
    ("C", "Celsius"),
    ("F", "Fahrenheit"),
]

_PERF_TOGGLES = [
    ("blurTransition", "Blur Transition", "Animated blur when opening panels"),
    ("windowPreview", "Window Preview", "Show window thumbnails in overview"),
    ("wavyLine", "Wavy Line", "Animated wavy line effect"),
    ("rotateCoverArt", "Rotate Cover Art", "Spin the vinyl disc when playing music"),
]


class ShellMiscPage:
    """Shell miscellaneous settings."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._on_dirty_changed = None

        # OCR — nested in system.json
        self._data = load_system()
        self._ocr = dict(self._data.get("ocr", SYSTEM_OCR_DEFAULTS))
        self._saved = dict(self._data)
        self._saved_ocr = dict(self._ocr)

        # Weather
        self._weather = load_weather()
        self._saved_weather = dict(self._weather)

        # Performance
        self._perf = load_performance()
        self._saved_perf = dict(self._perf)

        # Tools
        self._tools = load_tools()
        self._saved_tools = dict(self._tools)

        self._ocr_rows: dict[str, ManagedRow] = {}
        self._weather_rows: dict[str, ManagedRow] = {}
        self._perf_rows: dict[str, ManagedRow] = {}
        self._spin_rows: dict[str, Gtk.SpinButton] = {}

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)

        # ── OCR ──
        ocr_group = Adw.PreferencesGroup(
            title="OCR Languages",
            description="Language packs used by the OCR tool.",
        )
        for key, label in _OCR_KEYS:
            self._add_ocr_switch(ocr_group, key, label)
        content_box.append(ocr_group)

        # ── Weather ──
        weather_group = Adw.PreferencesGroup(
            title="Weather",
            description="Location and unit for the weather widget.",
        )
        self._add_weather_entry(weather_group, "location", "Location",
                                placeholder="e.g. Buenos Aires, Tokyo...",
                                subtitle="City name or coordinates for weather data")
        self._add_weather_combo(weather_group, "unit", "Unit", _UNIT_OPTIONS,
                                subtitle="Temperature display unit")
        content_box.append(weather_group)

        # ── Performance ──
        perf_group = Adw.PreferencesGroup(
            title="Performance",
            description="Toggle visual effects to improve performance.",
        )
        for key, label, sub in _PERF_TOGGLES:
            self._add_perf_switch(perf_group, key, label, subtitle=sub)
        content_box.append(perf_group)

        # ── Screenshot & Recording ──
        tools_group = Adw.PreferencesGroup(
            title="Screenshot and Recording",
            description="Capture settings: schedule, save location, and quality.",
        )

        # -- Screenshot Countdown --
        val = int(self._tools.get("screenshotCountdown", TOOLS_DEFAULTS["screenshotCountdown"]))
        adj = Gtk.Adjustment(value=val, lower=1, upper=30,
                             step_increment=1, page_increment=5)
        row = Adw.ActionRow(title="Screenshot Countdown",
                            subtitle="Seconds before timed capture (1–30)")
        s_spin = Gtk.SpinButton(adjustment=adj, digits=0)
        s_spin.set_valign(Gtk.Align.CENTER)
        s_spin.connect("value-changed", self._on_tools_spin_changed, "screenshotCountdown")
        s_label = Gtk.Label(label="s")
        s_label.set_valign(Gtk.Align.CENTER)
        s_label.set_opacity(0.7)
        s_label.set_margin_start(4)
        row.add_suffix(s_label)
        row.add_suffix(s_spin)
        tools_group.add(row)
        self._spin_rows["screenshotCountdown"] = s_spin

        # -- Timer enabled by default --
        timer_enabled_row = Adw.SwitchRow(
            title="Timer enabled by default",
            subtitle="Whether the timer toggle is on when opening the screenshot tool",
        )
        timer_enabled_row.set_active(bool(self._tools.get("screenshotTimerEnabled", TOOLS_DEFAULTS["screenshotTimerEnabled"])))
        tools_group.add(timer_enabled_row)
        self._timer_enabled_row = timer_enabled_row

        def _timer_enabled_changed(*_args):
            self._tools["screenshotTimerEnabled"] = timer_enabled_row.get_active()
            self._notify_dirty()
        timer_enabled_row.connect("notify::active", _timer_enabled_changed)

        # -- Screenshots folder --
        ss_dir_row = self._build_dir_row("Screenshots folder",
                                         "Where screenshots are saved (default: ~/Pictures/Screenshots)",
                                         "~/Pictures/Screenshots",
                                         "screenshotsDir")
        tools_group.add(ss_dir_row)

        # -- Recordings folder --
        rec_dir_row = self._build_dir_row("Recordings folder",
                                          "Where recordings are saved (default: ~/Videos/Recordings)",
                                          "~/Videos/Recordings",
                                          "recordingsDir")
        tools_group.add(rec_dir_row)

        # -- Recording FPS --
        fps_val = int(self._tools.get("recordingFps", TOOLS_DEFAULTS["recordingFps"]))
        fps_adj = Gtk.Adjustment(value=fps_val, lower=1, upper=240,
                                 step_increment=1, page_increment=30)
        fps_row = Adw.ActionRow(title="Recording FPS",
                                subtitle="Frames per second for recording (1–240)")
        fps_spin = Gtk.SpinButton(adjustment=fps_adj, digits=0)
        fps_spin.set_valign(Gtk.Align.CENTER)
        fps_spin.connect("value-changed", self._on_tools_spin_changed, "recordingFps")
        fps_label = Gtk.Label(label="fps")
        fps_label.set_valign(Gtk.Align.CENTER)
        fps_label.set_opacity(0.7)
        fps_label.set_margin_start(4)
        fps_row.add_suffix(fps_label)
        fps_row.add_suffix(fps_spin)
        tools_group.add(fps_row)
        self._spin_rows["recordingFps"] = fps_spin

        # -- Recording Resolution --
        res_options = self._get_resolution_options()
        res_ids = [o[0] for o in res_options]
        res_labels = [o[1] for o in res_options]
        current_res = self._tools.get("recordingResolution", TOOLS_DEFAULTS["recordingResolution"])
        try:
            res_selected = res_ids.index(current_res)
        except ValueError:
            res_selected = 0
        res_row = make_combo_row("Recording Resolution",
                                 model=Gtk.StringList.new(res_labels),
                                 selected=res_selected,
                                 subtitle="Output resolution for screen and portal capture modes")
        tools_group.add(res_row)
        self._res_row = res_row
        self._res_ids = res_ids

        def _res_changed(*_args):
            idx = res_row.get_selected()
            self._tools["recordingResolution"] = res_ids[idx] if 0 <= idx < len(res_ids) else res_ids[0]
            self._notify_dirty()
        res_row.connect("notify::selected", _res_changed)

        # -- Portal Recording --
        portal_row = Adw.SwitchRow(
            title="Portal Recording (Experimental)",
            subtitle="Unstable portal capture. Some apps may not render correctly. Off by default.",
        )
        portal_row.set_active(bool(self._tools.get("recordingPortalEnabled", TOOLS_DEFAULTS["recordingPortalEnabled"])))
        tools_group.add(portal_row)
        self._portal_row = portal_row

        def _portal_changed(*_args):
            if portal_row.get_active():
                from settings.ui import confirm
                def _enable():
                    self._tools["recordingPortalEnabled"] = True
                    self._notify_dirty()
                def _cancel():
                    portal_row.set_active(False)
                confirm(
                    self._window,
                    heading="Portal mode is experimental",
                    body="Portal capture may be unstable with some applications and compositor configurations. Enable anyway?",
                    label="Enable",
                    on_confirm=_enable,
                    appearance=Adw.ResponseAppearance.SUGGESTED,
                )
                # After showing dialog, always mark for potential dirty
                # Only actually set dirty if user confirms (in _enable)
                self._notify_dirty()
            else:
                self._tools["recordingPortalEnabled"] = False
                self._notify_dirty()
        portal_row.connect("notify::active", _portal_changed)

        # -- Preview countdown --
        preview_row = Adw.SwitchRow(
            title="Preview Countdown",
            subtitle="Show a camera icon before the countdown starts",
        )
        preview_row.set_active(bool(self._tools.get("previewCountdown", TOOLS_DEFAULTS["previewCountdown"])))
        tools_group.add(preview_row)
        self._preview_row = preview_row

        def _preview_changed(*_args):
            self._tools["previewCountdown"] = preview_row.get_active()
            self._notify_dirty()
        preview_row.connect("notify::active", _preview_changed)

        content_box.append(tools_group)

        return toolbar

    # ══ OCR builders ══

    def _add_ocr_switch(self, group: Adw.PreferencesGroup, key: str, label: str) -> ManagedRow:
        row = Adw.SwitchRow(title=label)
        row.set_active(bool(self._ocr.get(key, SYSTEM_OCR_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=SYSTEM_OCR_DEFAULTS[key],
            baseline=self._saved_ocr.get(key, SYSTEM_OCR_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
        )
        self._ocr_rows[key] = mrow

        def _changed(*_args):
            self._ocr[key] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        row.connect("notify::active", _changed)
        return mrow

    # ══ Weather builders ══

    def _add_weather_entry(self, group: Adw.PreferencesGroup, key: str, label: str,
                           *, placeholder: str = "", subtitle: str = "") -> ManagedRow:
        row = Adw.ActionRow(title=label, subtitle=subtitle)
        entry = Gtk.Entry(text=str(self._weather.get(key, WEATHER_DEFAULTS[key])))
        if placeholder:
            entry.set_placeholder_text(placeholder)
        row.set_child(entry)
        row.set_activatable_widget(entry)
        group.add(row)

        def get_value():
            return entry.get_text()

        def set_silent(value):
            entry.set_text(str(value))

        mrow = ManagedRow(
            row,
            default=WEATHER_DEFAULTS[key],
            baseline=self._saved_weather.get(key, WEATHER_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
        )
        self._weather_rows[key] = mrow

        def _changed(*_args):
            self._weather[key] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        entry.connect("changed", _changed)
        return mrow

    def _add_weather_combo(
        self, group: Adw.PreferencesGroup, key: str, label: str,
        options: list[tuple[str, str]], *, subtitle: str = "",
    ) -> ManagedRow:
        ids = [o[0] for o in options]
        labels = [o[1] for o in options]
        current = self._weather.get(key, WEATHER_DEFAULTS[key])
        try:
            selected = ids.index(current)
        except ValueError:
            selected = 0
        row = make_combo_row(label, model=Gtk.StringList.new(labels), selected=selected,
                             subtitle=subtitle)
        group.add(row)

        def get_value():
            idx = row.get_selected()
            return ids[idx] if 0 <= idx < len(ids) else ids[0]

        def set_silent(value):
            try:
                row.set_selected(ids.index(value))
            except ValueError:
                row.set_selected(0)

        mrow = ManagedRow(
            row,
            default=WEATHER_DEFAULTS[key],
            baseline=self._saved_weather.get(key, WEATHER_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
        )
        self._weather_rows[key] = mrow

        def _changed(*_args):
            self._weather[key] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        row.connect("notify::selected", _changed)
        return mrow

    # ══ Performance builders ══

    def _add_perf_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                         subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._perf.get(key, PERFORMANCE_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=PERFORMANCE_DEFAULTS[key],
            baseline=self._saved_perf.get(key, PERFORMANCE_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
        )
        self._perf_rows[key] = mrow

        def _changed(*_args):
            self._perf[key] = mrow.value
            mrow.refresh()
            self._notify_dirty()

        row.connect("notify::active", _changed)
        return mrow

    # ══ Tools helpers ══

    def _build_dir_row(self, title: str, subtitle: str, placeholder: str,
                       config_key: str) -> Adw.ActionRow:
        row = Adw.ActionRow(title=title, subtitle=subtitle)
        entry = Gtk.Entry(text=str(self._tools.get(config_key, TOOLS_DEFAULTS[config_key])))
        entry.set_placeholder_text(placeholder)
        entry.set_valign(Gtk.Align.CENTER)
        entry.set_hexpand(True)

        btn = Gtk.Button.new_from_icon_name("folder-open")
        btn.set_valign(Gtk.Align.CENTER)
        btn.set_tooltip_text("Choose folder")
        btn.add_css_class("flat")
        btn.connect("clicked", self._on_folder_pick, entry, config_key)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.append(entry)
        box.append(btn)
        row.set_child(box)

        def _dir_changed(*_args):
            self._tools[config_key] = entry.get_text()
            self._notify_dirty()
        entry.connect("changed", _dir_changed)

        if not hasattr(self, "_dir_entries"):
            self._dir_entries = {}
        self._dir_entries[config_key] = entry

        return row

    def _on_folder_pick(self, _btn: Gtk.Button, entry: Gtk.Entry,
                        config_key: str) -> None:
        dialog = Gtk.FileDialog()
        dialog.set_title("Choose Folder")
        dialog.select_folder(self._window, None,
                             self._on_folder_selected, entry, config_key)

    def _on_folder_selected(self, dialog: Gtk.FileDialog, result,
                            entry: Gtk.Entry, config_key: str) -> None:
        try:
            gfile = dialog.select_folder_finish(result)
        except GLib.Error:
            return
        path = gfile.get_path() if gfile else None
        if path:
            entry.set_text(path)
            self._tools[config_key] = path
            self._notify_dirty()

    def _get_resolution_options(self) -> list[tuple[str, str]]:
        monitors = []
        try:
            monitors = self._window.hypr.monitors.get_all()
        except Exception:
            monitors = []
        mon = next((m for m in monitors if m.focused), monitors[0] if monitors else None)
        if not mon:
            return [("auto", "Auto (native)")]
        w, h = mon.width, mon.height
        opts = [(f"{w}x{h}", f"{w}×{h}")]
        seen = {(w, h)}
        for frac in (0.75, 0.5, 0.375):
            nw = int(round(w * frac / 2) * 2)
            nh = int(round(h * frac / 2) * 2)
            if nw < 320 or nh < 240 or (nw, nh) in seen:
                continue
            seen.add((nw, nh))
            opts.append((f"{nw}x{nh}", f"{nw}×{nh}"))
        return opts

    # ══ Tools callbacks ══

    def _on_tools_spin_changed(self, spin: Gtk.SpinButton, key: str) -> None:
        self._tools[key] = int(spin.get_value())
        self._notify_dirty()

    # ══ Lifecycle ══

    def _notify_dirty(self) -> None:
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return (self._ocr != self._saved_ocr
                or self._weather != self._saved_weather
                or self._perf != self._saved_perf
                or self._tools != self._saved_tools)

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        if self._ocr != self._saved_ocr:
            self._data["ocr"] = dict(self._ocr)
            save_system(self._data)
            self._saved = dict(self._data)
            self._saved_ocr = dict(self._ocr)
        if self._weather != self._saved_weather:
            save_weather(self._weather)
            self._saved_weather = dict(self._weather)
        if self._perf != self._saved_perf:
            save_performance(self._perf)
            self._saved_perf = dict(self._perf)
        if self._tools != self._saved_tools:
            save_tools(self._tools)
            self._saved_tools = dict(self._tools)
        for key, mrow in self._ocr_rows.items():
            mrow.set_baseline(self._ocr.get(key, SYSTEM_OCR_DEFAULTS[key]))
        for key, mrow in self._weather_rows.items():
            mrow.set_baseline(self._weather.get(key, WEATHER_DEFAULTS[key]))
        for key, mrow in self._perf_rows.items():
            mrow.set_baseline(self._perf.get(key, PERFORMANCE_DEFAULTS[key]))

    def discard(self) -> None:
        self._ocr = dict(self._saved_ocr)
        self._weather = dict(self._saved_weather)
        self._perf = dict(self._saved_perf)
        self._tools = dict(self._saved_tools)
        for mrow in self._ocr_rows.values():
            mrow.discard()
        for mrow in self._weather_rows.values():
            mrow.discard()
        for mrow in self._perf_rows.values():
            mrow.discard()
        for key, spin in self._spin_rows.items():
            spin.set_value(self._tools.get(key, TOOLS_DEFAULTS[key]))
        self._preview_row.set_active(self._tools.get("previewCountdown", TOOLS_DEFAULTS["previewCountdown"]))
        self._timer_enabled_row.set_active(self._tools.get("screenshotTimerEnabled", TOOLS_DEFAULTS["screenshotTimerEnabled"]))
        self._portal_row.set_active(self._tools.get("recordingPortalEnabled", TOOLS_DEFAULTS["recordingPortalEnabled"]))
        if hasattr(self, "_dir_entries"):
            for key, entry in self._dir_entries.items():
                entry.set_text(self._tools.get(key, TOOLS_DEFAULTS[key]))
        res = self._tools.get("recordingResolution", TOOLS_DEFAULTS["recordingResolution"])
        try:
            self._res_row.set_selected(self._res_ids.index(res))
        except ValueError:
            self._res_row.set_selected(0)

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed: list[str] = []
        for key, label in _OCR_KEYS:
            if self._ocr.get(key) != self._saved_ocr.get(key):
                changed.append(label)
        if self._weather != self._saved_weather:
            changed.append("Weather")
        if self._perf != self._saved_perf:
            changed.append("Performance")
        if self._tools != self._saved_tools:
            changed.append("Screenshot & Recording")
        if changed:
            yield PendingChange(
                category="Shell Misc",
                title="Miscellaneous",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_misc",
                icon=MISC_ICON,
                kind="modified",
                revert=self.discard,
            )

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_misc:ocr", "label": "OCR Languages",
             "description": "Optical character recognition language toggles",
             "_group_id": "shell_misc", "_group_label": "Miscellaneous", "_section_label": "OCR"},
            {"key": "shell_misc:weather", "label": "Weather",
             "description": "Weather widget location and temperature unit",
             "_group_id": "shell_misc", "_group_label": "Miscellaneous", "_section_label": "Weather"},
            {"key": "shell_misc:performance", "label": "Performance",
             "description": "Visual effects toggles for better performance",
             "_group_id": "shell_misc", "_group_label": "Miscellaneous", "_section_label": "Performance"},
            {"key": "shell_misc:tools", "label": "Screenshot & Recording",
             "description": "Capture settings, save locations, and timed countdown",
             "_group_id": "shell_misc", "_group_label": "Miscellaneous", "_section_label": "Screenshot & Recording"},
        ]


__all__ = ["ShellMiscPage"]
