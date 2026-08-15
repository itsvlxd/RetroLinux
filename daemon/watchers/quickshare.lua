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
		local retro_dir = get_retro_dir()
		local core = retro_dir .. "/scripts/quickshare_core.sh"

		Watcher.log("quickshare", "Quick Share watcher started", "info")

		while true do
			if Watcher.run_cmd("test -f '" .. core .. "' && echo ok"):find("ok", 1, true)
				and Watcher.get_var("QUICKSHARE_ENABLED", "false") == "true" then
				local status = Watcher.run_cmd("bash '" .. core .. "' --status")
				local state = status:match("^([^|]*)")
				if state ~= "running" then
					Watcher.log("quickshare", "receiver not running, starting", "warn")
					local result = Watcher.run_cmd("bash '" .. core .. "' --start &")
					if result:find("^OK", 1) or result == "" then
						Watcher.log("quickshare", "receiver started", "info")
					else
						Watcher.log("quickshare", "start failed: " .. result, "error")
					end
				end
			end
			coroutine.yield()
		end
	end,
}
