import os
import re

_VARS_FILE = None
_VARS_CACHE = {}
_VARS_MTIME = 0


def _get_vars_file():
    global _VARS_FILE
    if _VARS_FILE:
        return _VARS_FILE
    retro_config = os.environ.get("RETRO_CONFIG", "")
    if not retro_config:
        home = os.environ.get("HOME", "/tmp")
        retro_config = os.path.join(home, ".config", "retro")
    _VARS_FILE = os.path.join(retro_config, "variables.sh")
    return _VARS_FILE


def _get_mtime(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return 0


def _strip_quotes(val):
    """Remove a single matching pair of surrounding quotes, preserving any
    quote chars inside the value (e.g. ``hyprctl dispatch 'hl.dsp.exit()'``)."""
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
        return val[1:-1]
    return val


def _parse_vars_file():
    global _VARS_MTIME, _VARS_CACHE
    path = _get_vars_file()
    current_mtime = _get_mtime(path)
    if current_mtime == _VARS_MTIME:
        return
    _VARS_MTIME = current_mtime
    _VARS_CACHE = {}

    try:
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                match = re.match(r"^export\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
                if match:
                    key = match.group(1)
                    val = match.group(2)
                    val = _strip_quotes(val)
                    _VARS_CACHE[key] = val
    except FileNotFoundError:
        pass


def get_var(key, default=""):
    _parse_vars_file()
    return _VARS_CACHE.get(key, default)


def set_var(key, value):
    if not key:
        return False
    _VARS_CACHE[key] = value
    path = _get_vars_file()

    os.makedirs(os.path.dirname(path), exist_ok=True)

    lines = []
    found = False
    try:
        with open(path, "r") as f:
            for line in f:
                if re.match(rf"^export\s+{re.escape(key)}=", line):
                    lines.append(f'export {key}="{value}"\n')
                    found = True
                else:
                    lines.append(line)
    except FileNotFoundError:
        pass

    if not found:
        lines.append(f'export {key}="{value}"\n')

    with open(path, "w") as f:
        f.writelines(lines)

    _VARS_MTIME = _get_mtime(path)
    return True


_MODULE_VARS: dict[str, str] | None = None


def get_module_default(key: str, default: str = "") -> str:
    """Read a variable's default from the module's variables.sh, not user's."""
    global _MODULE_VARS
    if _MODULE_VARS is None:
        _MODULE_VARS = {}
        retro_dir = os.environ.get("RETRO_DIR", "")
        path = os.path.join(retro_dir, "modules", "retro", "files", "variables.sh")
        try:
            with open(path, "r") as f:
                for line in f:
                    line = line.strip()
                    match = re.match(r"^export\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
                    if match:
                        val = _strip_quotes(match.group(2))
                        _MODULE_VARS[match.group(1)] = val
        except FileNotFoundError:
            pass
    return _MODULE_VARS.get(key, default)


def reload_vars():
    global _VARS_MTIME
    _VARS_MTIME = 0
    _parse_vars_file()
