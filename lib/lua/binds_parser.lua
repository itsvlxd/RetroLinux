local binds = {}

local function make_dispatch(path)
    return setmetatable({}, {
        __index = function(self, key)
            return make_dispatch(path .. "." .. key)
        end,
        __call = function(self, ...)
            local args = {...}
            local parts = {}
            for _, arg in ipairs(args) do
                if type(arg) == "table" then
                    local sorted_keys = {}
                    for k in pairs(arg) do
                        table.insert(sorted_keys, k)
                    end
                    table.sort(sorted_keys)
                    for _, k in ipairs(sorted_keys) do
                        table.insert(parts, tostring(k))
                        table.insert(parts, tostring(arg[k]))
                    end
                else
                    table.insert(parts, tostring(arg))
                end
            end
            local value = path
            if #parts > 0 then
                value = value .. "." .. table.concat(parts, ".")
            end
            return { _type = "dispatch", _value = value }
        end
    })
end

local retro_func_to_name = {}
local retro_mock = {}
for _, name in ipairs({"open_terminal", "open_filemanager", "open_editor", "fullscreen"}) do
    local f = function() end
    retro_mock[name] = f
    retro_func_to_name[f] = name
end

local hl = {
    bind = function(key, action, opts)
        local info = debug.getinfo(2, "l")
        local line = info and info.currentline or 0
        local action_type = "unknown"
        local action_value = ""

        if type(action) == "table" and action._type == "dispatch" then
            local prefix = "dsp.exec_cmd."
            if action._value:sub(1, #prefix) == prefix then
                action_type = "exec"
                action_value = action._value:sub(#prefix + 1)
            else
                action_type = "dispatch"
                action_value = action._value
            end
        elseif type(action) == "function" then
            action_type = "function"
            action_value = retro_func_to_name[action] or "anonymous"
        elseif type(action) == "table" then
            action_type = tostring(action)
            action_value = ""
        else
            action_type = type(action)
            action_value = tostring(action)
        end

        local flags = {}
        if opts then
            for k, v in pairs(opts) do
                if type(v) == "boolean" or type(v) == "string" or type(v) == "number" then
                    flags[k] = v
                end
            end
        end

        local flag_parts = {}
        for k, v in pairs(flags) do
            local v_str
            if type(v) == "boolean" then
                v_str = tostring(v)
            elseif type(v) == "string" then
                v_str = '"' .. v .. '"'
            else
                v_str = tostring(v)
            end
            table.insert(flag_parts, '"' .. k .. '":' .. v_str)
        end
        local flags_json = "{" .. table.concat(flag_parts, ",") .. "}"

        table.insert(binds, {
            line = line,
            key = key,
            action_type = action_type,
            action_value = action_value,
            flags = flags_json,
        })
    end,
    config = function() end,
    env = function() end,
    gesture = function() end,
    device = function() end,
    dispatch = function() end,
    dsp = make_dispatch("dsp"),
}

local _real_require = require
local mock_modules = {
    ["lib.retro"] = retro_mock,
    ["programs"] = {
        menu = "hyprlauncher",
        terminal = "kitty",
        filemanager = "nemo",
        browser = "zen-browser",
        editor = "nvim",
        launcher = "hyprlauncher",
    },
}

require = function(name)
    if mock_modules[name] then
        return mock_modules[name]
    end
    return _real_require(name)
end

local filepath = arg[1]
if not filepath or filepath == "" then
    io.stderr:write("Usage: lua binds_parser.lua <path/to/keybinds.lua>\n")
    os.exit(1)
end

local f = io.open(filepath, "r")
if not f then
    io.stderr:write("Error: cannot open " .. filepath .. "\n")
    os.exit(1)
end
local source = f:read("*a")
f:close()

local env = {
    hl = hl,
    require = require,
    print = print,
    os = os,
    io = io,
    string = string,
    table = table,
    math = math,
    pairs = pairs,
    ipairs = ipairs,
    tostring = tostring,
    tonumber = tonumber,
    type = type,
    select = select,
    unpack = table.unpack or unpack,
    pcall = pcall,
    xpcall = xpcall,
    error = error,
    debug = { getinfo = debug.getinfo, setupvalue = debug.setupvalue },
    _ENV = nil,
}

local chunk, err = load(source, "=" .. filepath, "t", env)
if not chunk then
    io.stderr:write("Error loading " .. filepath .. ": " .. tostring(err) .. "\n")
    os.exit(1)
end

local ok, err = pcall(chunk)
if not ok then
    io.stderr:write("Error executing " .. filepath .. ": " .. tostring(err) .. "\n")
    os.exit(1)
end

for _, b in ipairs(binds) do
    io.write(b.line .. "|" .. b.key .. "|" .. b.action_type .. "|" .. b.action_value .. "|" .. b.flags .. "\n")
end
