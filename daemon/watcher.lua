local Watcher = {}

local _vars_cache = {}
local _vars_file = nil
local _vars_mtime = 0

local _log_caps = {}
local _log_enabled = nil
local _log_dir = "/tmp/retro_logs"

os.execute("mkdir -p " .. _log_dir)

local function _get_vars_file()
    if _vars_file then return _vars_file end
    local retro_config = os.getenv("RETRO_CONFIG")
    if not retro_config or retro_config == "" then
        local home = os.getenv("HOME") or "/tmp"
        retro_config = home .. "/.config/retro"
    end
    _vars_file = retro_config .. "/variables.sh"
    return _vars_file
end

local function _get_mtime(path)
    local f = io.open(path, "r")
    if not f then return 0 end
    f:close()
    local result = io.popen("stat -c %Y '" .. path .. "' 2>/dev/null")
    if not result then return 0 end
    local mtime = result:read("*l")
    result:close()
    return tonumber(mtime) or 0
end

local function _parse_vars_file()
    local path = _get_vars_file()
    local current_mtime = _get_mtime(path)
    if current_mtime == _vars_mtime and current_mtime ~= 0 then return end
    _vars_mtime = current_mtime
    _vars_cache = {}

    local f = io.open(path, "r")
    if not f then return end

    for line in f:lines() do
        local key, val = line:match('^export%s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
        if key then
            val = val:gsub('^"', ''):gsub('"$', '')
            val = val:gsub("^'", ""):gsub("'$", "")
            _vars_cache[key] = val
        end
    end
    f:close()
end

function Watcher.get_var(key, default)
    _parse_vars_file()
    local val = _vars_cache[key]
    if val == nil then
        return default or ""
    end
    return val
end

function Watcher.set_var(key, value)
    if not key or key == "" then return false end
    _vars_cache[key] = value

    local path = _get_vars_file()
    local dir = path:match("(.+)/")
    if dir then os.execute("mkdir -p '" .. dir .. "'") end

    local lines = {}
    local found = false
    local f = io.open(path, "r")
    if f then
        for line in f:lines() do
            if line:match("^export " .. key .. "=") then
                table.insert(lines, 'export ' .. key .. '="' .. value .. '"')
                found = true
            else
                table.insert(lines, line)
            end
        end
        f:close()
    end

    if not found then
        table.insert(lines, 'export ' .. key .. '="' .. value .. '"')
    end

    f = io.open(path, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
    end

    _vars_mtime = _get_mtime(path)
    return true
end

function Watcher.reload_vars()
    _vars_mtime = 0
    _parse_vars_file()
end

function Watcher.run_cmd(cmd)
    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

function Watcher.read_sys(path)
    local f = io.open(path, "r")
    if not f then return "" end
    local val = f:read("*l")
    f:close()
    return val or ""
end

function Watcher.has_battery()
    local bat_path = Watcher.get_var("BAT_PATH")
    if bat_path and bat_path ~= "" and bat_path ~= "null" then
        local f = io.open(bat_path .. "/capacity", "r")
        if f then f:close(); return true end
    end
    local result = Watcher.run_cmd("ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1")
    if result ~= "" then
        Watcher.set_var("BAT_PATH", result)
        return true
    end
    return false
end

function Watcher.has_bluetooth()
    local result = Watcher.run_cmd("bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo ok")
    return result == "ok"
end

function Watcher.parse_pipe(line)
    local fields = {}
    for field in line:gmatch("([^|]*)") do
        table.insert(fields, field)
    end
    return fields
end

function Watcher.time()
    return os.time()
end

function Watcher.sleep(seconds)
    os.execute("sleep " .. tostring(seconds))
end

function Watcher.get_log_path(name)
    return _log_dir .. "/watcher_" .. name .. ".log"
end

function Watcher.get_log_cap(name)
    return _log_caps[name] or 100
end

function Watcher.set_log_cap(name, cap)
    _log_caps[name] = cap
end

function Watcher.is_log_enabled()
    if _log_enabled == nil then
        local val = Watcher.get_var("RETRO_EVENT_LOG_ENABLED", "true")
        _log_enabled = (val == "true")
    end
    return _log_enabled
end

function Watcher.set_log_enabled(enabled)
    _log_enabled = enabled
    Watcher.set_var("RETRO_EVENT_LOG_ENABLED", enabled and "true" or "false")
end

function Watcher.is_log_disabled(name)
    local disabled_file = _log_dir .. "/watcher_" .. name .. ".disabled"
    local f = io.open(disabled_file, "r")
    if f then f:close(); return true end
    return false
end

function Watcher.log(name, msg)
    if not Watcher.is_log_enabled() then return end
    if Watcher.is_log_disabled(name) then return end

    local log_path = Watcher.get_log_path(name)
    local cap = Watcher.get_log_cap(name)

    local f = io.open(log_path, "a")
    if not f then return end

    local ts = os.date("%Y-%m-%d %H:%M:%S")
    f:write(string.format("[%s] [INFO] %s\n", ts, msg))
    f:close()

    local lines = {}
    local lf = io.open(log_path, "r")
    if lf then
        for line in lf:lines() do
            table.insert(lines, line)
        end
        lf:close()
    end

    if #lines > cap then
        local start = #lines - cap + 1
        lf = io.open(log_path, "w")
        if lf then
            for i = start, #lines do
                lf:write(lines[i] .. "\n")
            end
            lf:close()
        end
    end
end

function Watcher.tail_log(name, limit)
    local log_path = Watcher.get_log_path(name)
    limit = limit or 30

    local f = io.open(log_path, "r")
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

function Watcher.clear_log(name)
    local log_path = Watcher.get_log_path(name)
    local f = io.open(log_path, "w")
    if f then f:close() end
end

function Watcher.list_logs()
    local logs = {}
    local handle = io.popen("ls " .. _log_dir .. "/watcher_*.log 2>/dev/null")
    if handle then
        for line in handle:lines() do
            local name = line:match("watcher_(.+)%.log")
            if name then
                table.insert(logs, name)
            end
        end
        handle:close()
    end
    return logs
end

return Watcher
