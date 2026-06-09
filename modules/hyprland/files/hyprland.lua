--------------------
--- Hyprland ---
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
	vars = {
		retro_opacity = 1.0,
		retro_inactive_opacity = 0.8,
		retro_border_size = 2,
		retro_rounding = 10,
		retro_gap_in = 5,
		retro_gap_out = 20,
		retro_shadow = true,
		retro_blur = true,
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
			active_opacity = vars.retro_opacity,
			shadow = { enabled = vars.retro_shadow, color = colors.shadow },
			blur = { enabled = vars.retro_blur },
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
