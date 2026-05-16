PINK   = "\033[38;5;5m"
GRAY   = "\033[38;2;108;112;134m"
MUTE   = "\033[38;2;69;71;90m"
RESET  = "\033[0m"
BOLD   = "\033[1m"
SUCCESS = "\033[38;5;76m"
WARN   = "\033[38;5;214m"
ERROR  = "\033[38;5;196m"

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


def info(message):
    rx_log("info", message)


def success(message):
    rx_log("success", message)


def warn(message):
    rx_log("warn", message)


def error(message):
    rx_log("error", message)
