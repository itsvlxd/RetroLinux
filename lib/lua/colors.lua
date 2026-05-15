local Colors = {}

Colors.PINK = "\27[38;5;5m"
Colors.GRAY = "\27[38;2;108;112;134m"
Colors.MUTE = "\27[38;2;69;71;90m"
Colors.RESET = "\27[0m"
Colors.BOLD = "\27[1m"
Colors.SUCCESS = "\27[38;5;76m"
Colors.WARN = "\27[38;5;214m"
Colors.ERROR = "\27[38;5;196m"
Colors.LABEL = "\27[38;5;244m"

function Colors.strip_ansi(str)
    return str:gsub("\27%[[0-9;]*m", "")
end

return Colors
