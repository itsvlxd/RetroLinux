local Log = require("log")
local Variable = require("variable")

local Fs = {}

function Fs.get_json(file, key, default)
    local f = io.open(file, "r")
    if not f then return default or "" end

    local content = f:read("*all")
    f:close()

    local val = content:match('"' .. key .. '"%s*:%s*"([^"]*)"')
        or content:match('"' .. key .. '"%s*:%s*(%S+)')

    if val then
        val = val:gsub("^~", os.getenv("HOME") or "")
        return val
    end

    return default or ""
end

function Fs.read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

function Fs.write_file(path, content)
    local dir = path:match("(.+)/")
    if dir then os.execute("mkdir -p '" .. dir .. "'") end

    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

function Fs.sanitize(target)
    local f = io.open(target, "r")
    if not f then return end

    local content = f:read("*all")
    f:close()

    local home = os.getenv("HOME")
    if home then
        content = content:gsub("/home/[^/]+", "/home/" .. home:match("[^/]+$"))
    end

    Fs.write_file(target, content)
end

return Fs
