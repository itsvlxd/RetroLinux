return {
	name = "timers",
	interval = 60,
	enabled = function()
		return true
	end,
	start = function(engine)
		local Watcher = require("watcher")

		local last_pkg_check = 0
		local last_retro_check = 0

		local pkg_min = tonumber(Watcher.get_var("RETRO_PKG_UPDATE_MIN", "20")) or 20
		local pkg_interval = pkg_min * 60

		local retro_min = tonumber(Watcher.get_var("RETRO_UPDATE_CHECK_MIN", "30")) or 30
		local retro_interval = retro_min * 60

		local retro_dir = os.getenv("RETRO_DIR")

		Watcher.log(
			"timers",
			string.format("Package check every %dm, Retro check every %dm", pkg_min, retro_min),
			"info"
		)

		while true do
			local now = Watcher.time()

			if now - last_pkg_check >= pkg_interval then
				local helper = Watcher.get_var("PKG_HELPER", "yay")
				local pac_raw = Watcher.run_cmd("checkupdates 2>/dev/null")
				local pac_count = 0
				for _ in pac_raw:gmatch("[^\n]+") do
					pac_count = pac_count + 1
				end

				local aur_raw = Watcher.run_cmd(helper .. " -Qu 2>/dev/null")
				local aur_count = 0
				for _ in aur_raw:gmatch("[^\n]+") do
					aur_count = aur_count + 1
				end

				local total = pac_count + aur_count

			local raw_thresh = Watcher.get_var("RETRO_PKG_UPDATE_THRESH", "20")
			local thresh = tonumber((raw_thresh:gsub("%D", ""))) or 20

				if total > 0 and total >= thresh then
					local sample_names = {}
					local seen = {}
					for line in pac_raw:gmatch("[^\n]+") do
						local name = line:match("^(%S+)")
						if name and not seen[name] and #sample_names < 3 then
							seen[name] = true
							table.insert(sample_names, name)
						end
					end
					for line in aur_raw:gmatch("[^\n]+") do
						local name = line:match("^(%S+)")
						if name and not seen[name] and #sample_names < 3 then
							seen[name] = true
							table.insert(sample_names, name)
						end
					end
					local sample = table.concat(sample_names, ", ")
					Watcher.log(
						"timers",
						string.format(
							"%d updates available (pac=%d, aur=%d, thresh=%d): %s",
							total,
							pac_count,
							aur_count,
							thresh,
							sample
						),
						"info"
					)
					engine:emit("on_pkg_updates_available", tostring(total), sample)
				else
					Watcher.log(
						"timers",
						string.format(
							"Package check: %d updates (pac=%d, aur=%d, thresh=%d) - below threshold",
							total,
							pac_count,
							aur_count,
							thresh
						),
						"info"
					)
				end

				last_pkg_check = now
			end

			if retro_dir and now - last_retro_check >= retro_interval then
				local git_check = Watcher.run_cmd("test -d '" .. retro_dir .. "/.git' && echo yes")
				if git_check == "yes" then
					Watcher.run_cmd("git -C '" .. retro_dir .. "' fetch origin 2>/dev/null")
					local branch =
						Watcher.run_cmd("git -C '" .. retro_dir .. "' rev-parse --abbrev-ref HEAD 2>/dev/null")
					local behind_str = Watcher.run_cmd(
						"git -C '" .. retro_dir .. "' rev-list --count HEAD..origin/" .. branch .. " 2>/dev/null"
					)
					local behind = tonumber(behind_str) or 0

					if behind > 0 then
						Watcher.log(
							"timers",
							string.format("%d Retro commits behind (branch: %s)", behind, branch),
							"info"
						)
						engine:emit("on_retro_update_available", tostring(behind))
					else
						Watcher.log("timers", "Retro is up to date (branch: " .. branch .. ")", "info")
					end
				end

				last_retro_check = now
			end

			coroutine.yield()
		end
	end,
}
