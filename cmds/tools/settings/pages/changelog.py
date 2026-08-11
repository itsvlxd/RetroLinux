"""Changelog page — repo commits grouped by date, sorted by type, with
date search and a from/to range filter."""

import os
import re
import subprocess
import threading
from collections.abc import Iterable
from datetime import date as _date, timedelta
from typing import TYPE_CHECKING

from gi.repository import Adw, GLib, Gtk

from settings.core.pending import PendingChange
from settings.ui import make_page_layout

if TYPE_CHECKING:
    from settings.window import RetroSettingsWindow

_RETRO_DIR = os.environ.get("RETRO_DIR", "/opt/retrolinux")

# Type -> (label, css class, glyph)
_COMMIT_TYPES: dict[str, tuple[str, str, str]] = {
    "feat": ("Features", "changelog-feat", "\U000f0b08"),
    "fix": ("Fixes", "changelog-fix", "\U000f0468"),
    "refactor": ("Refactors", "changelog-refactor", "\U000f0453"),
    "style": ("Style", "changelog-style", "\U000f03d8"),
    "docs": ("Docs", "changelog-docs", "\U000f0219"),
    "chore": ("Chore", "changelog-chore", "\U000f05d1"),
    "perf": ("Performance", "changelog-perf", "\U000f04c5"),
    "build": ("Build", "changelog-build", "\U000f03d3"),
    "ci": ("CI", "changelog-ci", "\U000f0297"),
    "test": ("Tests", "changelog-test", "\U000f0668"),
}

_TYPE_ORDER = [
    "feat", "fix", "refactor", "perf", "style", "docs", "chore", "build", "ci", "test",
]


def _type_rank(t: str) -> int:
    try:
        return _TYPE_ORDER.index(t)
    except ValueError:
        return len(_TYPE_ORDER)


def _fetch_commits() -> list[dict]:
    """Fetch all commits as parsed dicts (oldest first)."""
    try:
        r = subprocess.run(
            ["git", "-C", _RETRO_DIR, "log", "--pretty=format:%H|%s|%ad|%an", "--date=short"],
            capture_output=True, text=True, timeout=30,
            stdin=subprocess.DEVNULL,
        )
    except Exception:
        return []
    commits: list[dict] = []
    for line in r.stdout.splitlines():
        parts = line.split("|", 3)
        if len(parts) != 4:
            continue
        sha, subject, date, author = parts
        commits.append({
            "sha": sha[:7],
            "full_sha": sha,
            "subject": subject,
            "date": date,
            "author": author,
            "type": "other",
            "scope": "",
            "clean": subject,
        })
    mod_re = re.compile(r"^([a-z]+)(?:\(([^)]+)\))?:?\s*(.*)$")
    for c in commits:
        m = mod_re.match(c["subject"])
        if m:
            prefix = m.group(1)
            scope = m.group(2) or ""
            rest = m.group(3) or c["subject"]
            if prefix in _COMMIT_TYPES:
                c["type"] = prefix
            else:
                c["type"] = "other"
            c["scope"] = scope
            c["clean"] = rest
    commits.reverse()  # oldest → newest
    return commits


def _git_exists() -> bool:
    try:
        r = subprocess.run(
            ["git", "-C", _RETRO_DIR, "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True, timeout=5,
            stdin=subprocess.DEVNULL,
        )
        return r.returncode == 0
    except Exception:
        return False


def _date_label(date_str: str) -> str:
    """Human-friendly date heading, e.g. 'Today', 'Yesterday', or the date."""
    try:
        y, m, d = (int(x) for x in date_str.split("-"))
        d_obj = _date(y, m, d)
    except (ValueError, TypeError):
        return date_str or "Unknown"
    today = _date.today()
    if d_obj == today:
        return "Today"
    delta = (today - d_obj).days
    if delta == 1:
        return "Yesterday"
    return d_obj.strftime("%A, %B %d, %Y")


def _parse_date(text: str) -> _date | None:
    """Parse YYYY-MM-DD (or today/yesterday) into a date, else None."""
    text = text.strip()
    low = text.lower()
    if low in ("today", "now"):
        return _date.today()
    if low in ("yesterday",):
        return _date.today() - timedelta(days=1)
    m = re.match(r"^(\d{4})-(\d{2})-(\d{2})$", text)
    if m:
        try:
            return _date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            return None
    return None


_RANGE_PRESETS = ["All", "Today", "Last 7 days", "Last 30 days", "Last 90 days", "Custom\u2026"]


class ChangelogPage:
    """Repo changelog grouped by date. Read-only."""

    def __init__(self, window: "RetroSettingsWindow"):
        self._window = window
        self._content_box: Gtk.Box
        self._groups: list[tuple[str, Adw.PreferencesGroup]] = []
        self._group_rows: dict[str, list] = {}
        self._commits: list[dict] = []
        self._by_date: dict[str, list[dict]] = {}
        self._dates: list[str] = []
        self._pages: list[list[str]] = []
        self._page = 0
        self._commits_per_page = 100
        self._search_entry: Gtk.SearchEntry | None = None
        self._range_dd: Gtk.DropDown | None = None
        self._from_lbl: Gtk.Label | None = None
        self._from_entry: Gtk.Entry | None = None
        self._to_lbl: Gtk.Label | None = None
        self._to_entry: Gtk.Entry | None = None
        self._page_size_dd: Gtk.DropDown | None = None
        self._prev_btn: Gtk.Button | None = None
        self._next_btn: Gtk.Button | None = None
        self._page_label: Gtk.Label | None = None
        self._nav_bar: Gtk.Box | None = None
        self._status_lbl: Gtk.Label | None = None
        self._on_dirty_changed = None

    # ── Build ──

    def build(self, header: Adw.HeaderBar) -> Adw.ToolbarView:
        toolbar, _, content_box, _scrolled = make_page_layout(header=header)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh changelog")
        refresh_btn.connect("clicked", lambda _b: self._reload())
        header.pack_start(refresh_btn)

        self._content_box = content_box

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_margin_top(12)
        row.set_margin_start(12)
        row.set_margin_end(12)

        search = Gtk.SearchEntry()
        search.set_placeholder_text("Search commits\u2026")
        search.set_hexpand(True)
        search.connect("search-changed", lambda _e: self._apply_filter())
        self._search_entry = search
        row.append(search)

        from_lbl = Gtk.Label(label="From:")
        from_lbl.add_css_class("dim-label")
        from_lbl.set_valign(Gtk.Align.CENTER)
        from_lbl.set_visible(False)
        row.append(from_lbl)
        self._from_lbl = from_lbl
        self._from_entry = self._make_date_entry()
        row.append(self._from_entry)

        to_lbl = Gtk.Label(label="To:")
        to_lbl.add_css_class("dim-label")
        to_lbl.set_valign(Gtk.Align.CENTER)
        to_lbl.set_visible(False)
        row.append(to_lbl)
        self._to_lbl = to_lbl
        self._to_entry = self._make_date_entry()
        row.append(self._to_entry)

        dd = Gtk.DropDown.new_from_strings(_RANGE_PRESETS)
        dd.set_selected(0)
        dd.connect("notify::selected", lambda *_: self._on_range_changed())
        row.append(dd)
        self._range_dd = dd

        content_box.append(row)

        self._status_lbl = Gtk.Label(label="")
        self._status_lbl.set_halign(Gtk.Align.START)
        self._status_lbl.set_margin_start(16)
        self._status_lbl.set_margin_top(8)
        self._status_lbl.add_css_class("dim-label")
        content_box.append(self._status_lbl)

        self._build_pagination_bar()

        if not _git_exists():
            self._status_lbl.set_label("Not a git repository — no changelog available.")
            return toolbar

        self._reload()
        return toolbar

    def _build_pagination_bar(self) -> None:
        nav = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        nav.set_halign(Gtk.Align.CENTER)
        nav.set_margin_top(10)
        nav.set_margin_bottom(4)

        size_lbl = Gtk.Label(label="Per page:")
        size_lbl.add_css_class("dim-label")
        size_lbl.set_valign(Gtk.Align.CENTER)
        nav.append(size_lbl)

        size_dd = Gtk.DropDown.new_from_strings(["50", "100", "250", "500"])
        size_dd.set_selected(1)
        size_dd.connect("notify::selected", lambda *_: self._on_page_size_changed())
        nav.append(size_dd)
        self._page_size_dd = size_dd

        prev = Gtk.Button(label="Previous")
        prev.connect("clicked", lambda _b: self._goto_page(self._page - 1))
        prev.set_sensitive(False)
        nav.append(prev)
        self._prev_btn = prev

        self._page_label = Gtk.Label(label="")
        self._page_label.set_valign(Gtk.Align.CENTER)
        nav.append(self._page_label)

        nxt = Gtk.Button(label="Next")
        nxt.connect("clicked", lambda _b: self._goto_page(self._page + 1))
        nxt.set_sensitive(False)
        nav.append(nxt)
        self._next_btn = nxt

        self._nav_bar = nav

    def _on_page_size_changed(self) -> None:
        if self._page_size_dd is not None:
            val = int(self._page_size_dd.get_selected_item().get_string())
            self._commits_per_page = val
        self._page = 0
        self._apply_filter()

    def _make_date_entry(self) -> Gtk.Entry:
        entry = Gtk.Entry()
        entry.set_placeholder_text("YYYY-MM-DD")
        entry.set_width_chars(10)
        entry.set_visible(False)
        entry.connect("changed", lambda *_: self._apply_filter())
        return entry

    def _on_range_changed(self) -> None:
        idx = self._range_dd.get_selected() if self._range_dd is not None else 0
        custom = idx == len(_RANGE_PRESETS) - 1
        for w in (self._from_lbl, self._from_entry, self._to_lbl, self._to_entry):
            if w is not None:
                w.set_visible(custom)
        self._apply_filter()

    # ── Data ──

    def _reload(self) -> None:
        if self._status_lbl is not None:
            self._status_lbl.set_label("Loading commits\u2026")

        def worker():
            commits = _fetch_commits()
            GLib.idle_add(self._on_loaded, commits)

        threading.Thread(target=worker, daemon=True).start()

    def _on_loaded(self, commits: list[dict]) -> None:
        self._commits = commits
        if self._status_lbl is not None:
            if not commits:
                self._status_lbl.set_label("No commits found.")
            else:
                self._status_lbl.set_label(f"{len(commits)} commits")
        self._apply_filter()

    def _range_bounds(self) -> tuple[_date | None, _date | None]:
        """Return (from_date, to_date) from the preset or custom entries."""
        idx = self._range_dd.get_selected() if self._range_dd is not None else 0
        today = _date.today()
        presets = {
            1: (today, today),
            2: (today - timedelta(days=6), today),
            3: (today - timedelta(days=29), today),
            4: (today - timedelta(days=89), today),
        }
        if idx in presets:
            return presets[idx]
        if idx == len(_RANGE_PRESETS) - 1:
            from_txt = self._from_entry.get_text() if self._from_entry else ""
            to_txt = self._to_entry.get_text() if self._to_entry else ""
            return _parse_date(from_txt), _parse_date(to_txt)
        return None, None

    def _matches_term(self, c: dict, term: str) -> bool:
        if not term:
            return True
        if term in c["subject"].lower() or term in c["scope"].lower():
            return True
        return term in c["date"]

    def _apply_filter(self) -> None:
        term = (self._search_entry.get_text() if self._search_entry else "").strip().lower()
        date_q = _parse_date(term)
        from_d, to_d = self._range_bounds()

        self._by_date = {}
        self._dates = []
        self._pages = []

        if self._commits:
            by_date: dict[str, list[dict]] = {}
            for c in self._commits:
                # Range check.
                cd = _parse_date(c["date"])
                if from_d is not None and (cd is None or cd < from_d):
                    continue
                if to_d is not None and (cd is None or cd > to_d):
                    continue
                # Search term check: explicit date query takes precedence over text.
                if date_q is not None:
                    if cd is None or cd != date_q:
                        continue
                elif not self._matches_term(c, term):
                    continue
                by_date.setdefault(c["date"], []).append(c)

            # Features first (ascending rank), newest commit within each type first.
            for date in by_date:
                by_date[date].sort(key=lambda c: c["sha"], reverse=True)
                by_date[date].sort(key=lambda c: _type_rank(c["type"]))

            self._by_date = by_date
            self._dates = sorted(by_date.keys(), reverse=True)

            # Build pages by commit count, never splitting a day across pages.
            page_dates: list[str] = []
            page_count = 0
            for date in self._dates:
                n = len(by_date[date])
                if page_dates and page_count + n > self._commits_per_page:
                    self._pages.append(page_dates)
                    page_dates = []
                    page_count = 0
                page_dates.append(date)
                page_count += n
            if page_dates:
                self._pages.append(page_dates)

        self._page = max(0, min(self._page, max(0, len(self._pages) - 1)))
        self._render_page()

    def _render_page(self) -> None:
        # Clear existing groups (nav bar is detached and re-appended at the end).
        nav = self._nav_bar
        if nav is not None and nav.get_parent() is self._content_box:
            self._content_box.remove(nav)
        for date_key, group in self._groups:
            for row in self._group_rows.get(date_key, []):
                group.remove(row)
        self._group_rows = {}
        for _date_key, group in self._groups:
            self._content_box.remove(group)
        self._groups = []

        if not self._pages:
            if self._page_label is not None:
                self._page_label.set_label("")
            if self._prev_btn is not None:
                self._prev_btn.set_sensitive(False)
            if self._next_btn is not None:
                self._next_btn.set_sensitive(False)
            if nav is not None:
                self._content_box.append(nav)
            return

        for date in self._pages[self._page]:
            label = _date_label(date)
            group = Adw.PreferencesGroup(title=label)
            self._content_box.append(group)
            self._groups.append((date, group))
            self._group_rows[date] = []
            for c in self._by_date[date]:
                row = self._make_commit_row(c)
                group.add(row)
                self._group_rows[date].append(row)

        if nav is not None:
            self._content_box.append(nav)

        total_pages = len(self._pages)
        if self._page_label is not None:
            self._page_label.set_label(f"Page {self._page + 1} of {total_pages}")
        if self._prev_btn is not None:
            self._prev_btn.set_sensitive(self._page > 0)
        if self._next_btn is not None:
            self._next_btn.set_sensitive(self._page < total_pages - 1)

    def _goto_page(self, page: int) -> None:
        total_pages = len(self._pages)
        self._page = max(0, min(page, max(0, total_pages - 1)))
        self._render_page()

    # ── Rendering ──

    def _make_commit_row(self, c: dict) -> Gtk.ListBoxRow:
        row = Adw.ActionRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_top(2)
        box.set_margin_bottom(2)

        label, css, glyph = _COMMIT_TYPES.get(
            c["type"], ("Other", "changelog-other", "\U000f02d7")
        )
        badge = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        badge.add_css_class("badge")
        badge.add_css_class(css)
        badge.set_valign(Gtk.Align.CENTER)

        glyph_lbl = Gtk.Label(label=glyph)
        glyph_lbl.set_valign(Gtk.Align.CENTER)
        badge.append(glyph_lbl)

        text_lbl = Gtk.Label(label=label)
        text_lbl.set_valign(Gtk.Align.CENTER)
        badge.append(text_lbl)

        box.append(badge)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text_box.set_hexpand(True)

        subject = c["clean"] or c["subject"]
        if c["scope"]:
            scope_display = c["scope"][:1].upper() + c["scope"][1:]
            subject = f"{scope_display}: {subject}"
        subj_lbl = Gtk.Label(label=subject)
        subj_lbl.set_halign(Gtk.Align.START)
        subj_lbl.set_xalign(0.0)
        subj_lbl.set_ellipsize(3)
        text_box.append(subj_lbl)

        meta = f"{c['sha']} \u00b7 {c['author']}"
        meta_lbl = Gtk.Label(label=meta)
        meta_lbl.set_halign(Gtk.Align.START)
        meta_lbl.set_xalign(0.0)
        meta_lbl.add_css_class("caption")
        meta_lbl.add_css_class("dim-label")
        text_box.append(meta_lbl)

        box.append(text_box)

        copy_btn = Gtk.Button(icon_name="edit-copy-symbolic")
        copy_btn.add_css_class("flat")
        copy_btn.add_css_class("reset-button")
        copy_btn.set_valign(Gtk.Align.CENTER)
        copy_btn.set_tooltip_text("Copy full commit hash")
        full_sha = c.get("full_sha", c["sha"])
        copy_btn.connect("clicked", lambda _b: self._copy_hash(full_sha))
        box.append(copy_btn)

        row.set_child(box)
        return row

    def _copy_hash(self, full_sha: str) -> None:
        try:
            self._window.get_clipboard().set(full_sha)
            self._window.show_toast(f"Copied {full_sha}", timeout=2)
        except Exception:
            pass

    # ── Lifecycle (read-only) ──

    def is_dirty(self) -> bool:
        return False

    def mark_saved(self) -> None:
        pass

    def discard(self) -> None:
        pass

    def iter_pending_changes(self) -> Iterable[PendingChange]:
        return ()

    # ── Search ──

    def get_search_entries(self) -> list[dict]:
        return [
            {"key": "changelog:overview", "label": "Changelog",
             "description": "Recent repository commits grouped by date",
             "_group_id": "changelog", "_group_label": "Changelog",
             "_section_label": "Overview"},
        ]


__all__ = ["ChangelogPage"]
