local Watcher = require("watcher")

local Wallpaper = {}

local WALL_DIR = nil
local FRAME_CACHE = nil
local REPO_WALLS = nil

local function init_paths()
    if WALL_DIR then return end
    local retro_config = os.getenv("RETRO_CONFIG") or (os.getenv("HOME") .. "/.config/retro")
    local retro_dir = os.getenv("RETRO_DIR")
    WALL_DIR = retro_config .. "/wallpapers"
    FRAME_CACHE = retro_config .. "/wallpaper_frames"
    REPO_WALLS = retro_dir .. "/wallpapers"
    Watcher.run_cmd("mkdir -p '" .. FRAME_CACHE .. "' '" .. WALL_DIR .. "'")
end

local function generate_cache(target)
    init_paths()
    local filename = target:match("([^/]+)$")
    local output = FRAME_CACHE .. "/" .. filename .. ".png"

    if Watcher.run_cmd("test -f '" .. output .. "' && echo yes") ~= "yes" then
        if target:match("%.mp4$") or target:match("%.mkv$") or target:match("%.webm$") then
            Watcher.run_cmd("ffmpeg -i '" .. target .. "' -frames:v 1 '" .. output .. "' -y -loglevel quiet")
        else
            Watcher.run_cmd("ln -sf '" .. target .. "' '" .. output .. "'")
        end
    end
    return output
end

function Wallpaper.get_theme_dir()
    init_paths()
    local theme = Watcher.get_var("RETRO_THEME")
    if theme == "" or theme == "null" then theme = "retro" end

    local target = WALL_DIR .. "/" .. theme
    if Watcher.run_cmd("test -d '" .. target .. "' && echo yes") == "yes" then
        return target
    end
    return WALL_DIR
end

function Wallpaper.set_wallpaper(input_path, quick)
    init_paths()
    quick = quick or false
    local theme_dir = Wallpaper.get_theme_dir()
    local wall_path = ""

    if Watcher.run_cmd("test -f '" .. input_path .. "' && echo yes") == "yes" then
        wall_path = input_path
    elseif Watcher.run_cmd("test -f '" .. theme_dir .. "/" .. input_path .. "' && echo yes") == "yes" then
        wall_path = theme_dir .. "/" .. input_path
    elseif Watcher.run_cmd("test -f '" .. WALL_DIR .. "/" .. input_path .. "' && echo yes") == "yes" then
        wall_path = WALL_DIR .. "/" .. input_path
    else
        return false
    end

    local filename = wall_path:match("([^/]+)$")
    local base = filename:match("^(.+)%.")
    local ext = filename:match("%.([^.]+)$")
    local is_video = ext == "mp4" or ext == "mkv" or ext == "webm"

    local is_saver = Watcher.get_var("BAT_SAVER_ACTIVE", "false")
    local force_static = Watcher.get_var("WALL_STATIC_FORCED", "false")
    local static_on_bat = Watcher.get_var("WALL_STATIC_ON_BAT", "false")

    local should_be_static = false
    if is_saver == "true" or force_static == "true" then
        should_be_static = true
    elseif Watcher.run_cmd("grep -q 'Discharging' /sys/class/power_supply/BAT*/status 2>/dev/null && echo yes") == "yes" and static_on_bat == "true" then
        should_be_static = true
    end

    local is_first_load = Watcher.run_cmd("pgrep -x 'awww-daemon' >/dev/null 2>&1 && echo yes") ~= "yes"
    if is_first_load then
        Watcher.run_cmd("nohup awww-daemon >/dev/null 2>&1 &")
        local delay = 0.1
        for i = 1, 30 do
            Watcher.run_cmd("sleep " .. delay)
            if Watcher.run_cmd("awww query >/dev/null 2>&1 && echo yes") == "yes" then break end
            delay = delay * 1.5
        end
    end

    local static_source = wall_path
    if is_video then static_source = generate_cache(wall_path) end

    local current_wall = Watcher.get_var("WALL_CURRENT")
    local is_same_wall = current_wall == wall_path

    if is_first_load or quick then
        Watcher.run_cmd("awww img '" .. static_source .. "' --transition-type none")
    else
        local rand_x = math.random(0, 1920)
        local rand_y = math.random(0, 1080)
        Watcher.run_cmd(string.format("awww img '%s' --transition-type random --transition-duration 2.5 --transition-fps 120 --transition-pos '%d,%d'",
            static_source, rand_x, rand_y))
    end

    -- Background: pkill mpvpaper, matugen, video
    local bg_script = string.format([=[
pkill mpvpaper

if [[ '%s' != 'true' ]]; then
    color_cache='%s/%s.colors'
    scheme_type=""
    if [[ -f $color_cache ]]; then
        scheme_type=$(cat "$color_cache")
    else
        COLOR=$(magick '%s' -colorspace HSL -format "%%[fx:100*s]" info:)
        if [ "$(echo "$COLOR < 1.0" | bc)" -eq 1 ]; then
            scheme_type="monochrome"
        else
            scheme_type="vibrant"
        fi
        echo "$scheme_type" > "$color_cache"
    fi

    if [[ $scheme_type == "monochrome" ]]; then
        matugen image -b wal '%s' -t scheme-monochrome --fallback-color "#ffffff" --source-color-index 0 >/dev/null 2>&1
    else
        matugen image -b wal '%s' -t scheme-vibrant --source-color-index 0 >/dev/null 2>&1
    fi

    '%s/retro.sh' app all refresh >/dev/null 2>&1
fi
]=], is_same_wall, FRAME_CACHE, filename, static_source, static_source, static_source, os.getenv("RETRO_DIR"))

    if is_video and not should_be_static then
        if not is_first_load and not quick then
            bg_script = bg_script .. "\nsleep 2.2\n"
        end

        local res_map = Watcher.get_var("WALL_RES_MAP")
        local monitors = Watcher.run_cmd("hyprctl monitors -j | jq -r '.[] | \"\\(.name)|\\(.description)\"'")
        for line in monitors:gmatch("[^\n]+") do
            local m_name, m_desc = line:match("([^|]+)|([^|]+)")
            if m_name and m_desc then
                local custom_res = ""
                if res_map ~= "" and res_map ~= "null" then
                    for entry in res_map:gmatch("([^,]+)") do
                        local desc, res = entry:match("([^|]+)|([^|]+)")
                        if desc == m_desc then custom_res = res; break end
                    end
                end

                local target_video = wall_path
                if custom_res ~= "" then
                    local clean_base = base:gsub("%.[0-9]+x[0-9]+$", "")
                    local opt_file = theme_dir .. "/" .. clean_base .. "." .. custom_res .. "." .. ext
                    if Watcher.run_cmd("test -f '" .. opt_file .. "' && echo yes") == "yes" then
                        target_video = opt_file
                    end
                end

                bg_script = bg_script .. string.format("\nNV_PRIME_RENDER_OFFLOAD=0 nohup mpvpaper -o '--loop --panscan=1.0 --no-audio --hwdec=auto' '%s' '%s' >/dev/null 2>&1 &", m_name, target_video)
            end
        end
    end

    Watcher.run_cmd("bash -c '" .. bg_script:gsub("'", "'\\''") .. "' &")

    Watcher.set_var("WALL_CURRENT", wall_path)
    return true
end

function Wallpaper.restore_wallpaper(quick)
    local last_wall = Watcher.get_var("WALL_CURRENT")
    if last_wall ~= "" and last_wall ~= "null" and Watcher.run_cmd("test -f '" .. last_wall .. "' && echo yes") == "yes" then
        return Wallpaper.set_wallpaper(last_wall, quick or false)
    end
    return false
end

function Wallpaper.slideshow_next()
    init_paths()
    local target_dir = Wallpaper.get_theme_dir()
    local current = Watcher.get_var("WALL_CURRENT")

    local walls = Watcher.run_cmd("find '" .. target_dir .. "' -maxdepth 1 \\( -type f -o -type l \\) 2>/dev/null | grep -iE '\\.(png|jpg|jpeg|webp|gif|mp4|mkv|webm)$' | grep -vE '\\.[0-9]+x[0-9]+\\.(mp4|mkv|webm)$' | grep -vF '" .. current .. "' | shuf | head -1")

    if walls ~= "" then
        return Wallpaper.set_wallpaper(walls:gsub("%s+$", ""))
    end
    return false
end

function Wallpaper.static_wallpaper(action)
    local current = Watcher.get_var("WALL_STATIC_FORCED")
    local new_state = ""

    if action == "on" or action == "true" then
        new_state = "true"
    elseif action == "off" or action == "false" then
        new_state = "false"
    else
        new_state = current == "true" and "false" or "true"
    end

    Watcher.set_var("WALL_STATIC_FORCED", new_state)
    return Wallpaper.restore_wallpaper()
end

return Wallpaper
