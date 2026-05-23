return {
    name = "usb",
    interval = 5,
    enabled = function()
        return true
    end,
    start = function(engine)
        local Watcher = require("watcher")

        Watcher.log("usb", "USB watcher starting", "info")

        local mount_root = os.getenv("HOME") .. "/Mounts"
        os.execute("mkdir -p '" .. mount_root .. "'")
        Watcher.log("usb", "Mount root: " .. mount_root, "info")

        local function get_usb_parts()
            local raw = Watcher.run_cmd("lsblk -nlo NAME,RM,TYPE 2>/dev/null")
            local result = Watcher.run_cmd("lsblk -nlo NAME,RM,TYPE 2>/dev/null | awk '$2 ~ /^1$/ && $3 ~ /^part$/ {print $1}'")
            local parts = {}
            for part in result:gmatch("[^%s]+") do
                parts[part] = true
            end
            return parts
        end

        local last_usb = get_usb_parts()
        local dev_list = {}
        for d, _ in pairs(last_usb) do table.insert(dev_list, d) end
        Watcher.log("usb", "Initial USB state: " .. (#dev_list > 0 and table.concat(dev_list, ", ") or "no devices"), "info")

        local function process_changes()
            Watcher.reload_vars()
            local current = get_usb_parts()

            for dev, _ in pairs(current) do
                if not last_usb[dev] then
                    local dev_path = "/dev/" .. dev
                    local label = Watcher.run_cmd("lsblk -nlo LABEL '" .. dev_path .. "' 2>/dev/null"):gsub("%s+$", "")
                    if label == "" then label = "USB_" .. dev end
                    Watcher.log("usb", "New USB device: " .. dev .. " (label: " .. label .. ")", "info")

                    local actual_mount = Watcher.run_cmd("findmnt -nlo TARGET '" .. dev_path .. "' 2>/dev/null"):gsub("%s+$", "")
                    if actual_mount == "" then
                        Watcher.log("usb", "Not mounted, attempting mount via udisksctl...", "info")
                        local mount_out = Watcher.run_cmd("udisksctl mount -b '" .. dev_path .. "' --no-user-interaction 2>&1")
                        Watcher.log("usb", "udisksctl output: " .. mount_out, "info")
                        Watcher.sleep(1)
                        actual_mount = Watcher.run_cmd("findmnt -nlo TARGET '" .. dev_path .. "' 2>/dev/null"):gsub("%s+$", "")
                        if actual_mount ~= "" then
                            Watcher.log("usb", "Mount successful: " .. actual_mount, "info")
                        else
                            Watcher.log("usb", "Mount failed for " .. dev_path, "warn")
                        end
                    else
                        Watcher.log("usb", "Already mounted at: " .. actual_mount, "info")
                    end

                    if actual_mount ~= "" then
                        Watcher.log("usb", "Mounted at: " .. actual_mount, "info")
                        local symlink = mount_root .. "/" .. label
                        Watcher.run_cmd("ln -sfn '" .. actual_mount .. "' '" .. symlink .. "'")
                        Watcher.log("usb", "Symlink created: " .. symlink .. " -> " .. actual_mount, "info")

                        Watcher.reload_vars()
                        local ignore_list = Watcher.get_var("USB_IGNORE_DRIVES", "")
                        Watcher.log("usb", "Ignore list: [" .. ignore_list .. "]", "info")
                        local ignored = false
                        if ignore_list ~= "" and ignore_list ~= "null" then
                            for item in ignore_list:gmatch("[^|]+") do
                                Watcher.log("usb", "Checking ignore: '" .. item .. "' == '" .. label .. "'", "info")
                                if item == label then
                                    ignored = true
                                    Watcher.log("usb", "Drive '" .. label .. "' matched ignore list", "info")
                                    break
                                end
                            end
                        end

                        if not ignored then
                            Watcher.log("usb", "Emitting on_usb_connected: " .. label, "info")
                            engine:emit("on_usb_connected", label, symlink)
                        else
                            Watcher.log("usb", "Ignored drive: " .. label, "info")
                        end
                    else
                        Watcher.log("usb", "Mount failed for " .. dev_path, "warn")
                    end
                end
            end

            for dev, _ in pairs(last_usb) do
                if not current[dev] then
                    Watcher.log("usb", "USB removed: " .. dev, "info")
                    engine:emit("on_usb_disconnected", dev, mount_root)
                end
            end

            last_usb = current
        end

        process_changes()

        while true do
            process_changes()
            coroutine.yield()
        end
    end
}
