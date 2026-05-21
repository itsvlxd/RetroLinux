return {
    name = "wallpaper",
    interval = 1,
    enabled = function()
        return true
    end,
    start = function(engine)
        local Watcher = require("watcher")
        local Wallpaper = require("wallpaper")
        local log = function(msg) Watcher.log("wallpaper", msg) end

        local was_paused = false
        local was_static = false

        while true do
            Watcher.reload_vars()

            local force_static = Watcher.get_var("WALL_STATIC_FORCED", "false")
            local saver_active = Watcher.get_var("BAT_SAVER_ACTIVE", "false")
            local static_on_saver = Watcher.get_var("WALL_STATIC_ON_SAVER", "true")
            local wall_paused = Watcher.get_var("WALL_PAUSED", "false")
            local mpvpaper_running = Watcher.run_cmd("pgrep -x mpvpaper >/dev/null 2>&1 && echo yes")

            local should_be_static = force_static == "true" or (saver_active == "true" and static_on_saver == "true")

            if was_static and not should_be_static then
                log("Static mode disabled, resuming live wallpaper")
                Watcher.set_var("WALL_PAUSED", "false")
                wall_paused = "false"
            end

            if should_be_static then
                if mpvpaper_running == "yes" then
                    log("Static mode active, stopping mpvpaper")
                    Wallpaper.pause_wallpaper()
                end
                if was_paused then
                    was_paused = false
                end
            else
                if mpvpaper_running ~= "yes" and wall_paused ~= "true" then
                    local gen_ts = Watcher.run_cmd("cat /tmp/retro_wallpaper_gen 2>/dev/null"):gsub("%s+$", "")
                    local gen_age = 99
                    if gen_ts ~= "" and tonumber(gen_ts) and tonumber(gen_ts) > 1000000000 then
                        local gen_sec = math.floor(tonumber(gen_ts) / 1000000000)
                        gen_age = os.time() - gen_sec
                    end
                    local transition_in_progress = gen_age < 3

                    if not transition_in_progress then
                        local current = Watcher.get_var("WALL_CURRENT", "")
                        if current ~= "" and current ~= "null" then
                            local video = Wallpaper.find_video_version(current)
                            if video then
                                log("mpvpaper not running, launching with " .. video)
                                Wallpaper.start(video, true)
                            end
                        end
                    end
                end

                local should_pause = Wallpaper.should_pause()

                if should_pause and not was_paused then
                    log("Fullscreen or blocked process detected, pausing wallpaper")
                    Wallpaper.pause_wallpaper()
                    was_paused = true
                elseif not should_pause and was_paused then
                    log("Fullscreen cleared, resuming wallpaper")
                    local current = Watcher.get_var("WALL_CURRENT", "")
                    if current ~= "" and current ~= "null" then
                        local video = Wallpaper.find_video_version(current)
                        if video then
                            Wallpaper.start(video, true)
                        end
                    end
                    was_paused = false
                end
            end

            was_static = should_be_static
            coroutine.yield()
        end
    end
}
