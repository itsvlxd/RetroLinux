import os


def ensure_dbus():
    if "DBUS_SESSION_BUS_ADDRESS" not in os.environ:
        os.environ["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path=/run/user/{os.getuid()}/bus"


def get_shell_env(overrides=None):
    env = {
        "DISPLAY": os.environ.get("DISPLAY", ""),
        "DBUS_SESSION_BUS_ADDRESS": os.environ.get("DBUS_SESSION_BUS_ADDRESS", ""),
        "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR", ""),
        "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
        "RETRO_DIR": os.environ.get("RETRO_DIR", ""),
        "RETRO_CONFIG": os.environ.get("RETRO_CONFIG", ""),
    }
    if overrides:
        env.update(overrides)
    return env
