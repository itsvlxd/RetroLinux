return {
    name = "battery",
    interval = 5,
    enabled = function()
        local Watcher = require("watcher")
        return Watcher.has_battery()
    end,
    start = function(engine)
        local Watcher = require("watcher")

        local bat_path = Watcher.get_var("BAT_PATH")
        if not bat_path or bat_path == "" or bat_path == "null" then
            bat_path = Watcher.run_cmd("ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1"):gsub("%s+$", "")
            if bat_path ~= "" then
                Watcher.set_var("BAT_PATH", bat_path)
                Watcher.log("battery", "Auto-detected battery: " .. bat_path, "info")
            else
                Watcher.log("battery", "No battery found, disabling watcher", "warn")
                return
            end
        else
            Watcher.log("battery", "Using configured battery: " .. bat_path, "info")
        end

        local saver_thresh = tonumber(Watcher.get_var("BAT_SAVER_THRESHOLD", "20")) or 20
        local notify_thresh = tonumber(Watcher.get_var("BAT_NOTIFY_THRESHOLD", "30")) or 30
        local crit_thresh = tonumber(Watcher.get_var("BAT_NOTIFY_CRITICAL_THRESHOLD", "15")) or 15
        local tick_counter = 0

        local function build_notify_levels()
            local seen, out = {}, {}
            for _, level in ipairs({ notify_thresh, 20, 15, 10, 5 }) do
                if not seen[level] then
                    seen[level] = true
                    out[#out + 1] = level
                end
            end
            table.sort(out, function(a, b) return a > b end)
            return out
        end

        local notify_levels = build_notify_levels()
        local notified_levels = {}
        local cycle_start_capacity = nil

        Watcher.log("battery", string.format("Thresholds: saver=%d%%, notify=%d%%, critical=%d%%", saver_thresh, notify_thresh, crit_thresh), "info")

        while true do
            if tick_counter % 10 == 0 then
                saver_thresh = tonumber(Watcher.get_var("BAT_SAVER_THRESHOLD", "20")) or 20
                notify_thresh = tonumber(Watcher.get_var("BAT_NOTIFY_THRESHOLD", "30")) or 30
                crit_thresh = tonumber(Watcher.get_var("BAT_NOTIFY_CRITICAL_THRESHOLD", "15")) or 15
                notify_levels = build_notify_levels()
            end

            local capacity_str = Watcher.read_sys(bat_path .. "/capacity")
            local capacity = tonumber(capacity_str) or 0
            local status = Watcher.read_sys(bat_path .. "/status"):lower()

            if tick_counter % 5 == 0 then
                Watcher.log("battery", string.format("Read: cap=%d%% status=%s raw_cap=%s", capacity, status, capacity_str), "info")
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
                    Watcher.log("battery", "Battery saver ENABLED at " .. capacity .. "% (thresh: " .. saver_thresh .. "%)", "info")
                    engine:emit("on_battery_saver_enabled")
                else
                    Watcher.log("battery", "Battery saver DISABLED at " .. capacity .. "%", "info")
                    engine:emit("on_battery_saver_disabled")
                end
            end

            if status == "discharging" then
                if cycle_start_capacity == nil then
                    cycle_start_capacity = capacity
                end

                for _, level in ipairs(notify_levels) do
                    if not notified_levels[level]
                        and capacity <= level
                        and level <= cycle_start_capacity
                    then
                        notified_levels[level] = true
                        if level <= crit_thresh then
                            Watcher.log("battery", "CRITICAL battery crossed " .. level .. "% (current " .. capacity .. "%)", "error")
                            engine:emit("on_battery_critical", tostring(capacity))
                        else
                            Watcher.log("battery", "LOW battery crossed " .. level .. "% (current " .. capacity .. "%)", "warn")
                            engine:emit("on_battery_low", tostring(capacity))
                        end
                        break
                    end
                end
            elseif status == "charging" or status == "full" or status == "not charging" then
                notified_levels = {}
                cycle_start_capacity = nil
            end

            tick_counter = tick_counter + 1
            coroutine.yield()
        end
    end
}
