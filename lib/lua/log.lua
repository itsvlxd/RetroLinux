local Colors = require("colors")

local Log = {}

local ICONS = {
    INFO = " ",
    SUCCESS = " ",
    WARN = " ",
    ERROR = "󰅙 ",
}

local COLORS = {
    INFO = Colors.PINK,
    SUCCESS = Colors.SUCCESS,
    WARN = Colors.WARN,
    ERROR = Colors.ERROR,
}

function Log.log(level, message)
    level = string.upper(level or "info")
    local icon = ICONS[level] or "󰀦 "
    local color = COLORS[level] or Colors.RESET

    local is_prompt = false
    if message:match("%[[%s]*[Yy]/[Nn][%s]*%]:") or
       message:match("%[[%s]*[Yy]/[Nn][%s]*%]$") or
       message:match("%[Default:") then
        is_prompt = true
    end

    if is_prompt then
        io.write(string.format("%s[%s%s]%s %s", color, icon, level, Colors.RESET, message))
    else
        io.write(string.format("%s[%s%s]%s %s\n", color, icon, level, Colors.RESET, message))
    end
end

function Log.info(message) Log.log("info", message) end
function Log.success(message) Log.log("success", message) end
function Log.warn(message) Log.log("warn", message) end
function Log.error(message) Log.log("error", message) end

return Log
