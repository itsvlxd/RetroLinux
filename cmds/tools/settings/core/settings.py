"""Open settings's GSettings store and apply the stored config-path.

Shared by the GTK window and the headless CLI so both resolve the
managed-file path from the same source of truth.
"""

import subprocess
from pathlib import Path

from gi.repository import Gio

from settings.constants import APPLICATION_ID
from settings.core import config
from settings.data import bundled_data_dir

# The GSettings schema id matches our application id by convention.
SETTINGS_SCHEMA_ID = APPLICATION_ID


def _recompile_schemas_if_stale(schema_dir: Path) -> None:
    """Recompile GSettings schemas if the compiled file is stale or missing."""
    xml_files = list(schema_dir.glob("*.gschema.xml"))
    if not xml_files:
        return
    compiled = schema_dir / "gschemas.compiled"
    latest_xml_mtime = max(xml.stat().st_mtime for xml in xml_files)
    if not compiled.exists() or compiled.stat().st_mtime < latest_xml_mtime:
        subprocess.run(["glib-compile-schemas", str(schema_dir)], check=False)


def open_settings() -> Gio.Settings | None:
    """Open settings's GSettings store, or ``None`` when the schema is missing."""
    schema_dir = bundled_data_dir()
    _recompile_schemas_if_stale(schema_dir)
    schema_source = Gio.SettingsSchemaSource.new_from_directory(
        str(schema_dir),
        Gio.SettingsSchemaSource.get_default(),
        False,
    )
    schema_obj = schema_source.lookup(SETTINGS_SCHEMA_ID, False)
    if schema_obj is None:
        return None
    return Gio.Settings.new_full(schema_obj, None, None)


def apply_saved_config_path(settings: Gio.Settings | None) -> None:
    """Apply the stored ``config-path`` to :mod:`settings.core.config`.

    The user may have switched Hyprland's config language out-of-band
    since the path was stored, so the suffix is re-aligned to the active
    mode (converting file content if needed) and the repointed value is
    persisted back to *settings*. No-op when no override is stored.
    """
    if settings is None:
        return
    path = settings.get_string("config-path")
    if not path:
        return
    repointed = config.ensure_managed_path_matches_mode(path)
    if repointed is not None:
        settings.set_string("config-path", repointed)
        path = repointed
    config.set_managed_path(Path(path))
