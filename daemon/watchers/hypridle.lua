return {
	name = "hypridle",
	interval = 10,
	enabled = function()
		local Watcher = require("watcher")
		return Watcher.run_cmd("which hypridle >/dev/null 2>&1 && echo yes") == "yes"
	end,
	start = function(engine)
		local Watcher = require("watcher")

		local consecutive_failures = 0
		local max_failures = 3
		local last_restart_time = 0
		local restart_cooldown = 30
		local spawn_log = "/tmp/retro_logs/hypridle_spawn.log"

		local function hypridle_running()
			return Watcher.run_cmd("pgrep -x hypridle >/dev/null 2>&1 && echo yes") == "yes"
		end

		local function hypridle_bin()
			return Watcher.run_cmd("which hypridle")
		end

		local function hypridle_config()
			local xdg = os.getenv("XDG_CONFIG_HOME")
			local base = (xdg and xdg ~= "") and xdg or ((os.getenv("HOME") or "/tmp") .. "/.config")
			return base .. "/retro/hypridle.conf"
		end

		local function spawn_hypridle()
			local bin = hypridle_bin()
			if bin == "" then
				Watcher.log("hypridle", "spawn failed: hypridle binary not found in PATH", "error")
				return false
			end

			local config = hypridle_config()
			if Watcher.run_cmd("test -f '" .. config .. "' && echo yes") ~= "yes" then
				Watcher.log("hypridle", "spawn failed: config not found at " .. config, "error")
				return false
			end

			Watcher.log("hypridle", "spawning hypridle (bin: " .. bin .. ", config: " .. config .. ")", "info")
			Watcher.run_cmd("nohup " .. bin .. " -c '" .. config .. "' > " .. spawn_log .. " 2>&1 &")
			return true
		end

		while true do
			local caffeine = Watcher.get_var("HYPRIDLE_CAFFEINE_ENABLE", "false")
			local enabled = Watcher.get_var("HYPRIDLE_ENABLE", "true")

			if caffeine == "true" then
				-- Caffeine active: kill hypridle and never revive it.
				if hypridle_running() then
					Watcher.log("hypridle", "Caffeine active — stopping hypridle", "info")
					Watcher.run_cmd("pkill -x hypridle")
					Watcher.run_cmd("systemctl --user stop hypridle 2>/dev/null")
				end
				consecutive_failures = 0
			elseif enabled ~= "true" then
				-- Idle disabled at runtime: kill if running, don't revive.
				if hypridle_running() then
					Watcher.log("hypridle", "HYPRIDLE_ENABLE is off — stopping hypridle", "info")
					Watcher.run_cmd("pkill -x hypridle")
					Watcher.run_cmd("systemctl --user stop hypridle 2>/dev/null")
				end
				consecutive_failures = 0
			else
				if not hypridle_running() then
					-- Process not seen: log it.
					consecutive_failures = consecutive_failures + 1
					Watcher.log("hypridle", "hypridle process not found (failure " .. consecutive_failures .. "/" .. max_failures .. ")", "warn")

					-- Only start hypridle when a compositor (hyprland) is NOT running.
					local hyprland_running = Watcher.run_cmd("pgrep -x hyprland >/dev/null 2>&1 && echo yes") == "yes"
					if hyprland_running then
						consecutive_failures = 0
					elseif consecutive_failures >= max_failures then
						local now = Watcher.time()
						if now - last_restart_time >= restart_cooldown then
							Watcher.log("hypridle", "Attempting to spawn hypridle", "info")

							if spawn_hypridle() then
								Watcher.sleep(3)

								if hypridle_running() then
									Watcher.log("hypridle", "hypridle spawned successfully", "info")
									engine:emit("on_hypridle_restarted")
									consecutive_failures = 0
								else
									local err = Watcher.run_cmd("cat " .. spawn_log .. " 2>/dev/null | tail -3")
									if err ~= "" then
										Watcher.log("hypridle", "hypridle spawn failed — process not running. spawn log: " .. err, "error")
									else
										Watcher.log("hypridle", "hypridle spawn failed — process not running (no output captured)", "error")
									end
								end
							end

							last_restart_time = now
						else
							Watcher.log("hypridle", "Restart cooldown active, skipping (" .. (restart_cooldown - (now - last_restart_time)) .. "s remaining)", "info")
						end
					end
				else
					consecutive_failures = 0
				end
			end

			coroutine.yield()
		end
	end,
}
