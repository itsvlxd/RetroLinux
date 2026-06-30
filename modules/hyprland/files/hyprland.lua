--------------------
---   Hyprland   ---
--------------------
--
-- See https://wiki.hypr.land/Configuring/ for more

local ok
ok, colors = pcall(dofile, os.getenv("HOME") .. "/.config/retro/themes/hyprland-colors.lua")

for k, v in pairs(colors) do
	if type(v) == "string" then
		local alpha, rgb = v:match("^0x(%x%x)(%x%x%x%x%x%x)$")
		if alpha then
			colors[k] = "rgba(" .. rgb .. alpha .. ")"
		end
	end
end

ok, vars = pcall(dofile, os.getenv("HOME") .. "/.config/retro/themes/variables.lua")

if not ok then
	os.execute("bash " .. os.getenv("HOME") .. "/.config/hypr/scripts/refresh_hyprland.sh 2>/dev/null")

	ok, vars = pcall(dofile, os.getenv("HOME") .. "/.config/retro/themes/variables.lua")
end

if not ok then
	vars = {
		retro_opacity = 1.0,
		retro_inactive_opacity = 0.8,
		retro_border_size = 2,
		retro_rounding = 10,
		retro_rounding_power = 2,
		retro_gap_in = 5,
		retro_gap_out = 20,
		retro_shadow = true,
		retro_shadow_range = 4,
		retro_shadow_render_power = 3,
		retro_blur = true,
		retro_blur_size = 3,
		retro_blur_passes = 3,
		retro_blur_vibrancy = 0.1696,
		retro_layout = "dwindle",
		retro_resize_on_border = true,
		retro_allow_tearing = false,
		retro_animations = true,
	}
end

pcall(dofile, os.getenv("HOME") .. "/.config/retro/windowrules.lua")

local retro_dir = os.getenv("RETRO_DIR") or "/opt/retrolinux"
local retro_config = os.getenv("HOME") .. "/.config/retro"
package.path = retro_config
	.. "/?.lua;"
	.. retro_dir
	.. "/lib/lua/?.lua;"
	.. retro_dir
	.. "/modules/hyprland/files/?.lua;"
	.. package.path

local ok, _ = pcall(dofile, retro_config .. "/input.lua")
if not ok then
	require("input")
end

hl.config({
	ecosystem = {
		no_donation_nag = true,
		no_update_news = true,
	},
})

require("programs")
require("env")
require("monitors")
require("autostart")
require("appearance")
require("windows")
require("permissions")

pcall(dofile, retro_dir .. "/modules/hyprland/files/keybinds.lua")
pcall(dofile, retro_config .. "/keybinds.lua")
pcall(dofile, retro_config .. "/settings.lua")
