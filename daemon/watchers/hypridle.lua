return {
	name = "hypridle",
	interval = 10,
	enabled = function()
		local Watcher = require("watcher")
		return Watcher.run_cmd("command -v hypridle >/dev/null 2>&1 && echo yes") == "yes"
	end,
	start = function(engine)
		local Watcher = require("watcher")

		local consecutive_failures = 0
		local max_failures = 3
		local last_restart_time = 0
		local restart_cooldown = 30

		while true do
			local caffeine = Watcher.get_var("HYPRIDLE_CAFFEINE_ENABLE", "false")
			local enabled = Watcher.get_var("HYPRIDLE_ENABLE", "true")

			if caffeine == "true" then
				-- Caffeine active: kill hypridle and never revive it.
				if Watcher.run_cmd("pgrep -x hypridle >/dev/null 2>&1 && echo yes") == "yes" then
					Watcher.log("hypridle", "Caffeine active — stopping hypridle", "info")
					Watcher.run_cmd("pkill -x hypridle")
					Watcher.run_cmd("systemctl --user stop hypridle 2>/dev/null")
				end
				consecutive_failures = 0
			elseif enabled ~= "true" then
				-- Idle disabled at runtime: kill if running, don't revive.
				if Watcher.run_cmd("pgrep -x hypridle >/dev/null 2>&1 && echo yes") == "yes" then
					Watcher.log("hypridle", "HYPRIDLE_ENABLE is off — stopping hypridle", "info")
					Watcher.run_cmd("pkill -x hypridle")
					Watcher.run_cmd("systemctl --user stop hypridle 2>/dev/null")
				end
				consecutive_failures = 0
			else
				local idle_running = Watcher.run_cmd("pgrep -x hypridle >/dev/null 2>&1 && echo yes") == "yes"

				if idle_running then
					consecutive_failures = 0
				else
					-- Only start hypridle when a compositor (hyprland) is NOT running.
					local hyprland_running = Watcher.run_cmd("pgrep -x hyprland >/dev/null 2>&1 && echo yes") == "yes"
					if hyprland_running then
						consecutive_failures = 0
					else
						consecutive_failures = consecutive_failures + 1
						Watcher.log("hypridle", "hypridle not running (failure " .. consecutive_failures .. "/" .. max_failures .. ")", "warn")

						if consecutive_failures >= max_failures then
							local now = Watcher.time()
							if now - last_restart_time >= restart_cooldown then
								Watcher.log("hypridle", "Attempting hypridle start via 'retro shell idle'", "info")
								Watcher.run_cmd("retro shell idle")
								Watcher.sleep(3)

								local ok = Watcher.run_cmd("pgrep -x hypridle >/dev/null 2>&1 && echo yes") == "yes"
								if ok then
									Watcher.log("hypridle", "hypridle started successfully", "info")
									engine:emit("on_hypridle_restarted")
									consecutive_failures = 0
									last_restart_time = Watcher.time()
								else
									Watcher.log("hypridle", "hypridle start failed, will retry on next cycle", "warn")
									last_restart_time = Watcher.time()
								end
							else
								Watcher.log("hypridle", "Restart cooldown active, skipping (" .. (restart_cooldown - (now - last_restart_time)) .. "s remaining)", "info")
							end
						end
					end
				end
			end

			coroutine.yield()
		end
	end,
}
