return {
    name = "bluetooth",
    interval = 2,
    enabled = function()
        local Bluetooth = require("bluetooth")
        return Bluetooth.has_bluetooth()
    end,
    start = function(engine)
        local Watcher = require("watcher")
        local Bluetooth = require("bluetooth")
        local log = function(msg) Watcher.log("bluetooth", msg) end

        log("Bluetooth watcher started")

        local last_connected = {}
        local function get_connected_macs()
            local macs = {}
            for _, mac in ipairs(Bluetooth.get_connected_devices()) do
                macs[mac] = true
            end
            return macs
        end

        last_connected = get_connected_macs()
        if next(last_connected) then
            for mac, _ in pairs(last_connected) do
                local info = Bluetooth.get_device_full_info(mac)
                log("Already connected: " .. info.name .. " (" .. mac .. ") [" .. info.category_label .. "]")
            end
        else
            log("No connected devices")
        end

        local tick = 0
        while true do
            Watcher.reload_vars()
            local ignored_macs = Watcher.get_var("BT_MAC_IGNORE", "")
            local currently_pairing = Watcher.get_var("BT_PAIRING_IN_PROGRESS", "")

            local connected = get_connected_macs()
            for mac, _ in pairs(connected) do
                if not ignored_macs:find(mac, 1, true) and not currently_pairing:find(mac, 1, true) then
                    if not Bluetooth.is_paired(mac) then
                        local name = Bluetooth.get_device_name(mac)
                        log("Pairing request: " .. name .. " (" .. mac .. ")")
                        engine:emit("on_bluetooth_pairing_request", name, mac)
                    end
                end
            end

            for mac, _ in pairs(connected) do
                if not last_connected[mac] then
                    if Bluetooth.is_paired(mac) then
                        local info = Bluetooth.get_device_full_info(mac)
                        log("Device connected: " .. info.name .. " (" .. mac .. ") [" .. info.category_label .. "]")
                        engine:emit("on_bluetooth_connected", info.name, mac)
                    end
                end
            end

            for mac, _ in pairs(last_connected) do
                if not connected[mac] then
                    local name = Bluetooth.get_device_name(mac)
                    log("Device disconnected: " .. name .. " (" .. mac .. ")")
                    engine:emit("on_bluetooth_disconnected", name, mac)
                end
            end

            last_connected = connected
            tick = tick + 1
            coroutine.yield()
        end
    end
}
