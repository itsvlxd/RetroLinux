local Watcher = require("watcher")

local Wallpaper = {}

local WALL_DIR = nil
local FRAME_CACHE = nil
local REPO_WALLS = nil

local function init_paths()
	if WALL_DIR then return end
	local retro_config = os.getenv("RETRO_CONFIG") or (os.getenv("HOME") .. "/.config/retro")
	local retro_dir = os.getenv("RETRO_DIR")
	WALL_DIR = retro_config .. "/wallpapers"
	FRAME_CACHE = retro_config .. "/wallpaper_frames"
	REPO_WALLS = retro_dir .. "/wallpapers"
	Watcher.run_cmd("mkdir -p '" .. FRAME_CACHE .. "' '" .. WALL_DIR .. "'")
end

function Wallpaper.get_theme_dir()
	init_paths()
	local theme = Watcher.get_var("RETRO_THEME")
	if theme == "" or theme == "null" then theme = "retro" end
	local target = WALL_DIR .. "/" .. theme
	if Watcher.run_cmd("test -d '" .. target .. "' && echo yes") == "yes" then
		return target
	end
	return WALL_DIR
end

function Wallpaper.resolve_path(input)
	init_paths()
	local theme_dir = Wallpaper.get_theme_dir()
	if Watcher.run_cmd("test -f '" .. input .. "' && echo yes") == "yes" then
		return input
	elseif Watcher.run_cmd("test -f '" .. theme_dir .. "/" .. input .. "' && echo yes") == "yes" then
		return theme_dir .. "/" .. input
	elseif Watcher.run_cmd("test -f '" .. WALL_DIR .. "/" .. input .. "' && echo yes") == "yes" then
		return WALL_DIR .. "/" .. input
	end
	return nil
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

function Wallpaper.is_static()
	local is_saver = Watcher.get_var("BAT_SAVER_ACTIVE", "false")
	local static_on_saver = Watcher.get_var("WALL_STATIC_ON_SAVER", "true")
	local force_static = Watcher.get_var("WALL_STATIC_FORCED", "false")
	local static_on_bat = Watcher.get_var("WALL_STATIC_ON_BAT", "false")

	if force_static == "true" then return true end
	if is_saver == "true" then return static_on_saver == "true" end
	if Watcher.run_cmd("grep -q 'Discharging' /sys/class/power_supply/BAT*/status 2>/dev/null && echo yes") == "yes" and static_on_bat == "true" then
		return true
	end
	return false
end

function Wallpaper.ensure_awww()
	if Watcher.run_cmd("pgrep -x 'awww-daemon' >/dev/null 2>&1 && echo yes") ~= "yes" then
		Watcher.run_cmd("nohup awww-daemon >/dev/null 2>&1 &")
		local delay = 0.1
		for i = 1, 30 do
			Watcher.run_cmd("sleep " .. delay)
			if Watcher.run_cmd("awww query >/dev/null 2>&1 && echo yes") == "yes" then break end
			delay = delay * 1.5
		end
		return true
	end
	return false
end

function Wallpaper.start(input_path, quick)
	init_paths()
	local wall_path = Wallpaper.resolve_path(input_path)
	if not wall_path then return false end
	local quick_flag = quick and "true" or "false"
	Watcher.run_cmd("bash '" .. os.getenv("RETRO_DIR") .. "/scripts/wallpaper_core.sh' --set '" .. wall_path .. "' '" .. quick_flag .. "' &")
	return true
end

function Wallpaper.restore_wallpaper(quick)
	local quick_flag = quick and "true" or "false"
	Watcher.run_cmd("bash '" .. os.getenv("RETRO_DIR") .. "/scripts/wallpaper_core.sh' --restore '" .. quick_flag .. "' &")
	return true
end

function Wallpaper.pause_wallpaper()
	Watcher.run_cmd("bash '" .. os.getenv("RETRO_DIR") .. "/scripts/wallpaper_core.sh' --pause &")
	Watcher.set_var("WALL_PAUSED", "true")
	return true
end

function Wallpaper.resume_wallpaper()
	Watcher.set_var("WALL_PAUSED", "false")
	Watcher.run_cmd("bash '" .. os.getenv("RETRO_DIR") .. "/scripts/wallpaper_core.sh' --resume &")
	return true
end

function Wallpaper.slideshow_next()
	Watcher.run_cmd("bash '" .. os.getenv("RETRO_DIR") .. "/scripts/wallpaper_core.sh' --slideshow-next &")
	return true
end

function Wallpaper.static_wallpaper(action)
	local act = action or "toggle"
	Watcher.run_cmd("bash '" .. os.getenv("RETRO_DIR") .. "/scripts/wallpaper_core.sh' --static '" .. act .. "' &")
	return true
end

function Wallpaper.should_pause()
	local on_fullscreen = Watcher.get_var("WALL_STATIC_ON_FULLSCREEN", "true")
	local pause_procs = Watcher.get_var("WALL_PAUSE_PROCS", "")

	if on_fullscreen == "true" then
		local clients = Watcher.run_cmd("hyprctl clients -j 2>/dev/null")
		if clients ~= "" then
			local fs_count = tonumber(Watcher.run_cmd("echo '" .. clients .. "' | jq '[.[] | select(.fullscreen > 0 and .initialClass != \"mpvpaper\" and .class != \"mpvpaper\")] | length'")) or 0
			if fs_count > 0 then return true end
		end
	end

	if pause_procs ~= "" and pause_procs ~= "null" then
		for p in pause_procs:gmatch("([^|]+)") do
			local trimmed = p:gsub("%s+", "")
			if trimmed ~= "" then
				if Watcher.run_cmd("pgrep -x '" .. trimmed .. "' >/dev/null 2>&1 && echo yes") == "yes" then
					return true
				end
			end
		end
	end

	return false
end

return Wallpaper
