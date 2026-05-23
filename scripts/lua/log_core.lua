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

local _registered = {}
local _log_dir = "/tmp/retro_logs"

os.execute("mkdir -p " .. _log_dir)

local function _get_log_path(id)
    return _log_dir .. "/" .. id .. ".log"
end

local function _get_disabled_path(id)
    return _log_dir .. "/" .. id .. ".disabled"
end

local function _is_disabled(id)
    local path = _get_disabled_path(id)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function _rotate(path, max_lines)
    max_lines = max_lines or 500
    local f = io.open(path, "r")
    if not f then return end

    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()

    if #lines > max_lines then
        local tmp = {}
        local start = #lines - max_lines + 1
        for i = start, #lines do
            table.insert(tmp, lines[i])
        end
        f = io.open(path, "w")
        if f then
            for _, line in ipairs(tmp) do
                f:write(line .. "\n")
            end
            f:close()
        end
    end
end

local function _write_to_log(id, log_line)
    local path = _get_log_path(id)
    local f = io.open(path, "a")
    if not f then return end
    f:write(log_line .. "\n")
    f:close()
    _rotate(path)
end

function Log.register(id)
    if not id or id == "" then return false end
    _registered[id] = true
    local path = _get_log_path(id)
    local f = io.open(path, "r")
    if not f then
        f = io.open(path, "w")
        if f then f:close() end
    end
    return true
end

function Log.log(level, message, target_id)
    level = string.upper(level or "info")
    local ts = os.date("%Y-%m-%d %H:%M:%S")
    local log_line = string.format("[%s] [%s] %s", ts, level, message)

    if target_id then
        if not _is_disabled(target_id) then
            _write_to_log(target_id, log_line)
        end
        return
    end

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

    for id, _ in pairs(_registered) do
        if not _is_disabled(id) then
            _write_to_log(id, log_line)
        end
    end
end

function Log.info(message) Log.log("info", message) end
function Log.success(message) Log.log("success", message) end
function Log.warn(message) Log.log("warn", message) end
function Log.error(message) Log.log("error", message) end

function Log.disable(id)
    local path = _get_disabled_path(id)
    local f = io.open(path, "w")
    if f then f:close() end
end

function Log.enable(id)
    os.remove(_get_disabled_path(id))
end

function Log.is_disabled(id)
    return _is_disabled(id)
end

function Log.list()
    local result = {}
    for id, _ in pairs(_registered) do
        table.insert(result, id)
    end
    return result
end

function Log.tail(id, limit)
    limit = limit or 30
    local path = _get_log_path(id)
    local f = io.open(path, "r")
    if not f then return {} end

    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()

    if #lines > limit then
        local result = {}
        for i = #lines - limit + 1, #lines do
            table.insert(result, lines[i])
        end
        return result
    end

    return lines
end

function Log.clear(id)
    local path = _get_log_path(id)
    local f = io.open(path, "w")
    if f then f:close() end
end

function Log.status()
    local result = {}
    for id, _ in pairs(_registered) do
        local path = _get_log_path(id)
        local f = io.open(path, "r")
        if f then
            local lines = {}
            for line in f:lines() do
                table.insert(lines, line)
            end
            f:close()

            local last = lines[#lines] or "(empty)"
            local size_handle = io.popen("du -h '" .. path .. "' 2>/dev/null | cut -f1")
            local size = size_handle:read("*l") or "0"
            size_handle:close()

            table.insert(result, {
                id = id,
                lines = #lines,
                size = size,
                last = last,
            })
        end
    end
    return result
end

return Log
