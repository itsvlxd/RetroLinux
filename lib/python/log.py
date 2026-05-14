import sys
import logging

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
