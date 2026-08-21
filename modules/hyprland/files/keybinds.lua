-------------------
--- KEYBINDINGS ---
-------------------
--
-- See https://wiki.hypr.land/Configuring/Keywords/

local Retro = require("lib.retro")

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Binds/ for more
hl.bind(mainMod .. " + Q", Retro.open_terminal)
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", Retro.open_powermenu)
hl.bind(mainMod .. " + L", Retro.lock_screen)
hl.bind(mainMod .. " + E", Retro.open_filemanager)
hl.bind(mainMod .. " + SHIFT + E", Retro.open_emoji)
hl.bind(mainMod .. " + F", Retro.fullscreen)
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + V", Retro.open_clipboard)
hl.bind(mainMod .. " + T", Retro.open_tmux)
hl.bind(mainMod .. " + R", Retro.open_screenrecord)
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- dwindle
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle

hl.bind(mainMod .. " + space", Retro.open_launcher)
hl.bind(mainMod .. " + X", Retro.open_tools)
hl.bind(mainMod .. " + Tab", Retro.open_dashboard)
hl.bind(mainMod .. " + N", Retro.open_notes)
hl.bind(mainMod .. " + SHIFT + A", Retro.open_assistant)
hl.bind(mainMod .. " + comma", Retro.open_wallpapers)
hl.bind("ALT + Tab", Retro.open_overview)

hl.bind("F12", Retro.open_settings)
hl.bind("XF86Launch2", Retro.open_settings)

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "d" }))

-- Switch workspaces with mainMod + [0-9]
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", Retro.open_screenshot)

-- Cursor zoom with mainMod + arrow keys / scroll / keys
hl.bind(mainMod .. " + down", Retro.zoom_in)
hl.bind(mainMod .. " + up", Retro.zoom_out)
hl.bind(mainMod .. " + mouse_down", Retro.zoom_out)
hl.bind(mainMod .. " + mouse_up", Retro.zoom_in)
hl.bind(mainMod .. " + equal", Retro.zoom_in, { repeating = true })
hl.bind(mainMod .. " + minus", Retro.zoom_out, { repeating = true })
hl.bind(mainMod .. " + Z", Retro.zoom_toggle)

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", Retro.audio_up, { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", Retro.audio_down, { locked = true, repeating = true })
hl.bind("XF86AudioMute", Retro.audio_mute, { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", Retro.audio_mic_mute, { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", Retro.brightness_up, { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", Retro.brightness_down, { locked = true, repeating = true })

hl.bind("XF86AudioNext", Retro.media_next, { locked = true })
hl.bind("XF86AudioPause", Retro.media_play_pause, { locked = true })
hl.bind("XF86AudioPlay", Retro.media_play_pause, { locked = true })
hl.bind("XF86AudioPrev", Retro.media_prev, { locked = true })
