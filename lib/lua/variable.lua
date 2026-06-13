local Variable = {}

local _vars_file = nil
local _vars_file_mtime = 0
local _retro_vars_cache = {}

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

local function _get_file_mtime(path)
    local handle = io.popen("stat -c %Y '" .. path .. "' 2>/dev/null || echo 0")
    if not handle then return 0 end
    local mtime = handle:read("*a")
    handle:close()
    mtime = mtime:gsub("%s+$", "")
    return tonumber(mtime) or 0
end

local function _parse_vars_file()
    local path = _get_vars_file()
    local current_mtime = _get_file_mtime(path)
    if current_mtime == _vars_file_mtime then return end
    _vars_file_mtime = current_mtime
    _retro_vars_cache = {}
    local f = io.open(path, "r")
    if not f then return end
    for line in f:lines() do
        local key, val = line:match('^export%s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
        if key then
            val = val:gsub('^"', ''):gsub('"$', '')
            val = val:gsub("^'", ""):gsub("'$", "")
            _retro_vars_cache[key] = val
        end
    end
    f:close()
end

function Variable.get_var(key, default)
    _parse_vars_file()
    local val = _retro_vars_cache[key]
    if val == nil then
        return default or ""
    end
    return val
end

function Variable.set_var(key, value)
    if not key or key == "" then return false end
    _retro_vars_cache[key] = value
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
    return true
end

function Variable.reload_vars()
    _vars_file_mtime = 0
    _parse_vars_file()
end

return Variable
