local Format = {}

function Format.uptime(total_seconds)
    if not total_seconds or total_seconds < 60 then
        return "Just now"
    end

    local minutes = math.floor(total_seconds / 60)
    local hours = math.floor(minutes / 60)
    local days = math.floor(hours / 24)
    local weeks = math.floor(days / 7)
    local months = math.floor(weeks / 4)

    minutes = minutes % 60
    hours = hours % 24
    days = days % 7
    weeks = weeks % 4

    local parts = {}
    if months > 0 then table.insert(parts, months .. " months") end
    if weeks > 0 then table.insert(parts, weeks .. " weeks") end
    if days > 0 then table.insert(parts, days .. " days") end
    if hours > 0 then table.insert(parts, hours .. " hours") end
    if minutes > 0 then table.insert(parts, minutes .. " min") end

    return table.concat(parts, " ")
end

return Format
