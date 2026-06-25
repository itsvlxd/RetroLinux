local Watcher = require("watcher")

local busctl_cmd = "env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy"
local sensor_err = "/tmp/retro_logs/monitor-sensor.err"
local ms_pid = nil

return {
	name = "rotation",
	interval = 2,
	enabled = function()
		local raw = Watcher.run_cmd(busctl_cmd .. " HasAccelerometer" .. " 2>/dev/null")
		return raw:match("true") ~= nil
	end,
	start = function(engine)
		os.execute("pkill -x monitor-sensor 2>/dev/null || true")
		os.execute("> " .. sensor_err)
		os.execute("monitor-sensor >/dev/null 2>" .. sensor_err .. " &")
		os.execute("rm -f /tmp/retro_sensor.out")
		ms_pid = nil
		Watcher.log("rotation", "Watcher started", "info")
	end,
	tick = function(engine)
		local locked = Watcher.get_var("ROTATION_LOCK", "false")
		if locked == "true" then return end

		if not ms_pid or not Watcher.run_cmd("kill -0 " .. ms_pid .. " 2>/dev/null && echo alive"):match("alive") then
			local pids = Watcher.run_cmd("pgrep -x monitor-sensor 2>/dev/null | head -1")
			if pids == "" then
				Watcher.log("rotation", "monitor-sensor dead, restarting", "warn")
				os.execute("pkill -x monitor-sensor 2>/dev/null || true")
				os.execute("monitor-sensor >/dev/null 2>" .. sensor_err .. " &")
				ms_pid = nil
			else
				ms_pid = pids
			end
		end

		local raw = Watcher.run_cmd(busctl_cmd .. " AccelerometerOrientation" .. " 2>/dev/null")
		local orient = raw:match('"([%w-]+)')
		if not orient then
			local err = Watcher.read_sys(sensor_err):match("%S.*") or "none"
			Watcher.log("rotation", "D-Bus read failed (raw=" .. raw .. ", err=" .. err .. ")", "warn")
			return
		end

		local t
		if orient == "normal" then
			t = 0
		elseif orient == "bottom-up" then
			t = 2
		elseif orient == "left-up" then
			t = 1
		elseif orient == "right-up" then
			t = 3
		else
			Watcher.log("rotation", "Unknown orientation: " .. orient, "warn")
			return
		end

		local retro_dir = os.getenv("RETRO_DIR") or "/opt/retrolinux"
		local core = retro_dir .. "/scripts/display_core.sh"

		local monitor = Watcher.run_cmd("bash '" .. core .. "' --detect-internal-monitor 2>/dev/null")
		if monitor == "" then return end

		local cur = Watcher.run_cmd("bash '" .. core .. "' --get-transform '" .. monitor .. "' 2>/dev/null")
		if cur == tostring(t) then return end

		Watcher.run_cmd("bash '" .. core .. "' --set-transform '" .. monitor .. "' " .. t .. " 2>/dev/null")
		Watcher.log("rotation", "Applied transform " .. t .. " for " .. monitor .. " (" .. orient .. ")", "info")
		engine:emit("on_display_rotation", monitor, tostring(t), orient)
	end,
}
