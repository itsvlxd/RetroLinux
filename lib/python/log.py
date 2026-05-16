import os
import sys
import logging
from datetime import datetime

PINK   = "\033[38;5;5m"
GRAY   = "\033[38;2;108;112;134m"
MUTE   = "\033[38;2;69;71;90m"
RESET  = "\033[0m"
BOLD   = "\033[1m"
SUCCESS = "\033[38;5;76m"
WARN   = "\033[38;5;214m"
ERROR  = "\033[38;5;196m"
LABEL  = "\033[38;5;244m"

_ICONS = {
    "INFO":    " ",
    "SUCCESS": " ",
    "WARN":    " ",
    "ERROR":   "󰅙 ",
}

_COLORS = {
    "INFO":    PINK,
    "SUCCESS": SUCCESS,
    "WARN":    WARN,
    "ERROR":   ERROR,
}

_LOG_DIR = "/tmp/retro_logs"
_registered = set()

os.makedirs(_LOG_DIR, exist_ok=True)


def _get_log_path(identifier):
    return os.path.join(_LOG_DIR, f"{identifier}.log")


def _rotate(path, max_lines=500):
    try:
        with open(path, "r") as f:
            lines = f.readlines()
        if len(lines) > max_lines:
            with open(path, "w") as f:
                f.writelines(lines[-max_lines:])
    except Exception:
        pass


def register(identifier):
    if not identifier:
        return False
    _registered.add(identifier)
    path = _get_log_path(identifier)
    if not os.path.exists(path):
        open(path, "w").close()
    return True


def rx_log_file(level, message):
    level = level.upper()
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_line = f"[{ts}] [{level}] {message}\n"

    for identifier in _registered:
        path = _get_log_path(identifier)
        try:
            with open(path, "a") as f:
                f.write(log_line)
            _rotate(path)
        except Exception:
            pass


def rx_log(level, message):
    level = level.upper()
    icon = _ICONS.get(level, "󰀦 ")
    color = _COLORS.get(level, RESET)
    print(f"{color}[{icon}{level}]{RESET} {message}")


class RetroFormatter(logging.Formatter):
    _LEVEL_COLORS = {
        logging.INFO:    PINK,
        logging.WARNING: WARN,
        logging.ERROR:   ERROR,
        logging.DEBUG:   GRAY,
    }

    def format(self, record):
        color = self._LEVEL_COLORS.get(record.levelno, RESET)
        record.levelname = f"{color}{record.levelname}{RESET}"
        return super().format(record)


def setup_logger(name="obex", level=logging.INFO, stream=None):
    if stream is None:
        stream = sys.stdout

    handler = logging.StreamHandler(stream)
    handler.setFormatter(RetroFormatter("[OBEX] %(levelname)s: %(message)s"))

    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.addHandler(handler)
    return logger
