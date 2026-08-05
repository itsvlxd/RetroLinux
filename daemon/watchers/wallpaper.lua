return {
	name = "wallpaper",
	interval = 1,
	enabled = function()
		return true
	end,
	start = function(engine)
		local Watcher = require("watcher")
		local Wallpaper = require("wallpaper")

		while true do
			local force_static = Watcher.get_var("WALL_STATIC_FORCED", "false")
			local saver_active = Watcher.get_var("BAT_SAVER_ACTIVE", "false")
			local static_on_saver = Watcher.get_var("WALL_STATIC_ON_SAVER", "true")
			local static_on_bat = Watcher.get_var("WALL_STATIC_ON_BAT", "false")
			local wall_paused = Watcher.get_var("WALL_PAUSED", "false")
			local on_battery = Watcher.run_cmd("grep -q 'Discharging' /sys/class/power_supply/BAT*/status 2>/dev/null && echo yes")

			local should_be_static = force_static == "true"
				or (saver_active == "true" and static_on_saver == "true")
				or (on_battery == "yes" and static_on_bat == "true")

			local blocked = Wallpaper.should_pause()

			local current = Watcher.get_var("WALL_CURRENT", "")
			local video = Wallpaper.find_video_version(current)
			local should_run = video ~= nil
				and not should_be_static
				and not blocked
				and wall_paused ~= "true"

			local mpvpaper_running = Watcher.run_cmd("pgrep -x mpvpaper >/dev/null 2>&1 && echo yes") == "yes"

			local debounce = 3
			local ts = tonumber((Watcher.run_cmd("cat /tmp/retro_wallpaper_switch_ts 2>/dev/null"):gsub("%s+$", ""))) or 0
			local switching = ts > 0 and (os.time() - ts) < debounce

			if should_run and not mpvpaper_running and not switching then
				Watcher.log("wallpaper", "mpvpaper not running, launching " .. video, "info")
				Wallpaper.start(video, true)
			elseif not should_run and mpvpaper_running and not switching then
				Watcher.log("wallpaper", "Stopping mpvpaper (static/paused/blocked)", "info")
				Wallpaper.stop_wallpaper()
			end

			coroutine.yield()
		end
	end,
}
