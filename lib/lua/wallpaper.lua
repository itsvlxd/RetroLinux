local Watcher = require("watcher")

local Wallpaper = {}

function Wallpaper._core()
	return os.getenv("RETRO_DIR") .. "/scripts/wallpaper_core.sh"
end

function Wallpaper.find_video_version(path)
	if not path or path == "" or path == "null" then return nil end
	if path:match("%.mp4$") or path:match("%.mkv$") or path:match("%.webm$") then
		return path
	end
	local base = path:match("^(.+)%.%w+$")
	if not base then return nil end
	for _, ext in ipairs({ "mp4", "mkv", "webm" }) do
		local video = base .. "." .. ext
		if Watcher.run_cmd("test -f '" .. video .. "' && echo yes") == "yes" then
			return video
		end
	end
	return nil
end

function Wallpaper.start(input_path, quick)
	local quick_flag = quick and "true" or "false"
	Watcher.run_cmd("bash '" .. Wallpaper._core() .. "' --set '" .. input_path .. "' '" .. quick_flag .. "' &")
	return true
end

function Wallpaper.pause_wallpaper()
	Watcher.run_cmd("bash '" .. Wallpaper._core() .. "' --pause &")
	Watcher.set_var("WALL_PAUSED", "true")
	return true
end

function Wallpaper.stop_wallpaper()
	Watcher.run_cmd("pkill -x mpvpaper 2>/dev/null")
	return true
end

function Wallpaper.should_pause()
	local res = Watcher.run_cmd("bash '" .. Wallpaper._core() .. "' --should-pause")
	return res == "should_pause=true"
end

function Wallpaper.slideshow_next()
	Watcher.run_cmd("bash '" .. Wallpaper._core() .. "' --slideshow-next &")
	return true
end

return Wallpaper
