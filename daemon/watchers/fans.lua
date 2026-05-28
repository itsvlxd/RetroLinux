return {
    name = "fans",
    interval = 10,
    enabled = function()
        return true
    end,
    start = function(engine)
        local Watcher = require("watcher")

        local enabled = Watcher.get_var("FAN_ENABLED", "false")
        if enabled ~= "true" then
            Watcher.log("fans", "Fan control disabled, watcher dormant", "info")
            while true do
                Watcher.sleep(30)
                enabled = Watcher.get_var("FAN_ENABLED", "false")
                if enabled == "true" then
                    Watcher.log("fans", "Fan control enabled, watcher activating", "info")
                    break
                end
            end
        end

        local retro_dir = os.getenv("RETRO_DIR") or "/opt/retrolinux"
        local core = retro_dir .. "/scripts/fans_core.sh"

        Watcher.log("fans", "Fan curve daemon started", "info")

        while true do
            Watcher.reload_vars()

            local enabled = Watcher.get_var("FAN_ENABLED", "false")
            if enabled ~= "true" then
                Watcher.log("fans", "Fan control disabled, pausing", "info")
                while true do
                    Watcher.sleep(30)
                    Watcher.reload_vars()
                    enabled = Watcher.get_var("FAN_ENABLED", "false")
                    if enabled == "true" then
                        Watcher.log("fans", "Fan control re-enabled, resuming", "info")
                        break
                    end
                end
            end

            local result = Watcher.run_cmd("bash '" .. core .. "' --daemon-tick 2>/dev/null")
            if result and result ~= "" then
                Watcher.log("fans", result, "info")
            end

            coroutine.yield()
        end
    end
}
