local Watcher = require("watcher")

local Engine = {}
Engine.__index = Engine

function Engine.new(daemon_dir)
	local self = setmetatable({}, Engine)
	self.daemon_dir = daemon_dir
	self.events_dir = daemon_dir .. "/events"
	self.watchers_dir = daemon_dir .. "/watchers"
	self.watchers = {}
	self.event_handlers = {}
	self.event_count = 0
	self.max_crashes = 3
	return self
end

function Engine:load_watchers()
	local ls = io.popen("ls -1 '" .. self.watchers_dir .. "'/*.lua 2>/dev/null")
	if not ls then return end
	local files = {}
	for f in ls:lines() do table.insert(files, f) end
	ls:close()

	for _, file in ipairs(files) do
		local name = file:match("([^/]+)%.lua$")
		if not name then goto continue end

		local df = io.open("/tmp/retro_logs/watcher_" .. name .. ".disabled", "r")
		if df then df:close(); goto continue end

		local ok, mod = pcall(dofile, file)
		if not ok or not mod then goto continue end

		local enabled = true
		if type(mod.enabled) == "function" then
			enabled = mod.enabled()
		end
		if not enabled then goto continue end

		table.insert(self.watchers, {
			name = name,
			interval = mod.interval or 15,
			crashes = 0,
			disabled = false,
			next_run = 0,
			module = mod,
			co = nil,
		})
		::continue::
	end
end

function Engine:load_event_handlers()
	self.event_handlers = {}
	local ls = io.popen("ls -1 '" .. self.events_dir .. "'/*.lua 2>/dev/null")
	if not ls then return end
	local files = {}
	for f in ls:lines() do table.insert(files, f) end
	ls:close()

	for _, file in ipairs(files) do
		local ok, mod = pcall(dofile, file)
		if ok and type(mod) == "table" then
			for event, handler in pairs(mod) do
				if type(handler) == "function" then
					if not self.event_handlers[event] then
						self.event_handlers[event] = {}
					end
					table.insert(self.event_handlers[event], {
						module = file:match("([^/]+)%.lua$"),
						handler = handler,
					})
				end
			end
		end
	end
end

function Engine:emit(event_name, ...)
	self.event_count = self.event_count + 1
	local handlers = self.event_handlers[event_name]
	if not handlers then return end
	local args = {...}
	for _, h in ipairs(handlers) do
		local ok, err = pcall(function()
			h.handler(table.unpack(args))
		end)
		if not ok then
			Watcher.log("engine", event_name .. ": " .. tostring(err), "error")
		end
	end
end

function Engine:run_loop()
	self:load_watchers()
	self:load_event_handlers()
	if #self.watchers == 0 then return end

	self:emit("on_event_loop_start")

	for _, w in ipairs(self.watchers) do
		if w.module.tick then
			local ok, err = pcall(w.module.start, self)
			if not ok then
				Watcher.log(w.name, "init error: " .. tostring(err), "error")
				w.disabled = true
			end
		else
			w.co = coroutine.create(function()
				local ok, err = pcall(w.module.start, self)
				if not ok then
					Watcher.log(w.name, "coroutine error: " .. tostring(err), "error")
				end
			end)
		end
	end

	local stop_file = "/tmp/retro_event_daemon_stop"

	while true do
		local f = io.open(stop_file, "r")
		if f then f:close(); os.remove(stop_file); break end

		local now = os.time()

		for _, w in ipairs(self.watchers) do
			if w.disabled then goto continue end
			if now < w.next_run then goto continue end

			if w.module.tick then
				local ok, err = pcall(w.module.tick, self)
				if not ok then
					w.crashes = w.crashes + 1
					Watcher.log(w.name, "tick error: " .. tostring(err), "error")
					if w.crashes >= self.max_crashes then
						w.disabled = true
						Watcher.log(w.name, "DISABLED after " .. w.crashes .. " errors", "error")
					end
				end
			else
				local status = coroutine.status(w.co)
				if status == "suspended" then
					local ok, err = coroutine.resume(w.co)
					if not ok then
						w.crashes = w.crashes + 1
						if w.crashes >= self.max_crashes then
							w.disabled = true
						end
					end
				elseif status == "dead" then
					Watcher.log(w.name, "coroutine dead, restarting", "warn")
					w.co = coroutine.create(function()
						local ok, err = pcall(w.module.start, self)
						if not ok then
							Watcher.log(w.name, "coroutine restart error: " .. tostring(err), "error")
						end
					end)
				end
			end

			w.next_run = now + w.interval
			::continue::
		end

		os.execute("sleep 1")
	end
end

function Engine:get_status()
	local pid_file = "/tmp/retro_event_daemon.pid"
	local f = io.open(pid_file, "r")
	if not f then return { running = false } end
	local pid = f:read("*l"); f:close()
	local result = Watcher.run_cmd("kill -0 " .. pid .. " 2>/dev/null && echo alive")
	if result == "alive" then
		return { running = true, pid = pid }
	end
	os.remove(pid_file)
	return { running = false }
end

function Engine:stop()
	local status = self:get_status()
	if status.running then
		os.execute("touch /tmp/retro_event_daemon_stop")
		for i = 1, 50 do
			os.execute("sleep 0.1")
			if not self:get_status().running then return true end
		end
		os.execute("kill -9 " .. status.pid .. " 2>/dev/null")
		os.execute("pkill -f 'event_daemon.lua loop' 2>/dev/null")
		os.remove("/tmp/retro_event_daemon.pid")
		return true
	end
	return false
end

function Engine:list_watchers()
	self:load_watchers()
	local result = {}
	for _, w in ipairs(self.watchers) do
		table.insert(result, { name = w.name, interval = w.interval })
	end
	return result
end

return Engine
