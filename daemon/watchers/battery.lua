return {
    name = "battery",
    interval = 15,
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

        local last_bat_saver = Watcher.get_var("BAT_SAVER_ACTIVE", "false")
        local last_notified_level = 0
        local last_pwr_profile = Watcher.get_var("PWR_CURRENT", "")
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

            if target_saver ~= last_bat_saver then
                Watcher.set_var("BAT_SAVER_ACTIVE", target_saver)
                if target_saver == "true" then
                    log("Battery saver ENABLED at " .. capacity .. "% (thresh: " .. saver_thresh .. "%)")
                    engine:emit("on_battery_saver_enabled")
                else
                    log("Battery saver DISABLED at " .. capacity .. "%")
                    engine:emit("on_battery_saver_disabled")
                end
                last_bat_saver = target_saver
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

            local current_pwr = Watcher.get_var("PWR_CURRENT", "")
            if current_pwr ~= last_pwr_profile then
                log("Power profile changed: " .. current_pwr)
                engine:emit("on_power_profile_changed", current_pwr)
                last_notified_level = 0
                last_pwr_profile = current_pwr
            end

            if tick_counter % 60 == 0 then
                local v_raw = tonumber(Watcher.read_sys(bat_path .. "/voltage_now")) or 0
                local i_raw = tonumber(Watcher.read_sys(bat_path .. "/current_now")) or 0
                local p_raw = tonumber(Watcher.read_sys(bat_path .. "/power_now")) or 0

                if p_raw == 0 and v_raw > 0 and i_raw > 0 then
                    p_raw = math.floor(i_raw * v_raw / 1000000)
                    log(string.format("Power calc: V=%.2fV I=%.2fA P=%dmW (calculated)", v_raw / 1000000, i_raw / 1000000, p_raw))
                elseif p_raw > 0 then
                    log(string.format("Power read: %dmW (direct), V=%.2fV, I=%.2fA", p_raw, v_raw / 1000000, i_raw / 1000000))
                end

                local total_w = p_raw / 1000000.0

                local proc_list = Watcher.run_cmd("ps -eo %cpu,pid,comm --sort=-%cpu 2>/dev/null | grep -vE '(%CPU|\\[|ps|grep|awk|retro)' | head -n 10")
                if proc_list ~= "" then
                    local lines = {}
                    for line in proc_list:gmatch("[^\n]+") do
                        table.insert(lines, line)
                    end
                    if #lines >= 3 then
                        local top_cpu, top_pid, top_name = lines[1]:match("(%S+)%s+(%S+)%s+(%S+)")
                        if top_cpu and top_name then
                            top_name = top_name:gsub("Isolated", "Zen-Worker"):gsub("Web", "Web-Content")
                            local app_w = (tonumber(top_cpu) or 0) / 100 * total_w
                            if app_w > 2.0 and (tonumber(top_cpu) or 0) > 5.0 then
                                local now = Watcher.time()
                                local last_app = Watcher.get_var("BAT_LAST_NOTIFIED_APP")
                                local last_time = tonumber(Watcher.get_var("BAT_LAST_NOTIFIED_TIME")) or 0
                                local cooldown = 600
                                local time_diff = now - last_time
                                local ignore_list = Watcher.get_var("BAT_IGNORE_APPS", "")

                                local ignored = false
                                if ignore_list ~= "" and ignore_list ~= "null" then
                                    for item in ignore_list:gmatch("[^|]+") do
                                        if item == top_name then ignored = true; break end
                                    end
                                end

                                if not ignored and (top_name ~= last_app or time_diff > cooldown) then
                                    log(string.format("High usage: %s (%.2fW, %s%% CPU, PID %s)", top_name, app_w, top_cpu, top_pid))
                                    engine:emit("on_battery_usage_high", top_name, string.format("%.2f", app_w), top_cpu, top_pid)
                                    Watcher.set_var("BAT_LAST_NOTIFIED_APP", top_name)
                                    Watcher.set_var("BAT_LAST_NOTIFIED_TIME", tostring(now))
                                end
                            end
                        end
                    end
                end
                Watcher.set_var("BAT_LAST_NOTIFIED_APP", "none")
            end

            tick_counter = tick_counter + 1
            coroutine.yield()
        end
    end
}
