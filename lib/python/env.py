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


def _parse_vars_file():
    global _VARS_MTIME, _VARS_CACHE
    path = _get_vars_file()
    current_mtime = _get_mtime(path)
    if current_mtime == _VARS_MTIME and current_mtime != 0:
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
                    val = val.strip("\"'")
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


def reload_vars():
    global _VARS_MTIME
    _VARS_MTIME = 0
    _parse_vars_file()


def ensure_dbus():
    if "DBUS_SESSION_BUS_ADDRESS" not in os.environ:
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{os.getuid()}/bus"


def get_shell_env(overrides=None):
    env = {
        "DISPLAY": os.environ.get("DISPLAY", ""),
        "DBUS_SESSION_BUS_ADDRESS": os.environ.get("DBUS_SESSION_BUS_ADDRESS", ""),
        "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR", ""),
        "RETRO_DIR": os.environ.get("RETRO_DIR", ""),
        "RETRO_CONFIG": os.environ.get("RETRO_CONFIG", ""),
    }
    if overrides:
        env.update(overrides)
    return env
