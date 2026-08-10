return {
    name = "bluetooth",
    interval = 1,
    enabled = function()
        local Bluetooth = require("bluetooth")
        return Bluetooth.has_bluetooth()
    end,
    start = function(engine)
        local Watcher = require("watcher")
        local Bluetooth = require("bluetooth")

        Watcher.log("bluetooth", "Bluetooth watcher started", "info")

        local last_connected = {}
        local last_profile_state = {}
        local function get_connected_macs()
            local macs = {}
            for _, mac in ipairs(Bluetooth.get_connected_devices()) do
                macs[mac] = true
            end
            return macs
        end

        local function apply_forced_profile(mac)
            local mac_key = mac:gsub(":", "_")
            local forced = Watcher.get_var("BT_FORCE_PROFILE_" .. mac_key, "")
            if forced == "" then
                Watcher.log("bluetooth", "No forced profile for " .. mac, "info")
                return false
            end
            local profile = forced:match("([^|]+)")
            local codec = forced:match("|(.+)")
            local card = Bluetooth.get_audio_card(mac)
            if not card or card == "" then
                Watcher.log("bluetooth", "No audio card for " .. mac .. " - skipping forced profile", "warn")
                return false
            end
            local current = Bluetooth.get_audio_profile(card)
            if current == profile then
                Watcher.log("bluetooth", "Forced profile already active on " .. mac .. ": " .. profile, "info")
                return false
            end
            Watcher.log("bluetooth", "Switching " .. mac .. " from " .. current .. " -> " .. profile, "info")
            local ok = Bluetooth.set_audio_profile(card, profile)
            if ok then
                local notify = Watcher.get_var("BT_NOTIFY_FORCE_PROFILE", "true")
                if notify == "true" then
                    local name = Bluetooth.get_device_name(mac)
                    local display = Bluetooth.get_profile_display_name(profile)
                    Watcher.log("bluetooth", "Sending notification: Forced " .. display .. " for " .. name, "info")
                    os.execute('notify-send -a "RetroLinux" -u normal -i "bluetooth-active-symbolic" "Profile Restored" "Forced ' .. display .. ' applied to ' .. name .. '" 2>/dev/null')
                end
                Watcher.log("bluetooth", "Forced profile applied to " .. mac .. ": " .. profile, "info")
                return true
            end
            Watcher.log("bluetooth", "Failed to apply forced profile " .. profile .. " to " .. mac, "warn")
            return false
        end

        last_connected = get_connected_macs()
        if next(last_connected) then
            for mac, _ in pairs(last_connected) do
                local info = Bluetooth.get_device_full_info(mac)
                Watcher.log("bluetooth", "Already connected: " .. info.name .. " (" .. mac .. ") [" .. info.category_label .. "]", "info")
                if info.audio_capable then
                    local card = Bluetooth.get_audio_card(mac)
                    if card and card ~= "" then
                        last_profile_state[mac] = Bluetooth.get_audio_profile(card)
                    end
                    Watcher.sleep(2)
                    apply_forced_profile(mac)
                end
            end
        else
            Watcher.log("bluetooth", "No connected devices", "info")
        end

        local tick = 0
        while true do
            local ignored_macs = Watcher.get_var("BT_MAC_IGNORE", "")
            local currently_pairing = Watcher.get_var("BT_PAIRING_IN_PROGRESS", "")

            local connected = get_connected_macs()
            for mac, _ in pairs(connected) do
                if not ignored_macs:find(mac, 1, true) and not currently_pairing:find(mac, 1, true) then
                    if not Bluetooth.is_paired(mac) then
                        local name = Bluetooth.get_device_name(mac)
                        Watcher.log("bluetooth", "Pairing request: " .. name .. " (" .. mac .. ")", "info")
                        engine:emit("on_bluetooth_pairing_request", name, mac)
                    end
                end
            end

            for mac, _ in pairs(connected) do
                if not last_connected[mac] then
                    if Bluetooth.is_paired(mac) then
                        local info = Bluetooth.get_device_full_info(mac)
                        Watcher.log("bluetooth", "Device connected: " .. info.name .. " (" .. mac .. ")", "info")
                        Watcher.log("bluetooth", "  Category: " .. info.category_label .. " | Audio: " .. tostring(info.audio_capable) .. " | Input: " .. tostring(info.input_capable), "info")
                        engine:emit("on_bluetooth_connected", info.name, mac)
                        if info.audio_capable then
                            Watcher.sleep(3)
                            local card = Bluetooth.get_audio_card(mac)
                            if card and card ~= "" then
                                local profile = Bluetooth.get_audio_profile(card)
                                local codec = Bluetooth.get_codec_from_profile(profile)
                                Watcher.log("bluetooth", "  Card: " .. card .. " | Profile: " .. profile .. " | Codec: " .. codec, "info")
                                last_profile_state[mac] = profile
                            else
                                Watcher.log("bluetooth", "  No audio card found for " .. mac, "warn")
                            end
                            apply_forced_profile(mac)
                        end
                    end
                end
            end

            for mac, _ in pairs(last_connected) do
                if not connected[mac] then
                    local name = Bluetooth.get_device_name(mac)
                    Watcher.log("bluetooth", "Device disconnected: " .. name .. " (" .. mac .. ")", "info")
                    engine:emit("on_bluetooth_disconnected", name, mac)
                    last_profile_state[mac] = nil
                end
            end

            tick = tick + 1
            if tick % 2 == 0 then
                for mac, _ in pairs(connected) do
                    local info = Bluetooth.get_device_full_info(mac)
                    if info.audio_capable then
                        local card = Bluetooth.get_audio_card(mac)
                        if card and card ~= "" then
                            local current_profile = Bluetooth.get_audio_profile(card)
                            local mac_key = mac:gsub(":", "_")
                            local forced = Watcher.get_var("BT_FORCE_PROFILE_" .. mac_key, "")
                            if forced ~= "" then
                                local forced_profile = forced:match("([^|]+)")
                                if current_profile ~= forced_profile then
                                    Watcher.log("bluetooth", "Profile drift on " .. info.name .. ": " .. current_profile .. " -> " .. forced_profile, "info")
                                    apply_forced_profile(mac)
                                    last_profile_state[mac] = forced_profile
                                end
                            else
                                local mic_disabled = Watcher.get_var("BT_MIC_DISABLED_" .. mac_key, "")
                                if mic_disabled == "true" and not current_profile:find("a2dp%-sink") then
                                    Watcher.log("bluetooth", "Mic disabled, switching " .. info.name .. " to a2dp-sink", "info")
                                    Bluetooth.set_audio_profile(card, "a2dp-sink")
                                end
                            end
                        end
                    end
                end
            end

            last_connected = connected
            coroutine.yield()
        end
    end
}
