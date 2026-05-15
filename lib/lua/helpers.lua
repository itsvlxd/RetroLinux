local Variable = require("variable")

local Helpers = {}

function Helpers.format_time(t)
    if not t or t == "null" then return "Disabled" end

    if t < 60 then
        return tostring(t) .. " seconds"
    elseif t < 3600 then
        return tostring(math.floor(t / 60)) .. " minutes"
    elseif t < 86400 then
        return tostring(math.floor(t / 3600)) .. " hours"
    elseif t < 604800 then
        return tostring(math.floor(t / 86400)) .. " days"
    elseif t < 2592000 then
        return tostring(math.floor(t / 604800)) .. " weeks"
    else
        return tostring(math.floor(t / 2592000)) .. " months"
    end
end

function Helpers.format_size(size)
    if not size or size == "0" then return "0 B" end

    local units = {"B", "KB", "MB", "GB"}
    local i = 1

    while size > 1024 and i < 4 do
        size = size / 1024
        i = i + 1
    end

    return string.format("%.2f %s", size, units[i])
end

function Helpers.format_string(name)
    name = name:gsub("%.[^%.]*$", "")
    name = name:gsub("%.[0-9]*x[0-9]*", "")
    name = name:gsub("-", " ")
    name = name:gsub("_", " ")
    name = name:gsub("(%a)(%a*)", function(first, rest)
        return string.upper(first) .. rest
    end)
    return name
end

function Helpers.get_opacity_hex(multiplier)
    local base_opacity = Variable.get_var("RETRO_OPACITY", "1.0")
    if base_opacity == "1.0" then return "FF" end

    multiplier = multiplier or 1.0
    local opacity_int = math.floor(base_opacity * multiplier * 255 + 0.5)
    if opacity_int > 255 then opacity_int = 255 end
    if opacity_int < 0 then opacity_int = 0 end

    return string.format("%02x", opacity_int)
end

function Helpers.get_battery_icon(capacity, state)
    if state and state:match("charging") and not state:match("discharging") then
        return "󱐋"
    end

    if capacity >= 95 then return "󰁹"
    elseif capacity >= 85 then return "󰂂"
    elseif capacity >= 75 then return "󰂁"
    elseif capacity >= 65 then return "󰂀"
    elseif capacity >= 55 then return "󰁿"
    elseif capacity >= 45 then return "󰁾"
    elseif capacity >= 35 then return "󰁽"
    elseif capacity >= 25 then return "󰁼"
    elseif capacity >= 15 then return "󰁻"
    else return "󰂃"
    end
end

function Helpers.run_cmd(cmd)
    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

return Helpers
