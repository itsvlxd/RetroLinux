return {
    name = "power",
    interval = 1,
    enabled = function()
        return true
    end,
    start = function(engine)
        local Watcher = require("watcher")
        local log = function(msg) Watcher.log("power", msg) end

        local bat_path = Watcher.get_var("BAT_PATH")
        if not bat_path or bat_path == "" or bat_path == "null" then
            bat_path = Watcher.run_cmd("ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1"):gsub("%s+$", "")
            if bat_path ~= "" then
                Watcher.set_var("BAT_PATH", bat_path)
                log("Auto-detected battery: " .. bat_path)
            else
                log("No battery found, disabling watcher")
                return
            end
        else
            log("Monitoring battery: " .. bat_path)
        end

        local last_on_battery = nil
        local last_pwr_profile = nil
        local function is_on_battery()
            local status = Watcher.read_sys(bat_path .. "/status")
            return status == "Discharging"
        end

        last_on_battery = is_on_battery()
        last_pwr_profile = Watcher.get_var("PWR_CURRENT", "")
        log("Initial state: " .. (last_on_battery and "on battery" or "on AC"))

        while true do
            local raw_status = Watcher.read_sys(bat_path .. "/status")
            local raw_cap = Watcher.read_sys(bat_path .. "/capacity")
            local current = is_on_battery()

            if current ~= last_on_battery then
                local cap = tonumber(raw_cap) or 0
                if current then
                    log(string.format("Power DISCONNECTED (raw_status='%s', battery: %d%%)", raw_status, cap))
                    engine:emit("on_power_disconnect", tostring(cap))
                else
                    log(string.format("Power CONNECTED (raw_status='%s', battery: %d%%)", raw_status, cap))
                    engine:emit("on_power_connect", tostring(cap))
                end
                last_on_battery = current
                Watcher.reload_vars()
                last_pwr_profile = Watcher.get_var("PWR_CURRENT", "")
            end

            local current_pwr = Watcher.get_var("PWR_CURRENT", "")
            if current_pwr ~= last_pwr_profile then
                log("Power profile changed: " .. current_pwr)
                engine:emit("on_power_profile_changed", current_pwr)
                last_pwr_profile = current_pwr
            end

            coroutine.yield()
        end
    end
}
