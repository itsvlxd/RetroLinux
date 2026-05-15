local Watcher = require("watcher")
local Power = require("power")
local Battery = require("battery")
local Wallpaper = require("wallpaper")

local Events = {}

function Events.on_power_disconnect(cap)
    if Watcher.get_var("BAT_SAVER_ON_PWR_DIS") == "true" and Watcher.get_var("BAT_SAVER_ACTIVE") ~= "true" then
        Power.set_profile("saver")
    end

    if Watcher.get_var("WALL_STATIC_ON_BAT") == "true" then
        Wallpaper.restore_wallpaper(true)
    end

    Watcher.set_var("BAT_DISCONNECT_TIME", tostring(os.time()))
end

function Events.on_power_connect(cap)
    Power.restore_previous()

    if Watcher.get_var("BAT_SAVER_ON_PWR_DIS") == "true" and Watcher.get_var("BAT_SAVER_ACTIVE") == "true" then
        Battery.set_saver("false")
    end

    if Watcher.get_var("WALL_STATIC_ON_BAT") == "true" then
        Wallpaper.restore_wallpaper(true)
    end

    local start = Watcher.get_var("BAT_DISCONNECT_TIME")
    if start and start ~= "" and start ~= "null" then
        local total_sec = os.time() - tonumber(start)
        Battery.log_event("duration", total_sec)
        Battery.log_event("cycle", 1)
        Watcher.set_var("BAT_DISCONNECT_TIME", "null")
    end
end

function Events.on_power_profile_changed(current_pwr)
    local saver_active = Watcher.get_var("BAT_SAVER_ACTIVE")
    if current_pwr ~= "saver" and saver_active == "true" then
        Battery.set_saver("false")
        Battery.sync_hyprland_power("false")
    elseif current_pwr == "saver" and saver_active ~= "true" then
        Battery.set_saver("true")
        Battery.sync_hyprland_power("true")
    end

    Wallpaper.restore_wallpaper(true)
end

return Events
