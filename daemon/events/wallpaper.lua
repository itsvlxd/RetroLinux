local Wallpaper = require("wallpaper")

local Events = {}

function Events.on_slideshow_tick()
    Wallpaper.slideshow_next()
end

return Events
