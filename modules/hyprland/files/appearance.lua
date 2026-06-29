-------------------------
---   LOOK AND FEEL   ---
-------------------------
--
-- Refer to https://wiki.hypr.land/Configuring/Variables/

-- https://wiki.hypr.land/Configuring/Variables/#general
hl.config({
	general = {
		gaps_in = vars.retro_gap_in,
		gaps_out = vars.retro_gap_out,
		border_size = vars.retro_border_size,

		-- https://wiki.hypr.land/Configuring/Variables/#variable-types for info about colors
		col = {
			active_border = { colors = { colors.source_color, colors.secondary }, angle = 45 },
			inactive_border = colors.surface_variant,
		},

		-- Set to true enable resizing windows by clicking and dragging on borders and gaps
		resize_on_border = vars.retro_resize_on_border,

		-- Please see https://wiki.hypr.land/Configuring/Tearing/ before you turn this on
		allow_tearing = vars.retro_allow_tearing,

		extend_border_grab_area = vars.retro_extend_border_grab_area,
		hover_icon_on_border = vars.retro_hover_icon_on_border,

		snap = {
			enabled = vars.retro_snap_enabled,
			window_gap = vars.retro_snap_window_gap,
			monitor_gap = vars.retro_snap_monitor_gap,
			border_overlap = vars.retro_snap_border_overlap,
			respect_gaps = vars.retro_snap_respect_gaps,
		},

		layout = vars.retro_layout,
	},
	-- https://wiki.hypr.land/Configuring/Variables/#decoration
	decoration = {
		rounding = vars.retro_rounding,
		rounding_power = vars.retro_rounding_power,

		-- Change transparency of focused and unfocused windows
		active_opacity = vars.retro_opacity,
		inactive_opacity = vars.retro_inactive_opacity,
		fullscreen_opacity = vars.retro_fullscreen_opacity,

		dim_inactive = vars.retro_dim_inactive,
		dim_strength = vars.retro_dim_strength,
		dim_around = vars.retro_dim_around,
		dim_special = vars.retro_dim_special,
		dim_modal = vars.retro_dim_modal,

		border_part_of_window = vars.retro_border_part_of_window,

		shadow = {
			enabled = vars.retro_shadow,
			range = vars.retro_shadow_range,
			render_power = vars.retro_shadow_render_power,
			sharp = vars.retro_shadow_sharp,
			offset = vars.retro_shadow_offset,
			scale = vars.retro_shadow_scale,
			color = vars.retro_shadow_color,
		},

		-- https://wiki.hypr.land/Configuring/Variables/#blur
		blur = {
			enabled = vars.retro_blur,
			size = vars.retro_blur_size,
			passes = vars.retro_blur_passes,
			ignore_opacity = vars.retro_blur_ignore_opacity,
			new_optimizations = vars.retro_blur_new_optimizations,
			xray = vars.retro_blur_xray,
			noise = vars.retro_blur_noise,
			contrast = vars.retro_blur_contrast,
			brightness = vars.retro_blur_brightness,
			vibrancy = vars.retro_blur_vibrancy,
			vibrancy_darkness = vars.retro_blur_vibrancy_darkness,
			special = vars.retro_blur_special,
			popups = vars.retro_blur_popups,
			popups_ignorealpha = vars.retro_blur_popups_ignorealpha,
			input_methods = vars.retro_blur_input_methods,
			input_methods_ignorealpha = vars.retro_blur_input_methods_ignorealpha,
		},

		-- https://wiki.hypr.land/Configuring/Variables/#decoration-glow
		glow = {
			enabled = vars.retro_glow_enabled,
			range = vars.retro_glow_range,
			render_power = vars.retro_glow_render_power,
			color = colors.primary,
		},
	},

	-- https://wiki.hypr.land/Configuring/Variables/#animations
	animations = {
		enabled = vars.retro_animations,
	},
})

-- Default curves, see https://wiki.hypr.land/Configuring/Animations/#curves
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

-- Default animations, see https://wiki.hypr.land/Configuring/Animations/
hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })

-- Ref https://wiki.hypr.land/Configuring/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.config({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.config({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

hl.window_rule({
	name = "kitty-windows-style",
	match = { class = "kitty" },
	opacity = vars.retro_kitty_active_opacity .. " 0.8",
})

hl.layer_rule({
	name = "rofi-layer-style",
	match = { namespace = "^(rofi)$" },
	blur = true,
	ignore_alpha = 0.5,
	animation = "popin 80%",
})

-- See https://wiki.hypr.land/Configuring/Dwindle-Layout/ for more
-- pseudotile = true -- Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
-- preserve_split = true -- You probably want this
hl.config({ dwindle = { preserve_split = true } })

-- See https://wiki.hypr.land/Configuring/Master-Layout/ for more
hl.config({ master = { new_status = "master" } })

-- https://wiki.hypr.land/Configuring/Variables/#misc
hl.config({
	misc = {
		force_default_wallpaper = 0, -- Set to 0 or 1 to disable the anime mascot wallpapers
		disable_hyprland_logo = true, -- If true disables the random hyprland logo / anime girl background. :(
	},
})

hl.config({ xwayland = { force_zero_scaling = true } })
