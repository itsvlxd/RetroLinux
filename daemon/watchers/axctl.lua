return {
    name = "axctl",
    interval = 10,
    enabled = function()
        local Watcher = require("watcher")
        local uid = os.execute("id -u") or "1000"
        local handle = io.popen("id -u 2>/dev/null")
        if handle then
            uid = handle:read("*l") or "1000"
            handle:close()
        end
        uid = uid:gsub("%s+", "")
        local sock = "/tmp/axctl-" .. uid .. ".sock"
        return Watcher.run_cmd("[ -S '" .. sock .. "' ] && echo yes") == "yes"
    end,
    start = function(engine)
        local Watcher = require("watcher")

        local consecutive_failures = 0
        local max_failures = 3
        local last_restart_time = 0
        local restart_cooldown = 30

        local config_path = os.getenv("HOME") and (os.getenv("HOME") .. "/.config/retro/shellctl.toml") or "/tmp/shellctl.toml"

        while true do
            local daemon_running = Watcher.run_cmd("pgrep -f 'axctl.*daemon' >/dev/null 2>&1 && echo yes") == "yes"

            if not daemon_running then
                consecutive_failures = consecutive_failures + 1
                Watcher.log("axctl", "Daemon not running (failure " .. consecutive_failures .. "/" .. max_failures .. ")", "warn")

                if consecutive_failures >= max_failures then
                    local now = Watcher.time()
                    if now - last_restart_time >= restart_cooldown then
                        Watcher.log("axctl", "Attempting daemon restart", "info")
                        Watcher.run_cmd("axctl -c '" .. config_path .. "' daemon &")
                        Watcher.sleep(3)

                        local new_running = Watcher.run_cmd("pgrep -f 'axctl.*daemon' >/dev/null 2>&1 && echo yes") == "yes"
                        if new_running then
                            Watcher.log("axctl", "Daemon restarted successfully", "info")
                            consecutive_failures = 0
                            last_restart_time = Watcher.time()
                        else
                            Watcher.log("axctl", "Daemon restart failed, will retry on next cycle", "warn")
                            last_restart_time = Watcher.time()
                        end
                    else
                        Watcher.log("axctl", "Restart cooldown active, skipping (" .. (restart_cooldown - (now - last_restart_time)) .. "s remaining)", "info")
                    end
                end
            else
                consecutive_failures = 0
            end

            coroutine.yield()
        end
    end
}
