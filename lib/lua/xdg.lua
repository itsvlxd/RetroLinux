local Watcher = require("watcher")

local XDG = {}

local user_dirs_file = nil
local mimeapps_file = nil
local portal_conf = nil
local retro_dir = nil
local retro_config = nil

local search_paths = {
	"/usr/share/applications",
}

local function init_paths()
	if user_dirs_file then return end
	local home = os.getenv("HOME") or "/tmp"
	retro_config = os.getenv("RETRO_CONFIG") or (home .. "/.config/retro")
	retro_dir = os.getenv("RETRO_DIR")
	user_dirs_file = home .. "/.config/user-dirs.dirs"
	mimeapps_file = home .. "/.config/mimeapps.list"
	portal_conf = retro_config .. "/portal.conf"
	table.insert(search_paths, home .. "/.local/share/applications")
	local flatpak_path = "/var/lib/flatpak/exports/share/applications"
	if Watcher.run_cmd("test -d '" .. flatpak_path .. "' && echo yes") == "yes" then
		table.insert(search_paths, flatpak_path)
	end
end

local function read_file_lines(path)
	local lines = {}
	local f = io.open(path, "r")
	if not f then return lines end
	for line in f:lines() do
		table.insert(lines, line)
	end
	f:close()
	return lines
end

local function write_file(path, content)
	local dir = path:match("(.+)/")
	if dir then Watcher.run_cmd("mkdir -p '" .. dir .. "'") end
	local f = io.open(path, "w")
	if not f then return false end
	f:write(content)
	f:close()
	return true
end

local function expand_home(path)
	if path:sub(1, 1) == "$" then
		local var = path:match("^%$([A-Za-z_]+)")
		if var == "HOME" then
			return os.getenv("HOME") .. path:sub(6)
		end
	end
	if path:sub(1, 1) == "~" then
		return os.getenv("HOME") .. path:sub(2)
	end
	return path
end

function XDG.get_dir(name)
	init_paths()
	local var_name = "XDG_" .. name:upper() .. "_DIR"
	local cached = Watcher.get_var(var_name)
	if cached ~= "" and cached ~= "null" then return cached end

	local lines = read_file_lines(user_dirs_file)
	for _, line in ipairs(lines) do
		local key, val = line:match('^XDG_' .. name:upper() .. '_DIR="(.*)"')
		if key then
			local expanded = expand_home(val)
			Watcher.set_var(var_name, expanded)
			return expanded
		end
	end

	local defaults = {
		DESKTOP = "$HOME/Desktop",
		DOWNLOAD = "$HOME/Downloads",
		DOCUMENTS = "$HOME/Documents",
		MUSIC = "$HOME/Music",
		PICTURES = "$HOME/Pictures",
		VIDEOS = "$HOME/Videos",
		TEMPLATES = "$HOME/Templates",
		PUBLICSHARE = "$HOME/Public",
	}
	local d = defaults[name:upper()]
	if d then return expand_home(d) end
	return nil
end

function XDG.set_dir(name, path)
	local var_name = "XDG_" .. name:upper() .. "_DIR"
	local expanded = expand_home(path)
	Watcher.run_cmd("mkdir -p '" .. expanded .. "'")

	local lines = read_file_lines(user_dirs_file)
	local found = false
	local out = {}
	for _, line in ipairs(lines) do
		if line:match('^XDG_' .. name:upper() .. '_DIR=') then
			table.insert(out, 'XDG_' .. name:upper() .. '_DIR="' .. path .. '"')
			found = true
		else
			table.insert(out, line)
		end
	end
	if not found then
		table.insert(out, 'XDG_' .. name:upper() .. '_DIR="' .. path .. '"')
	end

	local content = table.concat(out, "\n") .. "\n"
	write_file(user_dirs_file, content)
	Watcher.set_var(var_name, expanded)
	return expanded
end

function XDG.list_dirs()
	local dirs = { "DESKTOP", "DOWNLOAD", "DOCUMENTS", "MUSIC", "PICTURES", "VIDEOS", "TEMPLATES", "PUBLICSHARE" }
	local result = {}
	for _, d in ipairs(dirs) do
		local path = XDG.get_dir(d)
		local exists = Watcher.run_cmd("test -d '" .. (path or "") .. "' && echo yes") == "yes"
		table.insert(result, { name = d, path = path or "", exists = exists })
	end
	return result
end

function XDG.get_default(mime)
	init_paths()
	local lines = read_file_lines(mimeapps_file)
	for _, line in ipairs(lines) do
		local m, app = line:match("^" .. mime .. "=(.+)$")
		if m then return app end
	end
	local fallback = Watcher.run_cmd("xdg-mime query default '" .. mime .. "' 2>/dev/null")
	if fallback ~= "" then return fallback end
	return nil
end

function XDG.list_defaults()
	init_paths()
	local lines = read_file_lines(mimeapps_file)
	local in_section = false
	local result = {}
	for _, line in ipairs(lines) do
		if line:match("^%[") then
			in_section = (line == "[Default Applications]")
		elseif in_section and line:match("=.+") and not line:match("^#") then
			local mime, desktop = line:match("^(.-)=(.+)$")
			if mime then
				local name = XDG.desktop_name(desktop)
				table.insert(result, { mime = mime, desktop = desktop, name = name })
			end
		end
	end
	return result
end

function XDG.set_default(mime, desktop_file)
	if not XDG.validate_desktop(desktop_file) then
		return nil, "desktop_file_not_found"
	end

	local lines = read_file_lines(mimeapps_file)
	local has_section = false
	local in_section = false
	local out = {}
	for _, line in ipairs(lines) do
		if line:match("^%[") then
			if line == "[Default Applications]" then
				has_section = true
				in_section = true
			else
				in_section = false
			end
			table.insert(out, line)
		elseif in_section and line:match("^" .. mime .. "=") then
			table.insert(out, mime .. "=" .. desktop_file)
			in_section = false
		else
			table.insert(out, line)
		end
	end

	if not has_section then
		table.insert(out, "")
		table.insert(out, "[Default Applications]")
		table.insert(out, mime .. "=" .. desktop_file)
	elseif #out > 0 and out[#out]:match("^" .. mime .. "=") == nil then
		local insert_pos = 1
		for i, line in ipairs(out) do
			if line == "[Default Applications]" then
				insert_pos = i + 1
				break
			end
		end
		table.insert(out, insert_pos, mime .. "=" .. desktop_file)
	end

	write_file(mimeapps_file, table.concat(out, "\n") .. "\n")
	Watcher.run_cmd("update-desktop-database '" .. os.getenv("HOME") .. "/.local/share/applications' 2>/dev/null")
	Watcher.run_cmd("command -v flatpak >/dev/null 2>&1 && flatpak override --user --filesystem=xdg-config/mimeapps.list:ro 2>/dev/null")
	return mime .. "=" .. desktop_file
end

function XDG.reset_defaults()
	init_paths()
	local editor = Watcher.get_var("RETRO_EDITOR_CMD", "nvim")
	local fm = Watcher.get_var("RETRO_FILEMANAGER_CMD", "thunar")
	local terminal = Watcher.get_var("RETRO_TERMINAL_CMD", "kitty")

	local editor_desktop = editor .. ".desktop"

	local fm_map = {
		thunar = "thunar.desktop",
		nemo = "nemo.desktop",
		nautilus = "org.gnome.Nautilus.desktop",
		yazi = "yazi.desktop",
	}
	local fm_desktop = fm_map[fm] or "thunar.desktop"

	local browser_desktop = "firefox.desktop"
	local browsers = { "firefox", "chromium", "zen-browser-bin", "floorp", "thorium", "nyxt", "google-chrome" }
	for _, b in ipairs(browsers) do
		if XDG.validate_desktop(b .. ".desktop") then
			browser_desktop = b .. ".desktop"
			break
		end
	end

	local content = "[Default Applications]\n"
		.. "text/plain=" .. editor_desktop .. "\n"
		.. "inode/directory=" .. fm_desktop .. "\n"
		.. "application/x-directory=" .. fm_desktop .. "\n"
		.. "x-scheme-handler/file=" .. fm_desktop .. "\n"
		.. "x-scheme-handler/trash=" .. fm_desktop .. "\n"
		.. "x-scheme-handler/http=" .. browser_desktop .. "\n"
		.. "x-scheme-handler/https=" .. browser_desktop .. "\n"
		.. "x-scheme-handler/about=" .. browser_desktop .. "\n"
		.. "x-scheme-handler/terminal=" .. terminal .. ".desktop\n"

	write_file(mimeapps_file, content)
	Watcher.run_cmd("update-desktop-database '" .. os.getenv("HOME") .. "/.local/share/applications' 2>/dev/null")
	Watcher.run_cmd("command -v flatpak >/dev/null 2>&1 && flatpak override --user --filesystem=xdg-config/mimeapps.list:ro 2>/dev/null")
	return true
end

function XDG.find_handlers(mime)
	init_paths()
	local result = {}
	for _, sp in ipairs(search_paths) do
		if Watcher.run_cmd("test -d '" .. sp .. "' && echo yes") ~= "yes" then
			goto continue
		end
		local files = Watcher.run_cmd("find '" .. sp .. "' -maxdepth 1 -name '*.desktop' -type f 2>/dev/null")
		for fpath in files:gmatch("[^\n]+") do
			if fpath == "" then goto next_file end
			local content = read_file_lines(fpath)
			for _, line in ipairs(content) do
				if line:match("^MimeType=") and line:find(mime, 1, true) then
					local basename = fpath:match("([^/]+)$")
					if not XDG._is_hidden(content) then
						local name = XDG.desktop_name(basename)
						table.insert(result, { desktop = basename, name = name, path = fpath })
					end
					break
				end
			end
			::next_file::
		end
		::continue::
	end
	return result
end

function XDG._is_hidden(lines)
	for _, line in ipairs(lines) do
		if line == "Hidden=true" then return true end
	end
	return false
end

function XDG.validate_desktop(desktop_file)
	init_paths()
	if Watcher.run_cmd("test -f '" .. desktop_file .. "' && echo yes") == "yes" then
		return XDG._check_desktop_file(desktop_file)
	end
	for _, sp in ipairs(search_paths) do
		local full = sp .. "/" .. desktop_file
		if Watcher.run_cmd("test -f '" .. full .. "' && echo yes") == "yes" then
			return XDG._check_desktop_file(full)
		end
	end
	return false
end

function XDG._check_desktop_file(path)
	local lines = read_file_lines(path)
	local has_exec = false
	local hidden = false
	for _, line in ipairs(lines) do
		if line:match("^Exec=") then has_exec = true end
		if line == "Hidden=true" then hidden = true end
	end
	return has_exec and not hidden
end

function XDG.desktop_name(desktop_file)
	init_paths()
	local path = nil
	if Watcher.run_cmd("test -f '" .. desktop_file .. "' && echo yes") == "yes" then
		path = desktop_file
	else
		for _, sp in ipairs(search_paths) do
			local full = sp .. "/" .. desktop_file
			if Watcher.run_cmd("test -f '" .. full .. "' && echo yes") == "yes" then
				path = full
				break
			end
		end
	end
	if path then
		local lines = read_file_lines(path)
		for _, line in ipairs(lines) do
			local name = line:match("^Name=(.+)$")
			if name then return name end
		end
	end
	return desktop_file:gsub("%.desktop$", "")
end

function XDG.get_portal_backend()
	init_paths()
	local lines = read_file_lines(portal_conf)
	for _, line in ipairs(lines) do
		local val = line:match("^portal=(.+)$")
		if val then return val end
	end

	local hyprland_conf = "/etc/xdg/xdg-desktop-portal/hyprland-portals.conf"
	local hlines = read_file_lines(hyprland_conf)
	for _, line in ipairs(hlines) do
		local val = line:match("^default=(.+)$")
		if val then return val end
	end

	local env_conf = retro_config .. "/env.conf"
	local elines = read_file_lines(env_conf)
	for _, line in ipairs(elines) do
		if line:find("xdg%-desktop%-portal") then
			for _, backend in ipairs({ "hyprland", "gtk", "kde", "wlroots", "gnome" }) do
				if line:find(backend) then return backend end
			end
		end
	end

	local backends = {
		{ name = "hyprland", pkg = "xdg-desktop-portal-hyprland" },
		{ name = "kde", pkg = "xdg-desktop-portal-kde" },
		{ name = "gtk", pkg = "xdg-desktop-portal-gtk" },
		{ name = "wlroots", pkg = "xdg-desktop-portal-wlr" },
	}
	for _, b in ipairs(backends) do
		if Watcher.run_cmd("pacman -Qq '" .. b.pkg .. "' >/dev/null 2>&1 && echo yes") == "yes" then
			return b.name
		end
	end
	return "none"
end

function XDG.list_portals()
	local backends = {
		{ name = "hyprland", pkg = "xdg-desktop-portal-hyprland" },
		{ name = "gtk", pkg = "xdg-desktop-portal-gtk" },
		{ name = "kde", pkg = "xdg-desktop-portal-kde" },
		{ name = "wlroots", pkg = "xdg-desktop-portal-wlr" },
		{ name = "gnome", pkg = "xdg-desktop-portal-gnome" },
	}
	local result = {}
	for _, b in ipairs(backends) do
		local installed = Watcher.run_cmd("pacman -Qq '" .. b.pkg .. "' >/dev/null 2>&1 && echo yes") == "yes"
		local running = Watcher.run_cmd("pgrep -f 'xdg-desktop-portal-" .. b.name .. "' >/dev/null 2>&1 && echo yes") == "yes"
		table.insert(result, { name = b.name, installed = installed, running = running, pkg = b.pkg })
	end
	return result
end

function XDG.set_portal_backend(backend)
	local pkg = "xdg-desktop-portal-" .. backend
	if backend == "gnome" then pkg = "xdg-desktop-portal-gnome" end

	if Watcher.run_cmd("pacman -Qq '" .. pkg .. "' >/dev/null 2>&1 && echo yes") ~= "yes" then
		return nil, "package_not_installed", pkg
	end

	local content = "[portal]\nportal=" .. backend .. "\n"
	write_file(portal_conf, content)
	return backend
end

function XDG.inject_portal_env()
	Watcher.run_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP 2>/dev/null")
	local backend = XDG.get_portal_backend()
	if backend ~= "none" then
		Watcher.run_cmd("systemctl --user restart xdg-desktop-portal xdg-desktop-portal-" .. backend .. " 2>/dev/null")
	else
		Watcher.run_cmd("systemctl --user restart xdg-desktop-portal 2>/dev/null")
	end
	return backend
end

function XDG.ensure_dirs()
	Watcher.run_cmd("command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update 2>/dev/null")
	local dirs = { "DESKTOP", "DOWNLOAD", "DOCUMENTS", "MUSIC", "PICTURES", "VIDEOS", "TEMPLATES", "PUBLICSHARE" }
	local created = 0
	for _, d in ipairs(dirs) do
		local path = XDG.get_dir(d)
		if path and path ~= "" then
			if Watcher.run_cmd("test -d '" .. path .. "' && echo yes") ~= "yes" then
				Watcher.run_cmd("mkdir -p '" .. path .. "'")
				created = created + 1
			end
		end
	end
	return created
end

function XDG.bridge_flatpak()
	if Watcher.run_cmd("command -v flatpak >/dev/null 2>&1 && echo yes") ~= "yes" then
		return false
	end
	Watcher.run_cmd("flatpak override --user --filesystem=xdg-config/mimeapps.list:ro 2>/dev/null")
	return true
end

return XDG
