local Watcher = require("watcher")

local Events = {}

function Events.on_display_rotation(monitor, transform, orient)
	local names = { "normal", "90°", "180°", "270°" }
	local tname = names[tonumber(transform) + 1] or orient
	Watcher.log("rotation", "Display " .. monitor .. " rotated to " .. tname, "info")
end

return Events
