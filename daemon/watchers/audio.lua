return {
    name = "audio",
    interval = 2,
    enabled = function()
        return true
    end,
    start = function(engine)
        local Watcher = require("watcher")
        local Audio = require("audio")
        local log = function(msg) Watcher.log("audio", msg) end

        log("Audio watcher starting")

        local last_sink_id = ""
        local last_source_id = ""
        local primary_sink_name = Watcher.get_var("AUDIO_PRIMARY_SINK", "")
        local primary_source_name = Watcher.get_var("AUDIO_PRIMARY_SOURCE", "")
        local fallback_sink_name = Watcher.get_var("AUDIO_FALLBACK_SINK", "")
        local fallback_source_name = Watcher.get_var("AUDIO_FALLBACK_SOURCE", "")

        if primary_sink_name ~= "" then
            log("Primary sink: " .. primary_sink_name)
        end
        if fallback_sink_name ~= "" then
            log("Fallback sink: " .. fallback_sink_name)
        end
        if primary_source_name ~= "" then
            log("Primary source: " .. primary_source_name)
        end
        if fallback_source_name ~= "" then
            log("Fallback source: " .. fallback_source_name)
        end

        while true do
            local old_primary_sink = primary_sink_name
            local old_primary_source = primary_source_name

            Watcher.reload_vars()

            primary_sink_name = Watcher.get_var("AUDIO_PRIMARY_SINK", "")
            primary_source_name = Watcher.get_var("AUDIO_PRIMARY_SOURCE", "")
            fallback_sink_name = Watcher.get_var("AUDIO_FALLBACK_SINK", "")
            fallback_source_name = Watcher.get_var("AUDIO_FALLBACK_SOURCE", "")

            if primary_sink_name ~= old_primary_sink then
                log("Priority config changed: sink primary " .. (old_primary_sink or "none") .. " -> " .. primary_sink_name)
            end
            if primary_source_name ~= old_primary_source then
                log("Priority config changed: source primary " .. (old_primary_source or "none") .. " -> " .. primary_source_name)
            end

            local current_sink_id = Audio.get_default_sink()

            if current_sink_id ~= last_sink_id then
                if last_sink_id ~= "" and current_sink_id == "" then
                    log("Default sink disappeared, was: " .. last_sink_id)
                    if fallback_sink_name ~= "" then
                        local result, name = Audio.apply_fallback("sink")
                        if result == "fallback_applied" then
                            log("Fallback applied: " .. name)
                            engine:emit("on_audio_sink_fallback", name)
                        else
                            log("No fallback available (" .. result .. ")")
                        end
                    end
                elseif current_sink_id ~= "" and last_sink_id ~= "" then
                    log("Default sink changed: " .. last_sink_id .. " -> " .. current_sink_id)
                elseif current_sink_id ~= "" and last_sink_id == "" then
                    log("Default sink appeared: " .. current_sink_id)
                end

                if primary_sink_name ~= "" then
                    local primary_id = Audio.get_sink_id_by_persistent(primary_sink_name)
                    if primary_id ~= "" then
                        if current_sink_id ~= primary_id then
                            log("Enforcing primary sink: " .. primary_sink_name .. " (ID " .. primary_id .. "), current was " .. current_sink_id)
                            Audio.set_default("sink", primary_id)
                            current_sink_id = primary_id
                        end
                    else
                        log("WARN: Primary sink not available: " .. primary_sink_name)
                    end
                end

                last_sink_id = current_sink_id
            end

            local current_source_id = Audio.get_default_source()

            if current_source_id ~= last_source_id then
                if last_source_id ~= "" and current_source_id == "" then
                    log("Default source disappeared, was: " .. last_source_id)
                    if fallback_source_name ~= "" then
                        local result, name = Audio.apply_fallback("source")
                        if result == "fallback_applied" then
                            log("Fallback applied: " .. name)
                            engine:emit("on_audio_source_fallback", name)
                        else
                            log("No fallback available (" .. result .. ")")
                        end
                    end
                elseif current_source_id ~= "" and last_source_id ~= "" then
                    log("Default source changed: " .. last_source_id .. " -> " .. current_source_id)
                elseif current_source_id ~= "" and last_source_id == "" then
                    log("Default source appeared: " .. current_source_id)
                end

                if primary_source_name ~= "" then
                    local primary_id = Audio.get_source_id_by_persistent(primary_source_name)
                    if primary_id ~= "" then
                        if current_source_id ~= primary_id then
                            log("Enforcing primary source: " .. primary_source_name .. " (ID " .. primary_id .. "), current was " .. current_source_id)
                            Audio.set_default("source", primary_id)
                            current_source_id = primary_id
                        end
                    else
                        log("WARN: Primary source not available: " .. primary_source_name)
                    end
                end

                last_source_id = current_source_id
            end

            coroutine.yield()
        end
    end
}
