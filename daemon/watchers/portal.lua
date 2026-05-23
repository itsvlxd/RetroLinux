return {
    name = "portal",
    interval = 30,
    enabled = function()
        local Watcher = require("watcher")
        return Watcher.run_cmd("pgrep -f 'xdg-desktop-portal' >/dev/null 2>&1 && echo yes") == "yes"
    end,
    start = function(engine)
        local Watcher = require("watcher")
        local XDG = require("xdg")

        local consecutive_failures = 0
        local max_failures = 3
        local last_restart_time = 0
        local restart_cooldown = 60
        local backend_warning_shown = {}

        while true do
            Watcher.reload_vars()

            local portal_pid = Watcher.run_cmd("pgrep -x 'xdg-desktop-portal' | head -1")
            local backend = XDG.get_portal_backend()
            local backend_pkg = "xdg-desktop-portal-" .. backend

            local portal_alive = false
            if portal_pid ~= "" then
                portal_alive = Watcher.run_cmd("kill -0 " .. portal_pid .. " 2>/dev/null && echo yes") == "yes"
            end

            if not portal_alive then
                consecutive_failures = consecutive_failures + 1
                Watcher.log("portal", "Portal daemon not responding (failure " .. consecutive_failures .. "/" .. max_failures .. ")", "warn")

                if consecutive_failures >= max_failures then
                    local now = Watcher.time()
                    if now - last_restart_time >= restart_cooldown then
                        Watcher.log("portal", "Attempting portal restart with env injection", "info")
                        local injected = XDG.inject_portal_env()
                        Watcher.sleep(3)

                        local new_pid = Watcher.run_cmd("pgrep -x 'xdg-desktop-portal' | head -1")
                        if new_pid ~= "" then
                            Watcher.log("portal", "Portal daemon restarted successfully (PID: " .. new_pid .. ", backend: " .. backend .. ")", "info")
                            consecutive_failures = 0
                            last_restart_time = Watcher.time()
                        else
                            Watcher.log("portal", "Portal restart failed, will retry on next cycle", "warn")
                            last_restart_time = Watcher.time()
                        end
                    else
                        Watcher.log("portal", "Restart cooldown active, skipping (" .. (restart_cooldown - (now - last_restart_time)) .. "s remaining)", "info")
                    end
                end
            else
                local backend_pid = Watcher.run_cmd("pgrep -x 'xdg-desktop-portal-" .. backend .. "' | head -1")
                local backend_alive = false
                if backend_pid ~= "" then
                    backend_alive = Watcher.run_cmd("kill -0 " .. backend_pid .. " 2>/dev/null && echo yes") == "yes"
                end

                if not backend_alive then
                    local pkg_installed = Watcher.run_cmd("pacman -Qq '" .. backend_pkg .. "' >/dev/null 2>&1 && echo yes") == "yes"
                    if pkg_installed then
                        Watcher.log("portal", "Backend '" .. backend .. "' died, restarting", "warn")
                        Watcher.run_cmd("systemctl --user restart --wait xdg-desktop-portal-" .. backend .. " 2>/dev/null")
                        Watcher.sleep(2)
                        local new_backend_pid = Watcher.run_cmd("pgrep -x 'xdg-desktop-portal-" .. backend .. "' | head -1")
                        if new_backend_pid ~= "" then
                            Watcher.log("portal", "Backend '" .. backend .. "' restarted (PID: " .. new_backend_pid .. ")", "info")
                        else
                            Watcher.log("portal", "Backend '" .. backend .. "' restart failed", "error")
                        end
                    else
                        if not backend_warning_shown[backend] then
                            Watcher.log("portal", "Backend '" .. backend .. "' package not installed (" .. backend_pkg .. "), skipping", "warn")
                            backend_warning_shown[backend] = true
                        end
                    end
                end

                consecutive_failures = 0
            end

            coroutine.yield()
        end
    end
}
