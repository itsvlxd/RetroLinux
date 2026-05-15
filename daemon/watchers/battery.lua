return {
    name = "battery",
    interval = 5,
    enabled = function()
        local Watcher = require("watcher")
        return Watcher.has_battery()
    end,
    start = function(engine)
        local Watcher = require("watcher")
        local log = function(msg) Watcher.log("battery", msg) end

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
            log("Using configured battery: " .. bat_path)
        end

        local last_notified_level = 0
        local saver_thresh = tonumber(Watcher.get_var("BAT_SAVER_THRESHOLD", "20")) or 20
        local low_thresh = tonumber(Watcher.get_var("BAT_NOTIFY_THRESHOLD", "20")) or 20
        local crit_thresh = tonumber(Watcher.get_var("BAT_NOTIFY_CRITICAL_THRESHOLD", "5")) or 5
        local tick_counter = 0

        log(string.format("Thresholds: saver=%d%%, low=%d%%, critical=%d%%", saver_thresh, low_thresh, crit_thresh))

        while true do
            if tick_counter % 10 == 0 then
                Watcher.reload_vars()
                saver_thresh = tonumber(Watcher.get_var("BAT_SAVER_THRESHOLD", "20")) or 20
                low_thresh = tonumber(Watcher.get_var("BAT_NOTIFY_THRESHOLD", "20")) or 20
                crit_thresh = tonumber(Watcher.get_var("BAT_NOTIFY_CRITICAL_THRESHOLD", "5")) or 5
            end

            local capacity_str = Watcher.read_sys(bat_path .. "/capacity")
            local capacity = tonumber(capacity_str) or 0
            local status = Watcher.read_sys(bat_path .. "/status"):lower()

            if tick_counter % 5 == 0 then
                log(string.format("Read: cap=%d%% status=%s raw_cap=%s", capacity, status, capacity_str))
            end

            local forced_saver = Watcher.get_var("BAT_SAVER_FORCED")
            local target_saver = "false"
            if forced_saver == "true" then
                target_saver = Watcher.get_var("BAT_SAVER_ACTIVE", "false")
            elseif status == "discharging" and capacity <= saver_thresh then
                target_saver = "true"
            end

            local current_saver = Watcher.get_var("BAT_SAVER_ACTIVE", "false")
            if target_saver ~= current_saver then
                Watcher.set_var("BAT_SAVER_ACTIVE", target_saver)
                if target_saver == "true" then
                    log("Battery saver ENABLED at " .. capacity .. "% (thresh: " .. saver_thresh .. "%)")
                    engine:emit("on_battery_saver_enabled")
                else
                    log("Battery saver DISABLED at " .. capacity .. "%")
                    engine:emit("on_battery_saver_disabled")
                end
            end

            if status == "discharging" then
                if capacity <= crit_thresh and capacity ~= last_notified_level then
                    log("CRITICAL battery: " .. capacity .. "% (thresh: " .. crit_thresh .. "%)")
                    engine:emit("on_battery_critical", tostring(capacity))
                    last_notified_level = capacity
                elseif capacity <= low_thresh and capacity ~= last_notified_level then
                    log("LOW battery: " .. capacity .. "% (thresh: " .. low_thresh .. "%)")
                    engine:emit("on_battery_low", tostring(capacity))
                    last_notified_level = capacity
                end
            end

            tick_counter = tick_counter + 1
            coroutine.yield()
        end
    end
}
