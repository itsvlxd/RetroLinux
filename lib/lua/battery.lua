local Watcher = require("watcher")

local Battery = {}

function Battery.set_saver(val, force)
    if val == "true" then
        Watcher.set_var("BAT_SAVER_FORCED", "true")
        Watcher.set_var("BAT_SAVER_ACTIVE", "true")
        return true
    elseif val == "false" then
        if force == "-f" or force == "--force" then
            Watcher.set_var("BAT_SAVER_FORCED", "true")
            Watcher.set_var("BAT_SAVER_ACTIVE", "false")
        else
            Watcher.set_var("BAT_SAVER_FORCED", "false")
        end
        return true
    elseif tonumber(val) then
        Watcher.set_var("BAT_SAVER_THRESHOLD", val)
        Watcher.set_var("BAT_SAVER_FORCED", "false")
        return true
    end
    return false
end

function Battery.log_event(type, val)
    val = tonumber(val) or 0
    local today = os.date("%Y-%m-%d")
    local entry_0 = Watcher.get_var("BAT_STATS_0")

    local d_date, d_cycles, d_seconds = today, 0, 0
    if entry_0 and entry_0 ~= "null" and entry_0:find("|") then
        local parts = {}
        for part in entry_0:gmatch("([^|]*)") do
            table.insert(parts, part)
        end
        d_date = parts[1] or today
        d_cycles = tonumber(parts[2]) or 0
        d_seconds = tonumber(parts[3]) or 0
    end

    if d_date ~= today then
        for i = 5, 0, -1 do
            local moving = Watcher.get_var("BAT_STATS_" .. i)
            if not moving or moving == "null" then moving = "0000-00-00|0|0" end
            Watcher.set_var("BAT_STATS_" .. (i + 1), moving)
        end
        d_date = today
        d_cycles = 0
        d_seconds = 0
    end

    if type == "cycle" then
        d_cycles = d_cycles + val
    else
        d_seconds = d_seconds + val
    end

    Watcher.set_var("BAT_STATS_0", d_date .. "|" .. d_cycles .. "|" .. d_seconds)
end

function Battery.sync_hyprland_power(state)
    local mon_name = Watcher.run_cmd("hyprctl monitors -j | jq -r '.[] | select(.name | startswith(\"eDP\")) | .name' | head -n 1")
    if mon_name == "" then return end

    local info = Watcher.run_cmd("hyprctl monitors -j | jq -r --arg n '" .. mon_name .. "' '.[] | select(.name==$n) | \"\\(.width) \\(.height) \\(.x) \\(.y) \\(.scale)\"'")
    local w, h, x, y, scale = info:match("(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    if not w then return end

    if state == "true" then
        Watcher.run_cmd("hyprctl keyword monitor '" .. mon_name .. ", " .. w .. "x" .. h .. "@60, " .. x .. "x" .. y .. ", " .. scale .. "'")
        Watcher.run_cmd("brightnessctl set 30%")
    else
        Watcher.run_cmd("hyprctl keyword monitor '" .. mon_name .. ", highres, " .. x .. "x" .. y .. ", " .. scale .. "'")
    end
end

function Battery.get_info()
    local bat_path = Watcher.get_var("BAT_PATH")
    if bat_path == "" or bat_path == "null" then
        bat_path = Watcher.run_cmd("ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1"):gsub("%s+$", "")
    end
    if bat_path == "" then return "no-battery" end

    local cap = Watcher.read_sys(bat_path .. "/capacity")
    local health = Watcher.read_sys(bat_path .. "/capacity_level")
    local model = Watcher.read_sys(bat_path .. "/model_name")
    local p_raw = tonumber(Watcher.read_sys(bat_path .. "/power_now")) or 0
    local v_raw = tonumber(Watcher.read_sys(bat_path .. "/voltage_now")) or 0
    local energy = tonumber(Watcher.read_sys(bat_path .. "/energy_now")) or tonumber(Watcher.read_sys(bat_path .. "/charge_now")) or 0
    local power = tonumber(Watcher.read_sys(bat_path .. "/power_now")) or tonumber(Watcher.read_sys(bat_path .. "/current_now")) or 0
    local status = Watcher.read_sys(bat_path .. "/status"):lower()

    local saver = Watcher.get_var("BAT_SAVER_ACTIVE")

    local sot_label = "N/A"
    if status:find("discharging") then
        local start_ts = Watcher.get_var("BAT_DISCONNECT_TIME")
        if start_ts and start_ts ~= "" and start_ts ~= "null" then
            local diff = os.time() - tonumber(start_ts)
            local days = math.floor(diff / 86400)
            local hrs = math.floor((diff % 86400) / 3600)
            local mins = math.floor((diff % 3600) / 60)
            local secs = diff % 60
            if days > 0 then
                sot_label = string.format("%dd %02dh %02dm %02ds", days, hrs, mins, secs)
            elseif hrs > 0 then
                sot_label = string.format("%02dh %02dm %02ds", hrs, mins, secs)
            else
                sot_label = string.format("%02dm %02ds", mins, secs)
            end
        else
            Watcher.set_var("BAT_DISCONNECT_TIME", tostring(os.time()))
            sot_label = "00m 00s"
        end
    end

    local estimate = "N/A"
    if status:find("discharging") and power > 0 then
        local seconds_left = energy * 3600 / power
        local e_hrs = math.floor(seconds_left / 3600)
        local e_mins = math.floor((seconds_left % 3600) / 60)
        estimate = string.format("%dh %dm", e_hrs, e_mins)
    elseif status:find("charging") and power > 0 then
        local full_energy = tonumber(Watcher.read_sys(bat_path .. "/energy_full")) or tonumber(Watcher.read_sys(bat_path .. "/charge_full")) or 0
        local needed = full_energy - energy
        if needed > 0 then
            local seconds_to_full = needed * 3600 / power
            estimate = string.format("%dh %dm to full", math.floor(seconds_to_full / 3600), math.floor((seconds_to_full % 3600) / 60))
        end
    end

    if p_raw == 0 then
        local i_raw = tonumber(Watcher.read_sys(bat_path .. "/current_now")) or 0
        p_raw = i_raw * v_raw / 1000000
    end

    local saver_label = saver == "true" and "ON" or "OFF"

    return string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s",
        cap, status, health ~= "" and health or "N/A", p_raw, v_raw,
        model ~= "" and model or "Generic", saver_label, sot_label, estimate)
end

function Battery.set_limit(limit)
    local bat_path = Watcher.get_var("BAT_PATH")
    if bat_path == "" or bat_path == "null" then
        bat_path = Watcher.run_cmd("ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1"):gsub("%s+$", "")
    end
    local path = bat_path .. "/charge_control_end_threshold"
    if Watcher.run_cmd("test -f '" .. path .. "' && echo yes"):find("yes") then
        Watcher.run_cmd("echo '" .. limit .. "' | sudo tee '" .. path .. "' >/dev/null")
        return true
    end
    return false
end

return Battery
