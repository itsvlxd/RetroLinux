local Colors = require("colors")

local Help = {}

function Help.usage(usage)
    io.write(string.format("%s[ INFO]%s Usage: %s\n", Colors.PINK, Colors.RESET, usage))
    print()
end

function Help.commands(title)
    title = title or "Commands"
    io.write(string.format("%s %s%s%s:\n", Colors.PINK, Colors.RESET, title, Colors.GRAY))
end

function Help.cmd(cmd, desc, width)
    width = width or 26
    io.write(string.format(" %s%-" .. width .. "s%s- %s%s\n", Colors.PINK, cmd, Colors.GRAY, Colors.RESET, desc))
end

function Help.example(cmd, desc, width)
    width = width or 26
    io.write(string.format(" %s%-" .. width .. "s%s %s\n", Colors.GRAY, cmd, Colors.RESET, desc))
end

function Help.spacer()
    print()
end

function Help.examples()
    print()
    io.write(string.format("%s %sExamples%s:\n", Colors.PINK, Colors.RESET, Colors.GRAY))
end

function Help.section(icon, title)
    icon = icon or "󰇝"
    io.write(string.format(" %s%s %s%s%s:\n", Colors.PINK, icon, Colors.RESET, title, Colors.GRAY))
end

function Help.option(cmd, desc)
    io.write(string.format(" %s%-24s%s %s%s\n", Colors.PINK, cmd, Colors.GRAY, desc, Colors.RESET))
end

function Help.separator()
    io.write(string.format(" %s󰇝%s ───────────────────────────────────────%s\n", Colors.PINK, Colors.MUTE, Colors.RESET))
end

function Help.header(icon, title)
    print()
    io.write(string.format(" %s%s  %s%s\n", Colors.PINK, icon, title, Colors.RESET))
    Help.separator()
end

function Help.footer()
    Help.separator()
    print()
end

function Help.wrap(text, width)
    width = width or 50
    for line in text:gmatch("[^\n]+") do
        local pos = 1
        while pos <= #line do
            local chunk = line:sub(pos, pos + width - 1)
            io.write(string.format(" %s%s%s\n", Colors.GRAY, chunk, Colors.RESET))
            pos = pos + width
        end
    end
end

function Help.table_separator()
    io.write(string.format(" %s󰇝%s ───────────────────────────────────────%s\n", Colors.PINK, Colors.MUTE, Colors.RESET))
end

function Help.table_header(icon, title)
    print()
    io.write(string.format(" %s%s %s%s\n", Colors.PINK, icon, title, Colors.RESET))
    Help.table_separator()
end

function Help.table_row(icon, label, value, value_color, width)
    value_color = value_color or Colors.PINK
    width = width or 26
    io.write(string.format(" %s%s%s %-" .. width .. "s %s%s%s\n", Colors.PINK, icon, Colors.RESET, label, value_color, value, Colors.RESET))
end

function Help.table_row_gray(icon, label, value, width)
    width = width or 26
    io.write(string.format(" %s%s%s %-" .. width .. "s %s%s%s\n", Colors.PINK, icon, Colors.RESET, label, Colors.GRAY, value, Colors.RESET))
end

function Help.table_key_value(label, value, value_color, width)
    value_color = value_color or Colors.PINK
    width = width or 26
    io.write(string.format(" %s󰄾%s %-" .. width .. "s %s%s%s\n", Colors.PINK, Colors.RESET, label, value_color, value, Colors.RESET))
end

function Help.table_simple(icon, value, value_color)
    value_color = value_color or Colors.PINK
    io.write(string.format(" %s%s%s %s%s%s\n", Colors.PINK, icon, Colors.RESET, value_color, value, Colors.RESET))
end

function Help.table_spacer()
    print()
end

function Help.table_list_header(icon, col1, col2, col3)
    io.write(string.format(" %s%s%s %-30s %s%-12s%s %s%s\n", Colors.PINK, icon, Colors.RESET, col1, Colors.PINK, col2, Colors.RESET, col3 or "", Colors.RESET))
end

function Help.table_list_row(icon, col1, col2, col3, col1_color, col2_color, col3_color)
    col1_color = col1_color or Colors.PINK
    col2_color = col2_color or Colors.GRAY
    col3_color = col3_color or Colors.MUTE
    io.write(string.format(" %s%s%s %-30s %s%-12s%s %s%s%s\n", col1_color, icon, Colors.RESET, col1, col2_color, col2, Colors.RESET, col3_color, col3 or "", Colors.RESET))
end

function Help.table_list_single(icon, text, text_color)
    text_color = text_color or Colors.PINK
    io.write(string.format(" %s%s%s %s%s%s\n", Colors.PINK, icon, Colors.RESET, text_color, text, Colors.RESET))
end

function Help.confirm(message, default, skip)
    default = default or "N"
    skip = skip or false

    if skip then return true end

    if default == "Y" then
        io.write(string.format("%s[ INFO]%s %s %s[Y/n]%s: ", Colors.PINK, Colors.RESET, message, Colors.PINK, Colors.RESET))
    else
        io.write(string.format("%s[ INFO]%s %s %s[y/N]%s: ", Colors.PINK, Colors.RESET, message, Colors.PINK, Colors.RESET))
    end
    io.flush()

    local confirm = io.read("*l")
    if not confirm or confirm == "" then confirm = default end

    return confirm:match("^[Yy]$") ~= nil
end

function Help.yesno(message)
    local skip_prompt = os.getenv("SKIP_PROMPT")
    if skip_prompt == "true" then return true end

    io.write(string.format("%s[ INFO]%s %s %s[y/N]%s: ", Colors.PINK, Colors.RESET, message, Colors.PINK, Colors.RESET))
    io.flush()

    local result = io.read("*l")
    return result and result:match("^[Yy]$") ~= nil
end

return Help
