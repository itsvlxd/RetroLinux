----------------
--- MONITORS ---
----------------
--
-- Run `retro display setup` to generate a custom config.

local ok = pcall(dofile, os.getenv("HOME") .. "/.config/retro/monitors.lua")

hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1,
})
