"""Convert live Hyprland bind IPC snapshots into the editor's bind shape.

Both helpers run as pure functions over data the page hands in, so they
test in isolation without instantiating any GTK widgets.

- :func:`live_bind_to_data` flattens Hyprland's flag-variant binds
  (``bindm``/``binde``/``bindl``/…) back into the original ``bind_type``
  so overrides round-trip the variant the user actually wrote.
- :func:`enrich_lua_binds` repairs the opaque ``__lua: <line>`` entries
  Hyprland's Lua runtime reports by matching them against the
  hyprland-config Document's parsed bind keywords.
"""

import os

from hyprland_config import BindData, Document, is_bind_keyword, parse_bind_line
from hyprland_socket import Bind, modmask_to_str

from settings.core.config import RETRO_FN_MAP, keybinds_path


def live_bind_to_data(b: Bind) -> BindData:
    """Convert a Hyprland live :class:`Bind` to a :class:`BindData`.

    Hyprland reports flag-variant binds (``bindm``/``binde``/``bindl``/…)
    as plain ``bind`` entries with boolean flags; this restores the
    original ``bind_type`` so overrides round-trip correctly. For mouse
    binds the runtime also reports ``dispatcher="mouse"`` with the real
    dispatcher in ``arg``, which is unwound here so categorisation works.
    """
    if b.mouse:
        bind_type = "bindm"
    elif b.repeat:
        bind_type = "binde"
    elif b.locked:
        bind_type = "bindl"
    elif b.release:
        bind_type = "bindr"
    elif b.non_consuming:
        bind_type = "bindn"
    else:
        bind_type = "bind"

    # Hyprland's ``bindm`` IPC representation: ``dispatcher="mouse"``
    # with the real dispatcher (``movewindow``/``resizewindow``) in
    # ``arg``.
    if b.mouse and b.dispatcher == "mouse":
        dispatcher = b.arg
        arg = ""
    else:
        dispatcher = b.dispatcher
        arg = b.arg

    return BindData(
        bind_type=bind_type,
        mods=modmask_to_str(b.modmask).split(" + ") if b.modmask else [],
        key=b.key,
        dispatcher=dispatcher,
        arg=arg,
    )


def enrich_lua_binds(live: list[BindData], document: Document) -> list[BindData]:
    """Replace ``__lua`` IPC dispatchers with the real ones from *document*.

    In Lua mode Hyprland reports every bind with ``dispatcher = "__lua"``
    and ``arg = "<lineno>"`` — the runtime stores the bind body as a Lua
    closure with no nameable dispatcher. The hyprland-config Lua reader
    has already walked the user's config and produced ``bind = …``
    keywords with real Hyprlang-style dispatcher names. Match by combo
    (mods + key) and swap the opaque ``__lua`` entry for the rich one
    so the binds page can categorise and label them correctly.

    Live binds without a ``__lua`` dispatcher pass through unchanged.
    Combos that aren't in *document* (handler defined directly via
    ``hl.bind`` with a closure the reader can't unwrap) also pass through
    so the user at least sees that the bind exists — they'll land in
    "Advanced" and read as ``__lua: <line>``, which is an acceptable
    degradation for an inherently opaque setup.
    """
    if not any(b.dispatcher == "__lua" for b in live):
        return live
    by_combo: dict[tuple, BindData] = {}
    for kw in document.find_all("bind*"):
        if not is_bind_keyword(kw.key):
            continue
        parsed = parse_bind_line(document.expand(kw.raw.strip()))
        if parsed is not None:
            # Document order means earlier binds win on duplicates,
            # mirroring Hyprland's "first match" runtime behaviour.
            by_combo.setdefault(parsed.combo, parsed)

    enriched: list[BindData] = []
    for b in live:
        if b.dispatcher != "__lua":
            enriched.append(b)
            continue
        # Try to resolve from document error lines first (opaque Lua closures
        # like ``Retro.open_terminal`` that the reader couldn't parse at all).
        # This takes priority over the document match because the error
        # represents the actual Lua bind that Hyprland's runtime is running.
        src_disp, src_arg = _resolve_from_errors(document, b)
        if src_disp:
            enriched.append(
                BindData(
                    bind_type=b.bind_type,
                    mods=list(b.mods),
                    key=b.key,
                    dispatcher=src_disp,
                    arg=src_arg,
                )
            )
            continue

        match = by_combo.get(b.combo)
        if match is None:
            # Fallback: try known Retro source files at the __lua line.
            # The library's Lua reader silently drops hl.bind(..., Retro.fn)
            # with no errors or keywords, so _resolve_from_errors and the
            # by_combo lookup both miss them.
            src_disp, src_arg = _try_retro_source_file(b)
            if src_disp:
                enriched.append(
                    BindData(
                        bind_type=b.bind_type,
                        mods=list(b.mods),
                        key=b.key,
                        dispatcher=src_disp,
                        arg=src_arg,
                    )
                )
                continue
            enriched.append(b)
            continue

        dispatcher = match.dispatcher
        arg = match.arg

        # Post-process: if the document couldn't resolve the dispatcher
        # (e.g. Retro.* Lua closures), try reading the source line.
        if not dispatcher:
            src_disp, src_arg = _resolve_lua_source(document, b, match)
            if src_disp:
                dispatcher = src_disp
                arg = src_arg

        # Preserve the live bind's flag-derived bind_type — the document
        # entry's bind_type carries the same info but the live IPC is
        # authoritative for which variant is currently registered.
        enriched.append(
            BindData(
                bind_type=b.bind_type,
                mods=list(b.mods),
                key=b.key,
                dispatcher=dispatcher,
                arg=arg,
            )
        )
    return enriched


def _resolve_lua_source(
    document: Document, live_bind: BindData, match: BindData
) -> tuple[str, str]:
    """Try to resolve a Lua bind's dispatcher by reading the source file.

    Handles binds using Lua closures (e.g. ``Retro.open_terminal``) that
    the hyprland-config Lua reader can't translate into standard
    Hyprland dispatchers.  Returns ``(dispatcher, "")`` or ``("", "")``
    when the source doesn't match any known pattern.
    """
    for kw in document.find_all("bind*"):
        if not is_bind_keyword(kw.key):
            continue
        parsed = parse_bind_line(document.expand(kw.raw.strip()))
        if parsed is not None and parsed.combo == match.combo:
            source = getattr(kw, "source_name", None)
            if source and os.path.exists(source):
                try:
                    lineno = int(live_bind.arg) if live_bind.arg else -1
                    with open(source) as f:
                        if lineno > 0:
                            lines = f.readlines()
                            if lineno <= len(lines):
                                line = lines[lineno - 1].strip()
                                for pattern, disp in RETRO_FN_MAP.items():
                                    if pattern in line:
                                        return disp, ""
                except (OSError, ValueError, IndexError):
                    pass
            break
    return "", ""


def _resolve_from_errors(
    document: Document, live_bind: BindData
) -> tuple[str, str]:
    """Resolve a Lua bind from document error source files (opaque Retro closures).

    The hyprland-config Lua reader can't parse ``hl.bind("KEY", Retro.*)``
    calls (string concat + function ref), so they produce no keywords in the
    document.  However, the reader *does* record them as ``ErrorLine`` entries
    with the ``source_name`` (the file path) — even if only one error per file
    is recorded, we can still read the file directly.

    Collects unique source file paths from all document errors, reads the
    source line at ``live_bind.arg`` (the ``__lua: <lineno>`` arg), and checks
    for known Retro function patterns.
    Returns ``(dispatcher, arg)`` or ``("", "")``.
    """
    lineno = int(live_bind.arg) if live_bind.arg else -1
    if lineno <= 0:
        return "", ""

    # Collect unique source file paths from all document errors
    source_paths: set[str] = set()
    for error in getattr(document, "errors", []):
        src = getattr(error, "source_name", None)
        if src and os.path.exists(src):
            source_paths.add(src)

    # Read each source file at the __lua line number
    for source in source_paths:
        try:
            with open(source) as f:
                lines = f.readlines()
            if lineno <= len(lines):
                line = lines[lineno - 1].strip()
                for pattern, disp in RETRO_FN_MAP.items():
                    if pattern in line:
                        return disp, ""
        except (OSError, ValueError, IndexError):
            continue
    return "", ""


def _try_retro_source_file(live_bind: BindData) -> tuple[str, str]:
    """Try to resolve a ``__lua`` bind from known Retro source files.

    The hyprland-config Lua reader silently drops ``hl.bind("KEY", Retro.fn)``
    calls — no keywords, no error entries.  When the line number from the live
    IPC bind points to a known source file, read it directly and check for
    ``Retro.*`` function patterns.
    """
    lineno = int(live_bind.arg) if live_bind.arg else -1
    if lineno <= 0:
        return "", ""
    retro_dir = os.environ.get("RETRO_DIR", "/opt/retrolinux")
    sources: list[str] = [
        os.path.join(retro_dir, "modules", "hyprland", "files", "keybinds.lua"),
    ]
    kb_override = keybinds_path()
    if kb_override.exists():
        sources.append(str(kb_override))
    for source in sources:
        if not os.path.exists(source):
            continue
        try:
            with open(source) as f:
                lines = f.readlines()
            if lineno <= len(lines):
                line = lines[lineno - 1].strip()
                for pattern, disp in RETRO_FN_MAP.items():
                    if pattern in line:
                        return disp, ""
        except (OSError, ValueError, IndexError):
            continue
    return "", ""
