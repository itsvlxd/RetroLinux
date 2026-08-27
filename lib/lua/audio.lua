local Audio = {}

local Watcher = require("watcher")

local function run_cmd(cmd)
    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

local _wpctl_cache = {}
local _wpctl_mtime = 0

local function _parse_wpctl_status()
    local mtime_result = io.popen("stat -c %Y /proc/$(pgrep -o wireplumber)/status 2>/dev/null")
    if mtime_result then
        local current_mtime = mtime_result:read("*l")
        mtime_result:close()
        if current_mtime == _wpctl_mtime and current_mtime ~= "" then
            return _wpctl_cache
        end
        _wpctl_mtime = current_mtime
    end

    _wpctl_cache = { sinks = {}, sources = {}, default_sink = "", default_source = "" }

    local status = run_cmd("wpctl status")
    local in_audio = true
    local section = ""
    local sub_section = ""
    local seen_streams = false

    for line in status:gmatch("[^\n]+") do
        if line:match("^%s*├─ Sinks:") or line:match("^%s*└─ Sinks:") then
            if seen_streams then
                in_audio = false
            end
            section = in_audio and "sinks" or ""
            sub_section = in_audio and "devices" or ""
        elseif line:match("^%s*├─ Sources:") or line:match("^%s*└─ Sources:") then
            if seen_streams then
                in_audio = false
            end
            section = in_audio and "sources" or ""
            sub_section = in_audio and "devices" or ""
        elseif line:match("^%s*├─ Filters:") or line:match("^%s*└─ Filters:") then
            section = ""
            sub_section = ""
        elseif line:match("^%s*├─ Streams:") or line:match("^%s*└─ Streams:") then
            if seen_streams then
                in_audio = false
            end
            sub_section = "streams"
            if in_audio then seen_streams = true end
        elseif sub_section == "devices" and section ~= "" and in_audio then
            local is_default = line:match("%*") ~= nil
            local id = line:match("[%│├└─]%s*%*?%s*(%d+)%.%s")
            if id then
                local name = line:match("%d+%.%s+(.-)%s+%[") or ""
                name = name:gsub("^%s+", ""):gsub("%s+$", "")
                local entry = { id = id, name = name, is_default = is_default }
                if section == "sinks" then
                    table.insert(_wpctl_cache.sinks, entry)
                    if is_default then _wpctl_cache.default_sink = id end
                else
                    table.insert(_wpctl_cache.sources, entry)
                    if is_default then _wpctl_cache.default_source = id end
                end
            end
        end
    end

    return _wpctl_cache
end

function Audio.invalidate_cache()
    _wpctl_cache = {}
    _wpctl_mtime = 0
end

function Audio.get_default_sink()
    local parsed = _parse_wpctl_status()
    return parsed.default_sink
end

function Audio.get_default_source()
    local parsed = _parse_wpctl_status()
    return parsed.default_source
end

function Audio.get_sink_name(id)
    if not id or id == "" then return "" end
    local parsed = _parse_wpctl_status()
    for _, sink in ipairs(parsed.sinks) do
        if sink.id == id then return sink.name end
    end
    local name = run_cmd("wpctl inspect " .. id .. " 2>/dev/null | grep 'node.description' | head -1 | sed 's/.*= *//' | tr -d '\"'")
    return name
end

function Audio.get_source_name(id)
    if not id or id == "" then return "" end
    local parsed = _parse_wpctl_status()
    for _, source in ipairs(parsed.sources) do
        if source.id == id then return source.name end
    end
    local name = run_cmd("wpctl inspect " .. id .. " 2>/dev/null | grep 'node.description' | head -1 | sed 's/.*= *//' | tr -d '\"'")
    return name
end

function Audio.get_sink_persistent_name(id)
    if not id or id == "" then return "" end
    local result = run_cmd("wpctl inspect " .. id .. " 2>/dev/null | grep 'node.name' | head -1 | awk '{print $NF}' | tr -d '\"'")
    return result
end

function Audio.get_source_persistent_name(id)
    if not id or id == "" then return "" end
    local result = run_cmd("wpctl inspect " .. id .. " 2>/dev/null | grep 'node.name' | head -1 | awk '{print $NF}' | tr -d '\"'")
    return result
end

function Audio.get_sink_id_by_persistent(name)
    if not name or name == "" then return "" end
    local parsed = _parse_wpctl_status()
    for _, sink in ipairs(parsed.sinks) do
        local pw_name = Audio.get_sink_persistent_name(sink.id)
        if pw_name == name then return sink.id end
    end
    return ""
end

function Audio.get_source_id_by_persistent(name)
    if not name or name == "" then return "" end
    local parsed = _parse_wpctl_status()
    for _, source in ipairs(parsed.sources) do
        local pw_name = Audio.get_source_persistent_name(source.id)
        if pw_name == name then return source.id end
    end
    return ""
end

function Audio.list_sinks()
    local parsed = _parse_wpctl_status()
    local sinks = {}
    for _, sink in ipairs(parsed.sinks) do
        local pw_name = Audio.get_sink_persistent_name(sink.id)
        if not sink.name:match("Easy Effects") then
            table.insert(sinks, { id = sink.id, name = sink.name, persistent_name = pw_name })
        end
    end
    return sinks
end

function Audio.list_sources()
    local parsed = _parse_wpctl_status()
    local sources = {}
    for _, source in ipairs(parsed.sources) do
        local pw_name = Audio.get_source_persistent_name(source.id)
        if not source.name:match("Easy Effects") then
            table.insert(sources, { id = source.id, name = source.name, persistent_name = pw_name })
        end
    end
    return sources
end

function Audio.device_exists(type, name)
    if not type or not name then return false end
    local current_id
    if type == "sink" then
        current_id = Audio.get_sink_id_by_persistent(name)
    else
        current_id = Audio.get_source_id_by_persistent(name)
    end
    return current_id ~= ""
end

function Audio.set_default(type, id)
    if not type or not id then return false end
    local result = run_cmd("wpctl set-default '" .. id .. "' 2>/dev/null && echo OK || echo ERR")
    return result == "OK"
end

function Audio.clear_bt_filter_defaults()
    local status = run_cmd("wpctl status")
    local in_filters = false
    for line in status:gmatch("[^\n]+") do
        if line:match("^%s*├─ Filters:") or line:match("^%s*└─ Filters:") then
            in_filters = true
        elseif line:match("^%s*└─") or line:match("^%s*├─%s+Streams:") or line:match("^%s*└─%s+Streams:") then
            in_filters = false
        elseif in_filters and line:match("%*") then
            local id = line:match("(%d+)%.%s")
            if id then
                local pw_name = run_cmd("wpctl inspect " .. id .. " 2>/dev/null | grep 'node.name' | head -1 | awk '{print $NF}' | tr -d '\"'")
                if pw_name and pw_name:match("^bluez_input%.") then
                    run_cmd("wpctl clear-default '" .. id .. "'")
                end
            end
        end
    end
end

function Audio.apply_fallback(type)
    local fallback_var
    if type == "sink" then
        fallback_var = "AUDIO_FALLBACK_SINK"
    else
        fallback_var = "AUDIO_FALLBACK_SOURCE"
    end

    local current_id
    if type == "sink" then
        current_id = Audio.get_default_sink()
    else
        current_id = Audio.get_default_source()
    end

    local current_name = ""
    if current_id and current_id ~= "" then
        if type == "sink" then
            current_name = Audio.get_sink_name(current_id)
        else
            current_name = Audio.get_source_name(current_id)
        end
    end

    if current_name ~= "" and current_name ~= "EasyEffects" then
        return "current_still_valid", current_name
    end

    local fallback_name = Watcher.get_var(fallback_var, "")
    if fallback_name == "" then
        return "no_fallback_configured", ""
    end

    local fallback_id
    if type == "sink" then
        fallback_id = Audio.get_sink_id_by_persistent(fallback_name)
    else
        fallback_id = Audio.get_source_id_by_persistent(fallback_name)
    end

    if fallback_id == "" then
        return "fallback_not_available", ""
    end

    Audio.set_default(type, fallback_id)

    local fallback_display_name
    if type == "sink" then
        fallback_display_name = Audio.get_sink_name(fallback_id)
    else
        fallback_display_name = Audio.get_source_name(fallback_id)
    end

    local eq_preset = Watcher.get_var("AUDIO_EQ_PRESET", "")
    if eq_preset ~= "" and eq_preset ~= "None" then
        local ee_running = run_cmd("pgrep -x easyeffects 2>/dev/null && echo yes || echo no")
        if ee_running == "yes" then
            run_cmd("easyeffects -l '" .. eq_preset .. "' 2>/dev/null")
        end
    end

    return "fallback_applied", fallback_display_name
end

function Audio.apply_primary(type)
    local primary_var
    if type == "sink" then
        primary_var = "AUDIO_PRIMARY_SINK"
    else
        primary_var = "AUDIO_PRIMARY_SOURCE"
    end

    local primary_name = Watcher.get_var(primary_var, "")
    if primary_name == "" then
        return "no_primary_configured", ""
    end

    local primary_id
    if type == "sink" then
        primary_id = Audio.get_sink_id_by_persistent(primary_name)
    else
        primary_id = Audio.get_source_id_by_persistent(primary_name)
    end

    if primary_id == "" then
        return "primary_not_available", ""
    end

    local current_id
    if type == "sink" then
        current_id = Audio.get_default_sink()
    else
        current_id = Audio.get_default_source()
    end

    if current_id == primary_id then
        local current_name
        if type == "sink" then
            current_name = Audio.get_sink_name(current_id)
        else
            current_name = Audio.get_source_name(current_id)
        end
        return "already_primary", current_name
    end

    Audio.set_default(type, primary_id)

    local primary_display_name
    if type == "sink" then
        primary_display_name = Audio.get_sink_name(primary_id)
    else
        primary_display_name = Audio.get_source_name(primary_id)
    end

    local eq_preset = Watcher.get_var("AUDIO_EQ_PRESET", "")
    if eq_preset ~= "" and eq_preset ~= "None" then
        local ee_running = run_cmd("pgrep -x easyeffects 2>/dev/null && echo yes || echo no")
        if ee_running == "yes" then
            run_cmd("easyeffects -l '" .. eq_preset .. "' 2>/dev/null")
        end
    end

    return "primary_applied", primary_display_name
end

return Audio
