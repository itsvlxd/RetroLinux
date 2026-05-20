local Watcher = require("watcher")
local Power = require("power")

local Events = {}

function Events.on_battery_saver_enabled()
    local current_pwr = Watcher.get_var("PWR_CURRENT")
    if current_pwr ~= "saver" then
        Power.set_profile("saver")
    end
end

function Events.on_battery_saver_disabled()
    local current_pwr = Watcher.get_var("PWR_CURRENT")
    if current_pwr == "saver" then
        Power.toggle_profile()
    end
end

return Events
