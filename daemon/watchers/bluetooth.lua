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
        local log = function(msg) Watcher.log("bluetooth", msg) end

        log("Bluetooth watcher started")

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
                log("No forced profile for " .. mac)
                return false
            end
            local profile = forced:match("([^|]+)")
            local codec = forced:match("|(.+)")
            local card = Bluetooth.get_audio_card(mac)
            if not card or card == "" then
                log("No audio card for " .. mac .. " - skipping forced profile")
                return false
            end
            local current = Bluetooth.get_audio_profile(card)
            if current == profile then
                log("Forced profile already active on " .. mac .. ": " .. profile)
                return false
            end
            log("Switching " .. mac .. " from " .. current .. " -> " .. profile)
            local ok = Bluetooth.set_audio_profile(card, profile)
            if ok then
                local notify = Watcher.get_var("BT_NOTIFY_FORCE_PROFILE", "true")
                if notify == "true" then
                    local name = Bluetooth.get_device_name(mac)
                    local display = Bluetooth.get_profile_display_name(profile)
                    log("Sending notification: Forced " .. display .. " for " .. name)
                    os.execute('notify-send -a "RetroBT" -u normal -i "bluetooth-active-symbolic" "Profile Restored" "Forced ' .. display .. ' applied to ' .. name .. '" 2>/dev/null')
                end
                log("Forced profile applied to " .. mac .. ": " .. profile)
                return true
            end
            log("Failed to apply forced profile " .. profile .. " to " .. mac)
            return false
        end

        last_connected = get_connected_macs()
        if next(last_connected) then
            for mac, _ in pairs(last_connected) do
                local info = Bluetooth.get_device_full_info(mac)
                log("Already connected: " .. info.name .. " (" .. mac .. ") [" .. info.category_label .. "]")
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
                        log("Device connected: " .. info.name .. " (" .. mac .. ")")
                        log("  Category: " .. info.category_label .. " | Audio: " .. tostring(info.audio_capable) .. " | Input: " .. tostring(info.input_capable))
                        engine:emit("on_bluetooth_connected", info.name, mac)
                        if info.audio_capable then
                            Watcher.sleep(3)
                            local card = Bluetooth.get_audio_card(mac)
                            if card and card ~= "" then
                                local profile = Bluetooth.get_audio_profile(card)
                                local codec = Bluetooth.get_codec_from_profile(profile)
                                log("  Card: " .. card .. " | Profile: " .. profile .. " | Codec: " .. codec)
                                last_profile_state[mac] = profile
                            else
                                log("  No audio card found for " .. mac)
                            end
                            apply_forced_profile(mac)
                        end
                    end
                end
            end

            for mac, _ in pairs(last_connected) do
                if not connected[mac] then
                    local name = Bluetooth.get_device_name(mac)
                    log("Device disconnected: " .. name .. " (" .. mac .. ")")
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
                                    log("Profile drift on " .. info.name .. ": " .. current_profile .. " -> " .. forced_profile)
                                    apply_forced_profile(mac)
                                    last_profile_state[mac] = forced_profile
                                end
                            else
                                local mic_disabled = Watcher.get_var("BT_MIC_DISABLED_" .. mac_key, "")
                                if mic_disabled == "true" and not current_profile:find("a2dp%-sink") then
                                    log("Mic disabled, switching " .. info.name .. " to a2dp-sink")
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
