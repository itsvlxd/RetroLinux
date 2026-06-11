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
	}
end

if APPLY_COLORS_ONLY then
	hl.config({
		general = {
			gaps_in = vars.retro_gap_in,
			gaps_out = vars.retro_gap_out,
			border_size = vars.retro_border_size,
			col = {
				active_border = { colors = { colors.source_color, colors.primary_container }, angle = 45 },
				inactive_border = colors.surface_variant,
			},
		},
		decoration = {
			rounding = vars.retro_rounding,
			rounding_power = vars.retro_rounding_power,
			active_opacity = vars.retro_opacity,
			inactive_opacity = vars.retro_inactive_opacity,
			shadow = {
				enabled = vars.retro_shadow,
				range = vars.retro_shadow_range,
				render_power = vars.retro_shadow_render_power,
				color = colors.shadow,
			},
			blur = {
				enabled = vars.retro_blur,
				size = vars.retro_blur_size,
				passes = vars.retro_blur_passes,
				vibrancy = vars.retro_blur_vibrancy,
			},
		},
	})
	return
end

if APPLY_RULES_ONLY then
	pcall(dofile, os.getenv("HOME") .. "/.config/retro/windowrules.lua")
	return
end

pcall(dofile, os.getenv("HOME") .. "/.config/retro/windowrules.lua")

require("programs")
require("env")
require("monitors")
require("input")
require("keybinds")
require("autostart")
require("appearance")
require("windows")
require("permissions")
