return {
	name = "portal",
	interval = 30,
	enabled = function()
		local Watcher = require("watcher")
		return Watcher.run_cmd("pgrep -f 'xdg-desktop-portal' >/dev/null 2>&1 && echo yes") == "yes"
	end,
	start = function(engine)
		local Watcher = require("watcher")
		local XDG = require("xdg")
		local log = function(msg) Watcher.log("portal", msg) end

		local consecutive_failures = 0
		local max_failures = 3
		local last_restart_time = 0
		local restart_cooldown = 60
		local backend_warning_shown = {}

		while true do
			Watcher.reload_vars()

			local portal_pid = Watcher.run_cmd("pgrep -x 'xdg-desktop-portal' | head -1")
			local backend = XDG.get_portal_backend()
			local backend_pkg = "xdg-desktop-portal-" .. backend

			local portal_alive = false
			if portal_pid ~= "" then
				portal_alive = Watcher.run_cmd("kill -0 " .. portal_pid .. " 2>/dev/null && echo yes") == "yes"
			end

			if not portal_alive then
				consecutive_failures = consecutive_failures + 1
				log("Portal daemon not responding (failure " .. consecutive_failures .. "/" .. max_failures .. ")")

				if consecutive_failures >= max_failures then
					local now = Watcher.time()
					if now - last_restart_time >= restart_cooldown then
						log("Attempting portal restart with env injection")
						local injected = XDG.inject_portal_env()
						Watcher.sleep(3)

						local new_pid = Watcher.run_cmd("pgrep -x 'xdg-desktop-portal' | head -1")
						if new_pid ~= "" then
							log("Portal daemon restarted successfully (PID: " .. new_pid .. ", backend: " .. backend .. ")")
							consecutive_failures = 0
							last_restart_time = Watcher.time()
						else
							log("Portal restart failed, will retry on next cycle")
							last_restart_time = Watcher.time()
						end
					else
						log("Restart cooldown active, skipping (" .. (restart_cooldown - (now - last_restart_time)) .. "s remaining)")
					end
				end
			else
				local backend_pid = Watcher.run_cmd("pgrep -x 'xdg-desktop-portal-" .. backend .. "' | head -1")
				local backend_alive = false
				if backend_pid ~= "" then
					backend_alive = Watcher.run_cmd("kill -0 " .. backend_pid .. " 2>/dev/null && echo yes") == "yes"
				end

				if not backend_alive then
					local pkg_installed = Watcher.run_cmd("pacman -Qq '" .. backend_pkg .. "' >/dev/null 2>&1 && echo yes") == "yes"
					if pkg_installed then
						log("Backend '" .. backend .. "' died, restarting")
						Watcher.run_cmd("systemctl --user restart --wait xdg-desktop-portal-" .. backend .. " 2>/dev/null")
						Watcher.sleep(2)
						local new_backend_pid = Watcher.run_cmd("pgrep -x 'xdg-desktop-portal-" .. backend .. "' | head -1")
						if new_backend_pid ~= "" then
							log("Backend '" .. backend .. "' restarted (PID: " .. new_backend_pid .. ")")
						else
							log("Backend '" .. backend .. "' restart failed")
						end
					else
						if not backend_warning_shown[backend] then
							log("Backend '" .. backend .. "' package not installed (" .. backend_pkg .. "), skipping")
							backend_warning_shown[backend] = true
						end
					end
				end

				consecutive_failures = 0
			end

			coroutine.yield()
		end
	end
}
