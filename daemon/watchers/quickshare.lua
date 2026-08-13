local function get_retro_dir()
	local dir = os.getenv("RETRO_DIR")
	if dir and dir ~= "" then
		return dir
	end
	return os.getenv("HOME") .. "/.local/share/retro"
end

return {
	name = "quickshare",
	interval = 30,
	enabled = function()
		local Watcher = require("watcher")
		local result = Watcher.run_cmd("python3 --version 2>/dev/null")
		return result:find("Python", 1, true) ~= nil
	end,
	start = function(engine)
		local Watcher = require("watcher")
		Watcher.log("quickshare", "Quick Share watcher started", "info")
	end,
	tick = function(engine)
		local Watcher = require("watcher")
		local retro_dir = get_retro_dir()
		local core = retro_dir .. "/scripts/quickshare_core.sh"

		if not Watcher.run_cmd("test -f '" .. core .. "' && echo ok"):find("ok", 1, true) then
			return
		end

		local status = Watcher.run_cmd("bash '" .. core .. "' --status")
		-- status format: state|dir|autostart|pid|autoaccept
		local state, _, autostart = status:match("^([^|]*)|([^|]*)|([^|]*)")

		if autostart == "true" and state ~= "running" then
			Watcher.log("quickshare", "receiver not running (autostart enabled), restarting", "warn")
			local result = Watcher.run_cmd("bash '" .. core .. "' --start &")
			if result:find("^OK", 1) or result == "" then
				Watcher.log("quickshare", "receiver restarted", "info")
			else
				Watcher.log("quickshare", "restart failed: " .. result, "error")
			end
		end
	end,
}
