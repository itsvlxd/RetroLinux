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

from gi.repository import Adw, Gtk

from settings.core.pending import PendingChange
from settings.core.shell_config import (
    PERFORMANCE_DEFAULTS, SYSTEM_OCR_DEFAULTS, WEATHER_DEFAULTS,
    load_performance, load_system, load_weather,
    save_performance, save_system, save_weather,
)
from settings.ui import make_page_layout
from settings.ui.icons import MISC_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_OCR_KEYS = [
    ("eng", "English"),
    ("spa", "Spanish"),
    ("lat", "Latin"),
    ("jpn", "Japanese"),
    ("chi_sim", "Chinese (Simplified)"),
    ("chi_tra", "Chinese (Traditional)"),
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

        self._ocr_rows: dict[str, ManagedRow] = {}
        self._weather_rows: dict[str, ManagedRow] = {}
        self._perf_rows: dict[str, ManagedRow] = {}

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

    # ══ Lifecycle ══

    def _notify_dirty(self) -> None:
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    def is_dirty(self) -> bool:
        return (self._ocr != self._saved_ocr
                or self._weather != self._saved_weather
                or self._perf != self._saved_perf)

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
        for mrow in self._ocr_rows.values():
            mrow.discard()
        for mrow in self._weather_rows.values():
            mrow.discard()
        for mrow in self._perf_rows.values():
            mrow.discard()

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
        ]


__all__ = ["ShellMiscPage"]
