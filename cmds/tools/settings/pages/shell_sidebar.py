"""Shell Sidebar page — configure the RetroShell assistant sidebar and AI (``ai.json`` + ``keys.db``).

Mirrors the Sidebar section of ``ShellPanel.qml`` and the full AI / API key
provider panel from ``AiPanel.qml``. AI provider API keys are stored via the
``KeyStore`` SQLite database (``keys.db``), not in the JSON config — this page
manages both files in one place.

Values are written to ``~/.config/retro/shell/ai.json`` and
``~/.local/share/retroshell/keys.db``; the shell's ``FileView`` watches
``ai.json`` with ``watchChanges`` and ``KeyStore.keysChanged`` broadcasts
key updates, so changes apply live without a shell restart.
"""

from collections.abc import Iterable
from typing import TYPE_CHECKING

from gi.repository import Adw, Gtk, GLib

from settings.core import keystore
from settings.core.pending import PendingChange
from settings.core.shell_config import AI_DEFAULTS, load_ai, save_ai
from settings.ui import make_page_layout
from settings.ui.icons import SIDEBAR_ICON
from settings.ui.managed_row import ManagedRow, make_combo_row, make_spin_int_row

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_POSITION_OPTIONS = [
    ("left", "Left"),
    ("right", "Right"),
]

# Matches ``AiPanel.qml`` Repeater model.
_PROVIDERS = [
    ("none", "None"),
    ("gemini", "Gemini"),
    ("openai", "OpenAI"),
    ("anthropic", "Anthropic"),
    ("mistral", "Mistral"),
    ("groq", "Groq"),
    ("ollama", "Ollama"),
    ("minimax", "MiniMax"),
    ("custom", "Custom"),
]


def _join_models(models) -> str:
    if isinstance(models, list):
        return ", ".join(str(m) for m in models)
    return ""


def _split_models(text: str) -> list[str]:
    return [m.strip() for m in text.split(",") if m.strip()]


class ShellSidebarPage:
    """Shell assistant sidebar and full AI configuration."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box | None = None
        self._on_dirty_changed = None
        self._data = load_ai()
        self._saved = dict(self._data)
        self._rows: dict[str, ManagedRow] = {}
        # Provider UI
        self._provider_combo: Adw.ComboRow | None = None
        self._api_entry: Gtk.Entry | None = None
        self._key_status: Gtk.Label | None = None
        self._save_btn: Gtk.Button | None = None
        self._clear_btn: Gtk.Button | None = None
        self._api_row: Adw.ActionRow | None = None
        # Model UI — either combo or entry, toggled by provider
        self._model_combo: Gtk.DropDown | None = None
        self._model_entry: Gtk.Entry | None = None
        self._model_row: Adw.ActionRow | None = None
        self._fetch_btn: Gtk.Button | None = None
        self._model_ids: list[str] = []

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _page_box, content_box, _scrolled = make_page_layout(header=header)
        self._content_box = content_box

        sidebar_group = Adw.PreferencesGroup(
            title="Sidebar",
            description="Position, size, and startup behaviour of the assistant sidebar.",
        )
        self._build_sidebar_group(sidebar_group)
        content_box.append(sidebar_group)

        ai_group = Adw.PreferencesGroup(
            title="AI",
            description="Provider, model, system prompt, and API key configuration.",
        )
        self._build_ai_group(ai_group)
        content_box.append(ai_group)

        provider = self._data.get("tool", AI_DEFAULTS["tool"])
        if provider == "ollama" and keystore.has_key("ollama"):
            GLib.idle_add(self._on_fetch_models)

        return toolbar

    # ══  Sidebar  ══

    def _build_sidebar_group(self, group: Adw.PreferencesGroup) -> None:
        self._add_combo(group, "sidebarPosition", "Position", _POSITION_OPTIONS,
                        subtitle="Which screen edge the sidebar is attached to")
        self._add_spin(group, "sidebarWidth", "Width",
                       lower=300, upper=800, suffix="px",
                       subtitle="Width of the sidebar in pixels")
        self._add_switch(group, "sidebarPinnedOnStartup", "Pinned on Startup",
                         subtitle="Keep the sidebar open when the session starts")

    # ══  AI group (single group: provider → key → model → system prompt → extras) ══

    def _build_ai_group(self, group: Adw.PreferencesGroup) -> None:
        # Provider
        self._add_combo(group, "tool", "Provider", _PROVIDERS,
                        subtitle="AI backend provider to use for conversations")

        # API key
        api_row = Adw.ActionRow(title="API Key", subtitle="Provider API key or token")
        api_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        api_entry = Gtk.Entry()
        api_entry.set_placeholder_text("Enter API key…")
        api_entry.set_visibility(False)
        api_entry.set_hexpand(True)
        api_entry.set_valign(Gtk.Align.CENTER)
        self._api_entry = api_entry

        save_btn = Gtk.Button(label="Save")
        save_btn.add_css_class("pill")
        save_btn.set_valign(Gtk.Align.CENTER)
        save_btn.connect("clicked", self._on_save_api_key)
        self._save_btn = save_btn

        clear_btn = Gtk.Button(label="Clear")
        clear_btn.add_css_class("pill")
        clear_btn.add_css_class("destructive-action")
        clear_btn.set_valign(Gtk.Align.CENTER)
        clear_btn.connect("clicked", self._on_clear_api_key)
        self._clear_btn = clear_btn

        status = Gtk.Label()
        status.add_css_class("dim-label")
        status.set_valign(Gtk.Align.CENTER)
        self._key_status = status

        api_box.append(api_entry)
        api_box.append(save_btn)
        api_box.append(clear_btn)
        api_box.append(status)
        api_row.add_suffix(api_box)
        self._api_row = api_row
        group.add(api_row)

        # Default model — dynamic: combo for Ollama, entry for others
        self._build_model_row(group)

        # System prompt
        self._add_entry(group, "systemPrompt", "System Prompt",
                        placeholder="You are a helpful assistant...",
                        subtitle="Instructions to the AI model on how to behave")

        # Extra models
        self._add_entry(group, "extraModels", "Extra Models",
                        placeholder="model-a, model-b",
                        subtitle="Comma-separated additional model names")

        self._refresh_model_row()
        self._refresh_provider_ui()

    def _build_model_row(self, group: Adw.PreferencesGroup) -> None:
        """Build a row with dropdown (for Ollama) or entry (other providers)."""
        row = Adw.ActionRow(title="Default Model",
                            subtitle="Model to use for new conversations")
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        current = str(self._data.get("defaultModel", AI_DEFAULTS["defaultModel"]))
        self._model_ids = [current] if current else [""]

        # DropDown for Ollama
        model_list = Gtk.StringList.new(self._model_ids)
        dropdown = Gtk.DropDown(model=model_list)
        dropdown.set_selected(0)
        dropdown.set_valign(Gtk.Align.CENTER)
        self._model_combo = dropdown

        # Entry for other providers
        entry = Gtk.Entry()
        entry.set_text(current)
        entry.set_hexpand(True)
        entry.set_valign(Gtk.Align.CENTER)
        self._model_entry = entry

        # Fetch button
        fetch_btn = Gtk.Button(label="Fetch")
        fetch_btn.add_css_class("pill")
        fetch_btn.set_valign(Gtk.Align.CENTER)
        fetch_btn.connect("clicked", self._on_fetch_models)
        self._fetch_btn = fetch_btn

        box.append(dropdown)
        box.append(entry)
        box.append(fetch_btn)
        row.add_suffix(box)
        self._model_row = row
        group.add(row)

        def _combo_changed(*_a):
            idx = dropdown.get_selected()
            if 0 <= idx < len(self._model_ids):
                self._on_change("defaultModel", self._model_ids[idx])

        dropdown.connect("notify::selected", _combo_changed)

        def _entry_changed(*_a):
            self._on_change("defaultModel", entry.get_text())

        entry.connect("changed", _entry_changed)

    def _refresh_model_row(self) -> None:
        provider = self._data.get("tool", AI_DEFAULTS["tool"])
        is_ollama = provider == "ollama"
        if self._model_combo:
            self._model_combo.set_visible(is_ollama)
        if self._model_entry:
            self._model_entry.set_visible(not is_ollama)
        if self._fetch_btn:
            self._fetch_btn.set_visible(is_ollama)

    def _refresh_provider_ui(self) -> None:
        provider = self._data.get("tool", AI_DEFAULTS["tool"])
        is_ollama = provider == "ollama"
        is_none = provider == "none"
        has_key = keystore.has_key(provider)
        key_val = keystore.get_key(provider) if has_key else ""

        visible = not is_none

        if self._api_entry:
            self._api_entry.set_visible(visible and not is_ollama)
            if not has_key:
                self._api_entry.set_text("")
        if self._save_btn:
            if is_ollama:
                self._save_btn.set_label("Enable" if not has_key else "Enabled")
                self._save_btn.set_sensitive(not has_key)
            else:
                self._save_btn.set_label("Save")
                self._save_btn.set_sensitive(True)
            self._save_btn.set_visible(visible)
        if self._clear_btn:
            self._clear_btn.set_visible(visible and has_key)
            if is_ollama:
                self._clear_btn.set_label("Disable")
        if self._key_status:
            if not visible:
                self._key_status.set_text("")
            elif has_key:
                self._key_status.set_text("Configured")
            else:
                self._key_status.set_text("Not configured")
        if self._api_row:
            self._api_row.set_visible(visible)

        self._refresh_model_row()

    def _on_save_api_key(self, *_args) -> None:
        provider = self._data.get("tool", AI_DEFAULTS["tool"])
        if not provider or provider == "none":
            return
        if provider == "ollama":
            keystore.set_key("ollama", "enabled")
        elif self._api_entry and self._api_entry.get_text().strip():
            keystore.set_key(provider, self._api_entry.get_text().strip())
            self._api_entry.set_text("")
        self._refresh_provider_ui()

    def _on_clear_api_key(self, *_args) -> None:
        provider = self._data.get("tool", AI_DEFAULTS["tool"])
        if not provider or provider == "none":
            return
        keystore.delete_key(provider)
        self._refresh_provider_ui()

    def _on_fetch_models(self, *_args) -> None:
        provider = self._data.get("tool", AI_DEFAULTS["tool"])
        models: list[str] = []
        if provider == "ollama":
            try:
                models = keystore.ollama_models()
            except Exception:
                models = []

        if not models:
            current = str(self._data.get("defaultModel", AI_DEFAULTS["defaultModel"]))
            models = [current] if current else ["llama3"]

        self._model_ids = models
        if self._model_combo:
            self._model_combo.set_model(Gtk.StringList.new(models))
            try:
                current = str(self._data.get("defaultModel", AI_DEFAULTS["defaultModel"]))
                idx = models.index(current)
                self._model_combo.set_selected(idx)
            except ValueError:
                self._model_combo.set_selected(0)
                if models:
                    self._data["defaultModel"] = models[0]
            self._notify_dirty()

    # ══  Row builders  ══

    def _add_switch(self, group: Adw.PreferencesGroup, key: str, label: str,
                    subtitle: str = "") -> ManagedRow:
        row = Adw.SwitchRow(title=label, subtitle=subtitle)
        row.set_active(bool(self._data.get(key, AI_DEFAULTS[key])))
        group.add(row)

        def get_value():
            return row.get_active()

        def set_silent(value):
            row.set_active(bool(value))

        mrow = ManagedRow(
            row,
            default=AI_DEFAULTS[key],
            baseline=self._saved.get(key, AI_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(row, "notify::active", key, mrow)
        return mrow

    def _add_combo(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        options: list[tuple[str, str]],
        *,
        subtitle: str = "",
    ) -> ManagedRow:
        ids = [opt[0] for opt in options]
        labels = [opt[1] for opt in options]
        current = self._data.get(key, AI_DEFAULTS[key])
        try:
            selected = ids.index(current)
        except ValueError:
            selected = 0
        row = make_combo_row(label, model=Gtk.StringList.new(labels), selected=selected,
                             subtitle=subtitle)
        group.add(row)

        if key == "tool":
            self._provider_combo = row

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
            default=AI_DEFAULTS[key],
            baseline=self._saved.get(key, AI_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(row, "notify::selected", key, mrow)
        return mrow

    def _add_spin(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        *,
        lower: int,
        upper: int,
        suffix: str,
        subtitle: str = "",
    ) -> ManagedRow:
        row, spin = make_spin_int_row(
            label,
            value=int(self._data.get(key, AI_DEFAULTS[key])),
            lower=lower,
            upper=upper,
            step=1,
            page_step=5,
            subtitle=subtitle,
        )
        group.add(row)
        if suffix:
            suffix_lbl = Gtk.Label(label=suffix)
            suffix_lbl.add_css_class("dim-label")
            suffix_lbl.set_valign(Gtk.Align.CENTER)
            row.add_suffix(suffix_lbl)

        def get_value():
            return int(spin.get_value())

        def set_silent(value):
            spin.set_value(int(value))

        mrow = ManagedRow(
            row,
            default=AI_DEFAULTS[key],
            baseline=self._saved.get(key, AI_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(spin, "value-changed", key, mrow)
        return mrow

    def _add_entry(
        self,
        group: Adw.PreferencesGroup,
        key: str,
        label: str,
        *,
        placeholder: str = "",
        subtitle: str = "",
    ) -> ManagedRow:
        raw = self._data.get(key, AI_DEFAULTS[key])
        if key == "extraModels":
            display = _join_models(raw)
        else:
            display = str(raw) if raw is not None else ""
        row = Adw.ActionRow(title=label, subtitle=subtitle)
        entry = Gtk.Entry(text=display)
        if placeholder:
            entry.set_placeholder_text(placeholder)
        row.set_child(entry)
        row.set_activatable_widget(entry)
        group.add(row)

        def get_value():
            text = entry.get_text()
            if key == "extraModels":
                return _split_models(text)
            return text

        def set_silent(value):
            if key == "extraModels":
                entry.set_text(_join_models(value))
            else:
                entry.set_text(str(value) if value is not None else "")

        mrow = ManagedRow(
            row,
            default=AI_DEFAULTS[key],
            baseline=self._saved.get(key, AI_DEFAULTS[key]),
            get_value=get_value,
            set_value_silent=set_silent,
            on_value_set=lambda value, k=key: self._on_change(k, value),
        )
        self._rows[key] = mrow
        self._wire_change(entry, "changed", key, mrow)
        return mrow

    # ══  Change plumbing  ══

    def _wire_change(self, widget: Gtk.Widget, signal: str, key: str, mrow: ManagedRow) -> None:
        def _changed(*_args):
            self._data[key] = mrow.value
            mrow.refresh()
            if key == "tool":
                self._refresh_provider_ui()
            self._notify_dirty()

        widget.connect(signal, _changed)

    def _on_change(self, key: str, value) -> None:
        self._data[key] = value
        if key == "tool":
            self._refresh_provider_ui()
        self._notify_dirty()

    def _write_live(self) -> None:
        save_ai(self._data)

    def _notify_dirty(self) -> None:
        self._write_live()
        if self._on_dirty_changed is not None:
            self._on_dirty_changed()

    # ══  Lifecycle  ══

    def is_dirty(self) -> bool:
        return self._data != self._saved

    def mark_saved(self) -> None:
        if not self.is_dirty():
            return
        save_ai(self._data)
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            mrow.set_baseline(self._data.get(key, AI_DEFAULTS[key]))

    def discard(self) -> None:
        self._data = dict(self._saved)
        for mrow in self._rows.values():
            mrow.discard()
        self._refresh_provider_ui()
        self._write_live()

    def reload_from_disk(self) -> None:
        """Re-read ai.json (e.g. after applying a preset) and sync widgets."""
        self._data = load_ai()
        self._saved = dict(self._data)
        for key, mrow in self._rows.items():
            value = self._data.get(key, AI_DEFAULTS[key])
            mrow.apply_value(value)
            mrow.set_baseline(value)
        self._refresh_provider_ui()

    # ══  Pending changes  ══

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        if not self.is_dirty():
            return
        changed = []
        for key in self._rows:
            if self._data.get(key) != self._saved.get(key):
                label = {
                    "sidebarPosition": "Position",
                    "sidebarWidth": "Width",
                    "sidebarPinnedOnStartup": "Pinned",
                    "tool": "Provider",
                    "systemPrompt": "System Prompt",
                    "defaultModel": "Default Model",
                    "extraModels": "Extra Models",
                }.get(key, "Sidebar setting")
                changed.append(label)
        if changed:
            yield PendingChange(
                category="Shell Sidebar",
                title="Sidebar",
                subtitle=", ".join(changed[:3]),
                navigate_to="shell_sidebar",
                icon=SIDEBAR_ICON,
                kind="modified",
                revert=self.discard,
            )

    # ══  Search  ══

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "shell_sidebar:sidebar", "label": "Sidebar",
             "description": "Position, width, startup pinning, AI provider, model, system prompt and API keys",
             "_group_id": "shell_sidebar", "_group_label": "Sidebar", "_section_label": "Sidebar"},
        ]


__all__ = ["ShellSidebarPage"]
