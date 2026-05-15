local Watcher = require("watcher")

local Engine = {}
Engine.__index = Engine

function Engine.new(daemon_dir)
    local self = setmetatable({}, Engine)
    self.daemon_dir = daemon_dir
    self.events_dir = daemon_dir .. "/events"
    self.watchers_dir = daemon_dir .. "/watchers"
    self.running = false
    self.watchers = {}
    self.watcher_next_run = {}
    self.watcher_co = {}
    self.event_count = 0
    self.crash_count = 0
    self.max_crashes = 3
    return self
end

function Engine:load_watchers()
    local watcher_files = {}
    local ls = io.popen("ls -1 '" .. self.watchers_dir .. "'/*.lua 2>/dev/null")
    if ls then
        for file in ls:lines() do
            table.insert(watcher_files, file)
        end
        ls:close()
    end

    for _, file in ipairs(watcher_files) do
        local name = file:match("([^/]+)%.lua$")
        if name then
            local ok, mod = pcall(require, name)
            if ok and mod and type(mod.start) == "function" then
                local enabled = true
                if mod.enabled and type(mod.enabled) == "function" then
                    enabled = mod.enabled()
                end
                if enabled then
                    table.insert(self.watchers, {
                        name = name,
                        module = mod,
                        interval = mod.interval or 15,
                        crashes = 0,
                        disabled = false,
                    })
                end
            else
                local log_path = "/tmp/retro_engine.log"
                local f = io.open(log_path, "a")
                if f then
                    f:write(string.format("[%s] Failed to load %s: %s\n", os.date("%H:%M:%S"), name, tostring(mod)))
                    f:close()
                end
            end
        end
    end
end

function Engine:emit(event_name, ...)
    self.event_count = self.event_count + 1
    local args = {...}
    local arg_str = ""
    for i, arg in ipairs(args) do
        local escaped = tostring(arg):gsub("'", "'\\''")
        arg_str = arg_str .. " '" .. escaped .. "'"
    end

    local ls = io.popen("ls -1 '" .. self.events_dir .. "'/*.sh 2>/dev/null")
    if not ls then return end

    local hooks = {}
    for file in ls:lines() do
        table.insert(hooks, file)
    end
    ls:close()

    for _, hook in ipairs(hooks) do
        local simple_cmd = string.format(
            "(source '%s' 2>/dev/null; declare -f '%s' >/dev/null 2>&1 && '%s'%s) &",
            hook,
            event_name,
            event_name,
            arg_str
        )
        os.execute(simple_cmd)
    end
end

function Engine:emit_sync(event_name, ...)
    local args = {...}
    local arg_str = ""
    for i, arg in ipairs(args) do
        local escaped = tostring(arg):gsub("'", "'\\''")
        arg_str = arg_str .. " '" .. escaped .. "'"
    end

    local ls = io.popen("ls -1 '" .. self.events_dir .. "'/*.sh 2>/dev/null")
    if not ls then return end

    local hooks = {}
    for file in ls:lines() do
        table.insert(hooks, file)
    end
    ls:close()

    for _, hook in ipairs(hooks) do
        local cmd = string.format(
            "source '%s' 2>/dev/null; declare -f '%s' >/dev/null 2>&1 && '%s'%s",
            hook,
            event_name,
            event_name,
            arg_str
        )
        os.execute("bash -c '" .. cmd .. "'")
    end
end

function Engine:run_watcher(watcher_info)
    local log_path = "/tmp/retro_watcher_" .. watcher_info.name .. ".log"
    local lf = io.open(log_path, "a")
    if lf then
        lf:write(string.format("[%s] Watcher started (interval: %d)\n", os.date("%H:%M:%S"), watcher_info.interval))
        lf:close()
    end

    local mod = watcher_info.module
    local ok, err = pcall(function()
        mod.start(self)
    end)
    if not ok then
        watcher_info.crashes = watcher_info.crashes + 1
        self.crash_count = self.crash_count + 1
        local f = io.open(log_path, "a")
        if f then
            f:write(string.format("[%s] CRASH #%d: %s\n", os.date("%H:%M:%S"), watcher_info.crashes, tostring(err)))
            f:close()
        end
        if watcher_info.crashes >= self.max_crashes then
            local f = io.open(log_path, "a")
            if f then
                f:write(string.format("[%s] DISABLED after %d crashes\n", os.date("%H:%M:%S"), watcher_info.crashes))
                f:close()
            end
            watcher_info.disabled = true
        end
    end
end

function Engine:run_loop()
    self:load_watchers()

    if #self.watchers == 0 then
        return
    end

    self:emit("on_event_loop_start")
    self.running = true

    local stop_file = "/tmp/retro_event_daemon_stop"
    local now = os.time()

    for i, w in ipairs(self.watchers) do
        self.watcher_co[i] = coroutine.create(function()
            self:run_watcher(w)
        end)
        self.watcher_next_run[i] = now
    end

    while self.running do
        local f = io.open(stop_file, "r")
        if f then
            f:close()
            os.remove(stop_file)
            break
        end

        now = os.time()
        local min_wait = 1

        for i, co in ipairs(self.watcher_co) do
            local w = self.watchers[i]
            if w.disabled then goto continue end

            if now >= self.watcher_next_run[i] then
                local status = coroutine.status(co)
                if status == "suspended" or status == "normal" then
                    local ok = coroutine.resume(co)
                    if not ok then
                        w.crashes = w.crashes + 1
                        if w.crashes >= self.max_crashes then
                            w.disabled = true
                        end
                    end
                    self.watcher_next_run[i] = now + w.interval
                end
            end

            local wait = self.watcher_next_run[i] - now
            if wait > 0 and wait < min_wait then
                min_wait = wait
            end
            ::continue::
        end

        os.execute("sleep " .. min_wait)
    end
end

function Engine:trigger(event_name, ...)
    self:emit(event_name, ...)
end

function Engine:get_status()
    local pid_file = "/tmp/retro_event_daemon.pid"
    local f = io.open(pid_file, "r")
    if not f then
        return { running = false }
    end
    local pid = f:read("*l")
    f:close()

    local result = Watcher.run_cmd("kill -0 " .. pid .. " 2>/dev/null && echo alive")
    if result == "alive" then
        return { running = true, pid = pid }
    else
        os.remove(pid_file)
        return { running = false }
    end
end

function Engine:stop()
    local status = self:get_status()
    if status.running then
        os.execute("touch /tmp/retro_event_daemon_stop")
        for i = 1, 50 do
            os.execute("sleep 0.1")
            local s = self:get_status()
            if not s.running then return true end
        end
        os.execute("kill -9 " .. status.pid .. " 2>/dev/null")
        os.remove("/tmp/retro_event_daemon.pid")
        return true
    end
    return false
end

function Engine:list_watchers()
    self:load_watchers()
    local result = {}
    for _, w in ipairs(self.watchers) do
        table.insert(result, {
            name = w.name,
            interval = w.interval,
        })
    end
    return result
end

return Engine
