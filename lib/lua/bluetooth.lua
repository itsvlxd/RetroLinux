local Bluetooth = {}

local BT_ADAPTER_PATH = "/sys/class/bluetooth/hci0"

local function run_cmd(cmd)
    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then return "" end
    local result = handle:read("*a")
    handle:close()
    return result:gsub("%s+$", "")
end

function Bluetooth.has_bluetooth()
    local f = io.open(BT_ADAPTER_PATH, "r")
    if f then f:close(); return true end
    return false
end

function Bluetooth.get_connected_devices()
    local result = run_cmd("bluetoothctl devices Connected 2>/dev/null | awk '{print $2}'")
    local macs = {}
    for mac in result:gmatch("[^%s]+") do
        table.insert(macs, mac)
    end
    return macs
end

function Bluetooth.get_device_name(mac)
    if not mac or mac == "" then return "Unknown" end
    local info = run_cmd("bluetoothctl info " .. mac .. " 2>/dev/null")
    local name = info:match("Name:%s*([^\n]+)")
    if not name then
        name = info:match("Alias:%s*([^\n]+)")
    end
    if name then name = name:gsub("^%s*(.-)%s*$", "%1") end
    return name or "Unknown Device"
end

function Bluetooth.is_paired(mac)
    if not mac or mac == "" then return false end
    local info = run_cmd("bluetoothctl info " .. mac .. " 2>/dev/null")
    return info:find("Paired:%s*yes") ~= nil
end

function Bluetooth.is_connected(mac)
    if not mac or mac == "" then return false end
    local info = run_cmd("bluetoothctl info " .. mac .. " 2>/dev/null")
    return info:find("Connected:%s*yes") ~= nil
end

function Bluetooth.get_device_uuids(mac)
    if not mac or mac == "" then return {} end
    local info = run_cmd("bluetoothctl info " .. mac .. " 2>/dev/null")
    local uuids = {}
    for uuid in info:gmatch("UUID:.- %(([%x%-]+)%)") do
        table.insert(uuids, uuid:lower())
    end
    return uuids
end

function Bluetooth.get_device_class(mac)
    if not mac or mac == "" then return 0, 0, 0 end
    local info = run_cmd("bluetoothctl info " .. mac .. " 2>/dev/null")
    local class_hex = info:match("Class:%s*0x([%x]+)")
    if not class_hex then
        class_hex = info:match("Class:%s*([%x]+)")
    end
    if not class_hex then return 0, 0, 0 end
    local class_dec = tonumber(class_hex, 16) or 0
    local major = math.floor(class_dec / 256) % 32
    local minor = math.floor(class_dec / 4) % 64
    return class_dec, major, minor
end

function Bluetooth.get_device_icon(mac)
    if not mac or mac == "" then return "" end
    local info = run_cmd("bluetoothctl info " .. mac .. " 2>/dev/null")
    local icon = info:match("Icon:%s*([^\n]+)")
    if icon then icon = icon:gsub("^%s*(.-)%s*$", "%1") end
    return icon or ""
end

function Bluetooth.is_audio_capable(mac)
    local uuids = Bluetooth.get_device_uuids(mac)
    local audio_uuids = {"0000110b", "0000110a", "00001108", "0000111e", "0000111f"}
    for _, uuid in ipairs(uuids) do
        for _, audio_uuid in ipairs(audio_uuids) do
            if uuid:sub(1, #audio_uuid) == audio_uuid then return true end
        end
    end
    return false
end

function Bluetooth.is_input_capable(mac)
    local uuids = Bluetooth.get_device_uuids(mac)
    local input_uuids = {"00001124", "00001126", "00001812", "00001813", "00001816", "00001805", "00001806", "0000180a"}
    for _, uuid in ipairs(uuids) do
        for _, input_uuid in ipairs(input_uuids) do
            if uuid:sub(1, #input_uuid) == input_uuid then return true end
        end
    end
    return false
end

function Bluetooth.is_phone(mac)
    local uuids = Bluetooth.get_device_uuids(mac)
    local phone_uuids = {"0000112f", "0000112d", "00001132"}
    for _, uuid in ipairs(uuids) do
        for _, phone_uuid in ipairs(phone_uuids) do
            if uuid:sub(1, #phone_uuid) == phone_uuid then return true end
        end
    end
    return false
end

function Bluetooth.is_computer(mac)
    local _, major = Bluetooth.get_device_class(mac)
    return major == 1
end

function Bluetooth.is_gamepad(mac)
    local icon = Bluetooth.get_device_icon(mac)
    if icon:find("gamepad") or icon:find("input%-gaming") or icon:find("joystick") then
        return true
    end
    local _, major, minor = Bluetooth.get_device_class(mac)
    return major == 5 and minor >= 1 and minor <= 15
end

function Bluetooth.get_device_category(mac)
    if not mac or mac == "" then return "other" end
    if Bluetooth.is_phone(mac) then return "phone" end
    if Bluetooth.is_computer(mac) then return "computer" end
    if Bluetooth.is_gamepad(mac) then return "controller" end
    local is_audio = Bluetooth.is_audio_capable(mac)
    local is_input = Bluetooth.is_input_capable(mac)
    if is_audio and is_input then return "audio+input" end
    if is_audio then return "audio" end
    if is_input then return "input" end
    return "other"
end

local DEVICE_ICONS = {
    ["phone"] = " ",
    ["computer"] = "󰍹 ",
    ["audio"] = "󰋋 ",
    ["audio+input"] = "󰋎 ",
    ["controller"] = "󰖺 ",
    ["input-keyboard"] = "󰌌 ",
    ["input-mouse"] = "󰍽 ",
    ["input-audio"] = " ",
    ["input"] = "󰕓 ",
    ["other"] = "󰦔 ",
}

local DEVICE_LABELS = {
    ["phone"] = "PHONE",
    ["computer"] = "PC",
    ["audio"] = "AUDIO",
    ["audio+input"] = "AUDIO+INPUT",
    ["controller"] = "CONTROLLER",
    ["input-keyboard"] = "KEYBOARD",
    ["input-mouse"] = "MOUSE",
    ["input-audio"] = "INPUT AUDIO",
    ["input"] = "INPUT",
    ["other"] = "OTHER",
}

function Bluetooth.get_category_icon(category)
    return DEVICE_ICONS[category] or DEVICE_ICONS["other"]
end

function Bluetooth.get_category_label(category)
    return DEVICE_LABELS[category] or DEVICE_LABELS["other"]
end

function Bluetooth.can_send_file(mac)
    return Bluetooth.is_phone(mac) or Bluetooth.is_computer(mac)
end

function Bluetooth.get_audio_card(mac)
    if not mac or mac == "" then return "" end
    local mac_us = mac:gsub(":", "_")
    local result = run_cmd("pactl list cards short 2>/dev/null | awk '{print $2}' | grep -i '" .. mac_us .. "' | head -1")
    return result
end

function Bluetooth.get_audio_profile(card)
    if not card or card == "" then return "" end
    local result = run_cmd("pactl list cards 2>/dev/null | sed -n '/Name: .*" .. card .. "/,/Ports:/p' | grep 'Active Profile:' | awk '{print $3}' | tr -d '\\n' | xargs")
    return result
end

function Bluetooth.get_audio_codec(card)
    local profile = Bluetooth.get_audio_profile(card)
    return Bluetooth.get_codec_from_profile(profile)
end

function Bluetooth.get_codec_from_profile(profile)
    if not profile or profile == "" then return "unknown" end
    if profile:find("sbc_xq") then return "SBC-XQ" end
    if profile:find("msbc") then return "MSBC" end
    if profile:find("cvsd") then return "CVSD" end
    if profile:find("ldac") then return "LDAC" end
    if profile:find("aptx%-hd") or profile:find("aptx_hd") then return "aptX HD" end
    if profile:find("aptx") then return "aptX" end
    if profile:find("aac") then return "AAC" end
    if profile:find("opus") then return "Opus" end
    if profile:find("sbc") then return "SBC" end
    if profile:find("headset") then return "MSBC" end
    if profile:find("a2dp") then return "SBC" end
    if profile:find("off") then return "off" end
    return profile
end

function Bluetooth.get_profile_display_name(profile)
    if not profile or profile == "" then return profile end
    if profile:find("a2dp%-sink.*aac") then return "High Fidelity Playback (A2DP Sink, codec AAC)" end
    if profile:find("a2dp%-sink.*ldac") then return "High Fidelity Playback (A2DP Sink, codec LDAC)" end
    if profile:find("a2dp%-sink.*aptx%-hd") or profile:find("a2dp%-sink.*aptx_hd") then return "High Fidelity Playback (A2DP Sink, codec aptX HD)" end
    if profile:find("a2dp%-sink.*aptx") then return "High Fidelity Playback (A2DP Sink, codec aptX)" end
    if profile:find("a2dp%-sink.*opus") then return "High Fidelity Playback (A2DP Sink, codec Opus)" end
    if profile:find("a2dp%-sink.*sbc_xq") then return "High Fidelity Playback (A2DP Sink, codec SBC-XQ)" end
    if profile:find("a2dp%-sink.*sbc") then return "High Fidelity Playback (A2DP Sink, codec SBC)" end
    if profile:find("a2dp%-sink") then return "High Fidelity Playback (A2DP Sink)" end
    if profile:find("headset%-head%-unit.*msbc") then return "Headset Head Unit (HSP/HFP, codec MSBC)" end
    if profile:find("headset%-head%-unit%-cvsd") then return "Headset Head Unit (HSP/HFP, codec CVSD)" end
    if profile:find("headset%-head%-unit") then return "Headset Head Unit (HSP/HFP)" end
    if profile:find("off") then return "Off" end
    return profile
end

function Bluetooth.get_codec_display_name(codec)
    if not codec or codec == "" then return "unknown" end
    local names = {
        sbc = "SBC", sbc_xq = "SBC-XQ", aac = "AAC", ldac = "LDAC",
        aptx = "aptX", aptx_hd = "aptX HD", opus = "Opus",
        cvsd = "CVSD", msbc = "MSBC",
    }
    return names[codec] or codec
end

function Bluetooth.set_audio_profile(card, profile)
    if not card or not profile then return false end
    local result = run_cmd("pactl set-card-profile '" .. card .. "' '" .. profile .. "' 2>/dev/null && echo OK || echo ERR")
    return result == "OK"
end

function Bluetooth.is_scanning()
    local result = run_cmd("bluetoothctl show 2>/dev/null | grep -i 'Discovering:' | awk '{print $2}'")
    return result == "yes"
end

function Bluetooth.get_nearby_devices()
    local is_scanning = Bluetooth.is_scanning()
    if not is_scanning then return {} end

    local paired = {}
    local paired_raw = run_cmd("bluetoothctl devices Paired 2>/dev/null | awk '{print $2}'")
    for mac in paired_raw:gmatch("[^%s]+") do
        paired[mac] = true
    end

    local devices = {}
    local all_raw = run_cmd("bluetoothctl devices 2>/dev/null")
    for line in all_raw:gmatch("[^\n]+") do
        local mac = line:match("%S+%s+(%S+)")
        if mac and not paired[mac] then
            table.insert(devices, { mac = mac, line = line })
        end
    end
    return devices
end

function Bluetooth.get_device_icon_path(name)
    if not name or name == "" then return "bluetooth-active" end
    local retro_dir = os.getenv("RETRO_DIR") or "/home/vlad/.essentials/retro-arch"
    local icon_dir = retro_dir .. "/icons"
    local n = name:lower()

    local icon_map = {
        { pattern = "xbox.*wireless", file = "xbox_wireless_controller.png" },
        { pattern = "nothing.*headphone.*1", file = "nothing_headphone_1.png" },
        { pattern = "nothing.*phone.*2", file = "nothing_phone_2.png" },
        { pattern = "nothing.*ear", file = "nothing_ear.png" },
        { pattern = "at.*over.*ear", file = "at_over_ear.png" },
    }

    for _, entry in ipairs(icon_map) do
        if n:match(entry.pattern) then
            local full_path = icon_dir .. "/" .. entry.file
            local f = io.open(full_path, "r")
            if f then f:close(); return full_path end
        end
    end
    return "bluetooth-active"
end

function Bluetooth.get_device_full_info(mac)
    if not mac or mac == "" then return nil end
    local name = Bluetooth.get_device_name(mac)
    local category = Bluetooth.get_device_category(mac)
    local paired = Bluetooth.is_paired(mac)
    local connected = Bluetooth.is_connected(mac)
    local icon = Bluetooth.get_device_icon(mac)
    local class_dec, major, minor = Bluetooth.get_device_class(mac)

    return {
        mac = mac,
        name = name,
        category = category,
        category_icon = Bluetooth.get_category_icon(category),
        category_label = Bluetooth.get_category_label(category),
        paired = paired,
        connected = connected,
        icon = icon,
        class = string.format("0x%06X", class_dec),
        major_class = major,
        minor_class = minor,
        audio_capable = Bluetooth.is_audio_capable(mac),
        input_capable = Bluetooth.is_input_capable(mac),
        is_phone = Bluetooth.is_phone(mac),
        is_computer = Bluetooth.is_computer(mac),
        is_gamepad = Bluetooth.is_gamepad(mac),
        can_send_file = Bluetooth.can_send_file(mac),
    }
end

return Bluetooth
