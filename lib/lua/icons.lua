local Icons = {}

function Icons.get_icon(name)
    name = string.lower(name or "")

    local retro_dir = os.getenv("RETRO_DIR") or "."
    local icon_dir = retro_dir .. "/icons"

    if name:match("xbox") and name:match("wireless") then
        return icon_dir .. "/xbox_wireless_controller.png"
    elseif name:match("nothing") and name:match("headphone") and name:match("1") then
        return icon_dir .. "/nothing_headphone_1.png"
    elseif name:match("nothing") and name:match("phone") and name:match("2") then
        return icon_dir .. "/nothing_phone_2.png"
    elseif name:match("nothing") and name:match("ear") then
        return icon_dir .. "/nothing_ear.png"
    elseif name:match("at") and name:match("over") and name:match("ear") then
        return icon_dir .. "/at_over_ear.png"
    else
        return "bluetooth"
    end
end

return Icons
