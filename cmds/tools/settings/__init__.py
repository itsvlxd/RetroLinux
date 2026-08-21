"""Retro Settings — GTK4/libadwaita configuration tool for Hyprland."""

import sys as _sys

def _dbg(msg: str) -> None:
    if "--debug" in _sys.argv or "-d" in _sys.argv:
        print(f"[settings.__init__] {msg}", file=_sys.stderr, flush=True)

_dbg("Package init starting")
import settings.gi_setup  # noqa: F401
_dbg("gi_setup imported")

# --- Monkey-patch hyprland_state to handle both version formats ---
# _detect_version() returns "X.Y.Z" (no v prefix) but hyprland_schema
# keys versions by GitHub tags ("vX.Y.Z").  The upstream _load_schema
# passes the bare version straight through, causing build_options() to
# miss every bundled/cache lookup and fall through to a network fetch.
# Patch _load_schema to normalise the tag so both formats resolve
# instantly from the bundled catalog or disk cache.
try:
    import hyprland_state._state as _hs_state
    _orig_load_schema = _hs_state._load_schema

    def _patched_load_schema(version):  # type: ignore[no-untyped-def]
        if version is None:
            return _orig_load_schema(version)
        tag = version if version.startswith("v") else f"v{version}"
        try:
            import hyprland_schema
            return hyprland_schema.load(tag).options_by_key
        except hyprland_schema.MigrationError:
            pass
        # Caller may already supply a v-prefixed tag; try bare.
        bare = version[1:] if version.startswith("v") else version
        try:
            import hyprland_schema
            return hyprland_schema.load(bare).options_by_key
        except hyprland_schema.MigrationError:
            import hyprland_schema
            return hyprland_schema.OPTIONS_BY_KEY

    _hs_state._load_schema = _patched_load_schema
    _dbg("patched _load_schema to normalise version tags")
except Exception as _exc:
    _dbg(f"could not patch _load_schema: {_exc}")
