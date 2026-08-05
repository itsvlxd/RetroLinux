local Variable = require("variable")

local Retro = {}

function Retro.fullscreen()
	local win = hl.get_active_window()
	if win then
		local class = win.class
		local pid = win.pid
		local fs = win.fullscreen
		if class and class:lower() == "kitty" then
			local shrink = Variable.get_var("KITTY_SHRINK_PADDING_FULLSCREEN", "true")
			local default_pd = Variable.get_var("KITTY_PADDING", "5")
			if shrink == "true" then
				local pd = (fs > 0) and default_pd or "1"
				os.execute(
					("kitty @ --to=unix:/tmp/kitty-%d set-spacing padding-top=%s padding-bottom=%s padding-left=%s padding-right=%s 2>/dev/null"):format(
						pid,
						pd,
						pd,
						pd,
						pd
					)
				)
			end
		end
	end
	hl.dispatch(hl.dsp.window.fullscreen())
end

function Retro.open_terminal()
	local opacity = Variable.get_var("RETRO_OPACITY", "1.0")
	local font = Variable.get_var("KITTY_FONT", "JetBrainsMono Nerd Font")
	local emoji = Variable.get_var("RETRO_FONT_EMOJI", "Apple Color Emoji")
	local size = Variable.get_var("KITTY_FONT_SIZE", "9.5")
	local padding = Variable.get_var("KITTY_PADDING", "5")

	local home = os.getenv("HOME") or "/tmp"
	local theme = home .. "/.config/retro/themes/kitty-colors.conf"
	local cwd = os.getenv("RETRO_CWD") or home

	os.execute(
		'setsid kitty --directory "'
			.. cwd
			.. '"'
			.. ' -o "background_opacity='
			.. opacity
			.. '"'
			.. ' -o "font_family='
			.. font
			.. '"'
			.. ' -o "font_size='
			.. size
			.. '"'
			.. ' -o "window_padding_width='
			.. padding
			.. '"'
			.. ' -o "symbol_map U+E000-U+F8FF,U+F0000-U+FFFFF '
			.. font
			.. '"'
			.. ' -o "symbol_map U+1F300-U+1F9FF,U+1F600-U+1F64F '
			.. emoji
			.. '"'
			.. ' -o "include='
			.. theme
			.. '"'
			.. ' -o "allow_remote_control=yes"'
			.. ' -o "listen_on=unix:/tmp/kitty-{kitty_pid}"'
			.. " >/dev/null 2>&1 &"
	)
end

function Retro.open_filemanager()
	local fm = Variable.get_var("RETRO_FILEMANAGER_CMD", "nemo")
	local retro_dir = os.getenv("RETRO_DIR") or "/opt/retrolinux"
	local script = retro_dir .. "/modules/" .. fm .. "/files/scripts/open_" .. fm .. ".sh"
	local f = io.open(script, "r")
	if f then
		f:close()
		os.execute("setsid bash '" .. script .. "' >/dev/null 2>&1 &")
	else
		os.execute("setsid " .. fm .. " >/dev/null 2>&1 &")
	end
end

function Retro.open_editor()
	local editor = Variable.get_var("RETRO_EDITOR_CMD", "nvim")
	local retro_dir = os.getenv("RETRO_DIR") or "/opt/retrolinux"
	local script = retro_dir .. "/modules/" .. editor .. "/files/scripts/open_" .. editor .. ".sh"
	local f = io.open(script, "r")
	if f then
		f:close()
		os.execute("setsid bash '" .. script .. "' >/dev/null 2>&1 &")
	else
		os.execute("setsid " .. editor .. " >/dev/null 2>&1 &")
	end
end

function Retro.shell_run(name)
	os.execute("setsid retro shell run " .. name .. " >/dev/null 2>&1 &")
end

function Retro.open_launcher()
	Retro.shell_run("launcher")
end
function Retro.open_clipboard()
	Retro.shell_run("clipboard")
end
function Retro.open_emoji()
	Retro.shell_run("emoji")
end
function Retro.open_tmux()
	Retro.shell_run("tmux")
end
function Retro.open_notes()
	Retro.shell_run("notes")
end
function Retro.open_wallpapers()
	Retro.shell_run("wallpapers")
end
function Retro.open_screenshot()
	Retro.shell_run("screenshot")
end
function Retro.open_screenrecord()
	Retro.shell_run("screenrecord")
end
function Retro.open_lockscreen()
	Retro.shell_run("lockscreen")
end
function Retro.open_overview()
	Retro.shell_run("overview")
end
function Retro.open_powermenu()
	Retro.shell_run("powermenu")
end
function Retro.open_tools()
	Retro.shell_run("tools")
end
function Retro.open_assistant()
	Retro.shell_run("assistant")
end
function Retro.open_config()
	Retro.shell_run("config")
end
function Retro.open_dashboard()
	Retro.shell_run("dashboard")
end
function Retro.media_play_pause()
	Retro.shell_run("media-play-pause")
end
function Retro.media_next()
	Retro.shell_run("media-next")
end
function Retro.media_prev()
	Retro.shell_run("media-prev")
end

return Retro
