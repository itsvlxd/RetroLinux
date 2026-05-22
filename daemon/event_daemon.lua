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

local action = arg[1]

if not action then
	Log.error("No command specified. Use: retro daemon --help")
	os.exit(1)
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
else
	Log.error("Unknown command: " .. action .. ". Use: retro daemon --help")
	os.exit(1)
end
