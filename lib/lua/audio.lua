local Audio = {}

local Watcher = require("watcher")

local function run_cmd(cmd)
    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

function Audio.get_default_sink()
    local result = run_cmd("wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\\.$/ && match($(i-1),/\\*/)) {gsub(/\\./,'',$i); print $i; exit}}'")
    return result
end

function Audio.get_default_source()
    local result = run_cmd("wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\\.$/ && match($(i-1),/\\*/)) {gsub(/\\./,'',$i); print $i; exit}}'")
    return result
end

function Audio.get_sink_name(id)
    if not id or id == "" then return "" end
    local result = run_cmd("wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/' | grep '" .. id .. "\\.' | head -1 | sed 's/.*[0-9]\\. //' | awk -F'[' '{print $1}' | xargs")
    return result
end

function Audio.get_source_name(id)
    if not id or id == "" then return "" end
    local result = run_cmd("wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/' | grep '" .. id .. "\\.' | head -1 | sed 's/.*[0-9]\\. //' | awk -F'[' '{print $1}' | xargs")
    return result
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
    local ids = run_cmd("wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\\./) {gsub(/\\./,'',$i); print $i}}'")
    for id in ids:gmatch("[^%s]+") do
        local pw_name = Audio.get_sink_persistent_name(id)
        if pw_name == name then
            return id
        end
    end
    return ""
end

function Audio.get_source_id_by_persistent(name)
    if not name or name == "" then return "" end
    local ids = run_cmd("wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\\./) {gsub(/\\./,'',$i); print $i}}'")
    for id in ids:gmatch("[^%s]+") do
        local pw_name = Audio.get_source_persistent_name(id)
        if pw_name == name then
            return id
        end
    end
    return ""
end

function Audio.list_sinks()
    local result = run_cmd("wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sinks:/,/Sources:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\\./) {gsub(/\\./,'',$i); print $i}}'")
    local sinks = {}
    for id in result:gmatch("[^%s]+") do
        local name = Audio.get_sink_name(id)
        local pw_name = Audio.get_sink_persistent_name(id)
        if not name:match("Easy Effects") then
            table.insert(sinks, { id = id, name = name, persistent_name = pw_name })
        end
    end
    return sinks
end

function Audio.list_sources()
    local result = run_cmd("wpctl status 2>/dev/null | sed -n '/^Audio$/,/^Video$/p' | awk '/Sources:/,/Streams:/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\\./) {gsub(/\\./,'',$i); print $i}}'")
    local sources = {}
    for id in result:gmatch("[^%s]+") do
        local name = Audio.get_source_name(id)
        local pw_name = Audio.get_source_persistent_name(id)
        if not name:match("Easy Effects") then
            table.insert(sources, { id = id, name = name, persistent_name = pw_name })
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
