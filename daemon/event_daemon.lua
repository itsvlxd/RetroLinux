#!/usr/bin/env lua

local script_path = arg[0]
script_dir = script_path:match("(.+)/[^/]+$") or "."
local daemon_dir = script_dir

local retro_dir = os.getenv("RETRO_DIR") or (daemon_dir .. "/..")
local retro_config = os.getenv("RETRO_CONFIG") or (os.getenv("HOME") or "/tmp") .. "/.config/retro"

package.path = table.concat({
	retro_dir .. "/lib/lua/?.lua",
	retro_dir .. "/daemon/?.lua",
	retro_dir .. "/daemon/watchers/?.lua",
	package.path,
}, ";")

local Engine = require("engine")
local Watcher = require("watcher")
local Help = require("help")
local Colors = require("colors")
local Log = require("log")

local function show_help()
	Help.usage("retro event <command>")
	Help.commands("Commands")
	Help.cmd("start", "Start the event daemon in background")
	Help.cmd("stop", "Stop the running daemon")
	Help.cmd("status", "Check if daemon is running")
	Help.cmd("trigger [name]", "Manually fire an event")
	Help.cmd("list", "List available watchers")
	Help.cmd("log [name]", "View watcher logs")
	Help.cmd("log true/false", "Enable/disable all watcher logs")
	Help.cmd("log limit [number]", "Set log line cap for a watcher")
	Help.cmd("help", "Show this help")
	Help.examples()
	Help.example("retro event status", "Check if daemon is running")
	Help.example("retro event list", "Show all loaded watchers")
	Help.example("retro event log usb", "View USB watcher logs")
	Help.example("retro event log true", "Enable log generation")
	Help.example("retro event log false", "Disable log generation")
	Help.example("retro event log limit 200", "Set log cap to 200 lines")
	Help.spacer()
end

local action = arg[1]

if not action or action == "help" then
	show_help()
	os.exit(0)
end

local engine = Engine.new(daemon_dir)

if action == "loop" then
	os.remove("/tmp/retro_event_daemon_stop")
	engine:run_loop()
elseif action == "trigger" then
	local event_name = arg[2]
	if not event_name then
		Log.error("Event name required")
		os.exit(1)
	end

	local args = {}
	for i = 3, #arg do
		table.insert(args, arg[i])
	end

	Log.info("Firing event: " .. Colors.PINK .. event_name .. Colors.RESET)
	engine:emit(event_name, table.unpack(args))
elseif action == "status" then
	local status = engine:get_status()

	if status.running then
		Help.table_header("󱐋", "Event Daemon Status")
		Help.table_row("󱐋", "State:", "ACTIVE (PID: " .. status.pid .. ")", Colors.PINK, 14)
		local uptime_handle = io.popen("ps -o etime= -p " .. status.pid .. " 2>/dev/null | xargs")
		local uptime = uptime_handle:read("*l")

		uptime_handle:close()

		uptime = uptime and uptime:gsub("%s+", "")

		if uptime == "" then
			uptime = "N/A"
		end

		Help.table_row("󱎫", "Uptime:", uptime, Colors.PINK, 14)

		local log_enabled = Watcher.is_log_enabled()
		local log_color = log_enabled and Colors.SUCCESS or Colors.ERROR
		local log_text = log_enabled and "ENABLED" or "DISABLED"

		Help.table_row("󱐋", "Log Gen:", log_text, log_color, 14)
		Help.table_separator()
		Help.table_spacer()
		os.exit(0)
	else
		Help.table_header("󱐋", "Event Daemon Status")
		Help.table_row("󱐋", "State:", "INACTIVE", Colors.ERROR, 14)
		Help.table_row("󱎫", "Uptime:", "N/A", Colors.MUTE, 14)

		local log_enabled = Watcher.is_log_enabled()
		local log_color = log_enabled and Colors.SUCCESS or Colors.ERROR
		local log_text = log_enabled and "ENABLED" or "DISABLED"
		Help.table_row("󱐋", "Watcher Logs:", log_text, log_color, 14)

		Help.table_separator()
		Help.table_spacer()
		os.exit(1)
	end
elseif action == "stop" then
	Log.info("Stopping the event daemon...")
	if engine:stop() then
		Log.success("Event daemon stopped")
	else
		Log.warn("Event daemon was not running")
	end
elseif action == "list" then
	local watchers = engine:list_watchers()
	if #watchers == 0 then
		Help.table_simple("󰓅", "(No watchers found)", Colors.MUTE)
	else
		Help.table_header("󱐋", "Event Modules")
		for _, w in ipairs(watchers) do
			Help.table_list_single("󱐋", w.name .. " (interval: " .. w.interval .. "s)", Colors.GRAY)
		end
		Help.table_separator()
		Help.table_spacer()
	end
elseif action == "log" then
	local sub = arg[2]

	if sub == "true" then
		Watcher.set_log_enabled(true)
		Log.success("Watcher log generation ENABLED")
		os.exit(0)
	end

	if sub == "false" then
		Watcher.set_log_enabled(false)
		Log.warn("Watcher log generation DISABLED")
		os.exit(0)
	end

	if sub == "limit" then
		local name = arg[3]
		local cap = tonumber(arg[4])
		if not name then
			Log.error("Watcher name required")
			print("Usage: retro event log limit <name> <lines>")
			os.exit(1)
		end
		if not cap or cap < 10 then
			Log.error("Cap must be at least 10 lines")
			os.exit(1)
		end
		Watcher.set_log_cap(name, cap)
		Log.success("Log cap for '" .. name .. "' set to " .. cap .. " lines")
		os.exit(0)
	end

	if not sub then
		local logs = Watcher.list_logs()
		local log_enabled = Watcher.is_log_enabled()
		local log_color = log_enabled and Colors.SUCCESS or Colors.ERROR
		local log_text = log_enabled and "ENABLED" or "DISABLED"
		Help.table_header("󱐋", "Watcher Logs [" .. log_text .. "]")
		if #logs == 0 then
			Help.table_simple("󰓅", "(No watcher logs found)", Colors.MUTE)
		else
			for _, name in ipairs(logs) do
				local cap = Watcher.get_log_cap(name)
				local lines = Watcher.tail_log(name, 3)
				local last = lines[#lines] or "(empty)"
				Help.table_list_single("󱐋", name .. " [" .. cap .. " cap] - " .. last, Colors.GRAY)
			end
		end
		Help.table_separator()
		Help.table_spacer()
		os.exit(0)
	end

	local limit = tonumber(arg[3]) or 30
	local lines = Watcher.tail_log(sub, limit)

	if #lines == 0 then
		Log.warn("No logs found for watcher: " .. sub)
		os.exit(1)
	end

	Help.table_header("󱐋", sub .. " Logs (last " .. #lines .. " lines)")
	for _, line in ipairs(lines) do
		local ts, msg = line:match("^%[(.-)%] (.*)$")
		if ts and msg then
			local color = Colors.RESET
			if msg:find("ERROR") or msg:find("CRITICAL") or msg:find("fail") then
				color = Colors.ERROR
			elseif msg:find("WARN") then
				color = Colors.WARN
			elseif msg:find("connected") or msg:find("ENABLED") or msg:find("complete") then
				color = Colors.SUCCESS
			end
			io.write(string.format(" %s[%s]%s %s%s\n", Colors.GRAY, ts, Colors.RESET, color, msg))
		else
			io.write(string.format(" %s%s\n", Colors.RESET, line))
		end
	end
	Help.table_separator()
	Help.table_spacer()
else
	Log.error("Unknown command: " .. action)
	show_help()
	os.exit(1)
end
