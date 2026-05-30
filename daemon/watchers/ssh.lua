return {
    name = "ssh",
    interval = 2,
    enabled = function()
        local Watcher = require("watcher")
        local ok = Watcher.run_cmd("systemctl is-active sshd 2>/dev/null | grep -q active && echo ok")
        return ok == "ok"
    end,
    start = function(engine)
        local Watcher = require("watcher")

        Watcher.log("ssh", "SSH watcher started", "info")

        local last_log_cursor = ""

        local function get_new_logs()
            local since = ""
            if last_log_cursor ~= "" then
                since = " --after-cursor='" .. last_log_cursor .. "'"
            else
                since = " --since '10 seconds ago'"
            end
            local cmd = "journalctl -u sshd --no-pager -o cat" .. since .. " 2>/dev/null"
            local output = Watcher.run_cmd(cmd)
            if output == "" then
                return "", ""
            end
            local cursor_cmd = "journalctl -u sshd --no-pager -n 1 --show-cursor 2>/dev/null | grep -oP 'cursor: \\K.*'"
            local cursor = Watcher.run_cmd(cursor_cmd)
            return output, cursor
        end

        while true do
            local logs, cursor = get_new_logs()
            if logs ~= "" then
                if cursor ~= "" then
                    last_log_cursor = cursor
                end
                for line in logs:gmatch("[^\n]+") do
                    local user, ip, method

                    user = line:match("Accepted .+ for (%S+) from (%S+) port")
                    if user then
                        ip = line:match("Accepted .+ for %S+ from (%S+) port")
                        method = line:match("Accepted (%S+) for")
                        Watcher.log("ssh", "Login: " .. user .. "@" .. ip .. " (" .. (method or "unknown") .. ")", "info")
                        engine:emit("on_ssh_login", user, ip, method)
                        goto continue
                    end

                    user = line:match("Failed .+ for (%S+) from (%S+) port")
                    if user then
                        ip = line:match("Failed .+ for %S+ from (%S+) port")
                        Watcher.log("ssh", "Failed: " .. user .. "@" .. ip, "warn")
                        engine:emit("on_ssh_failed", user, ip)
                        goto continue
                    end

                    local close_user, close_ip, close_reason

                    close_user, close_ip = line:match("Connection closed by authenticating user (%S+) (%S+) port")
                    if close_user then
                        close_reason = "auth_fail"
                    end
                    if not close_user then
                        close_user, close_ip = line:match("Disconnected from user (%S+) (%S+) port")
                        if close_user then
                            close_reason = "disconnected"
                        end
                    end
                    if not close_user then
                        close_ip = line:match("Received disconnect from (%S+) port")
                        if close_ip then
                            close_reason = "user_disconnect"
                        end
                    end
                    if not close_user and not close_ip then
                        close_user = line:match("Connection closed by (%S+) port")
                        if close_user then
                            close_reason = "closed"
                        end
                    end
                    if not close_user and not close_ip then
                        close_ip = line:match("(%d+%.%d+%.%d+%.%d+).*port.*disconnect")
                        if close_ip then
                            close_reason = "disconnected"
                        end
                    end

                    if close_user or close_ip then
                        local entity = close_ip or close_user or "unknown"
                        local log_user = close_user or ""
                        local log_ip = close_ip or close_user or "unknown"
                        Watcher.log("ssh", "Close: " .. (log_user ~= "" and (log_user .. "@") or "") .. entity .. " (" .. (close_reason or "unknown") .. ")", close_reason == "auth_fail" and "warn" or "info")
                        engine:emit("on_ssh_close", log_user, log_ip, close_reason or "unknown")
                        goto continue
                    end

                    ::continue::
                end
            end

            coroutine.yield()
        end
    end
}
