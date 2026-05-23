return {
    name = "slideshow",
    interval = 1,
    enabled = function()
        return true
    end,
    start = function(engine)
        local Watcher = require("watcher")

        local slideshow_tick = 0
        local current_rand_target = 0

        while true do
            Watcher.reload_vars()
            local slideshow_active = Watcher.get_var("WALL_SLIDESHOW_ACTIVE", "false")

            if slideshow_active == "true" then
                local interval = Watcher.get_var("WALL_SLIDESHOW_INTERVAL", "300")
                local target_ticks = tonumber(interval) or 300

                if interval == "random" then
                    if current_rand_target == 0 then
                        current_rand_target = math.random(300, 1200)
                        Watcher.log("slideshow", "Random interval set to " .. current_rand_target .. "s", "info")
                    end
                    target_ticks = current_rand_target
                end

                if slideshow_tick >= target_ticks then
                    Watcher.log("slideshow", "Slideshow tick fired (interval: " .. target_ticks .. "s, tick: " .. slideshow_tick .. ")", "info")
                    engine:emit("on_slideshow_tick")
                    slideshow_tick = 0
                    current_rand_target = 0
                end

                slideshow_tick = slideshow_tick + 1
            else
                slideshow_tick = 0
                current_rand_target = 0
            end

            coroutine.yield()
        end
    end
}
