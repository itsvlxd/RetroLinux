#!/bin/bash

# TODO: Add a option to cache reset so it deleted the wallpapers saved in cache and
# the cache of the wallpaper frames to generate new ones
#
# TODO: also add a command to add a wallpaper inside the wallpaper menu
# TODO: add slideshow mode

source "$RETRO_DIR/lib/helpers.sh"

source "$RETRO_DIR/scripts/lib/battery.sh"
source "$RETRO_DIR/scripts/lib/variable.sh"

WALL_DIR="$HOME/.cache/retro/wallpapers"
FRAME_CACHE="$HOME/.cache/retro/wallpaper_frames"

mkdir -p "$FRAME_CACHE"

# TODO: add a option and a variable on what resolution to run the wallpaper
# because I want to grab also 4k resolution wallpapers so i can
# make mpv run them at a lower scale
#
# TODO: also add more wallpapers from https://motionbgs.com and https://wallpapercave.com/retro-synthwave-wallpapers

generate_cache() {
    local target="$1"
    [[ -z $target ]] && return 1

    local filename=$(basename "$target")
    local output="$FRAME_CACHE/${filename}.png"

    if [[ ! -f $output ]]; then
        if [[ $target =~ \.(mp4|mkv|webm)$ ]]; then
            ffmpeg -i "$target" -frames:v 1 "$output" -y -loglevel quiet
        else
            ln -sf "$target" "$output"
        fi
    fi
    echo "$output"
}

set_wallpaper() {
    local input_path="$1"
    local wall_path=""

    if [[ -f $input_path ]]; then
        wall_path="$input_path"
    elif [[ -f "$WALL_DIR/$input_path" ]]; then
        wall_path="$WALL_DIR/$input_path"
    else
        return 1
    fi

    local filename=$(basename "$wall_path")
    local is_video=false
    [[ $filename =~ \.(mp4|mkv|webm)$ ]] && is_video=true

    local is_saver=$(get_var "BAT_SAVER_ACTIVE" "false")
    local force_static=$(get_var "WALL_STATIC_FORCED" "false")
    local static_on_bat=$(get_var "WALL_STATIC_ON_BAT" "false")
    local on_bat=$(is_on_battery)

    local should_be_static=false
    if [[ $is_saver == "true" || $force_static == "true" ]]; then
        should_be_static=true
    elif [[ $on_bat == "true" && $static_on_bat == "true" ]]; then
        should_be_static=true
    fi

    local is_first_load=false
    if ! pgrep -x "awww-daemon" >/dev/null; then
        is_first_load=true
        nohup awww-daemon >/dev/null 2>&1 &
        while ! awww query >/dev/null 2>&1; do sleep 0.05; done
    fi

    local static_source="$wall_path"
    [[ $is_video == "true" ]] && static_source=$(generate_cache "$wall_path")

    if [[ $is_first_load == "true" ]]; then
        awww img "$static_source" --transition-type none
    else
        local rand_x=$((RANDOM % 1920))
        local rand_y=$((RANDOM % 1080))

        # TODO: Make sure the fps is being synced with the current from from the monitor
        # remember that on battery should be more aggresive on the refreshrate

        awww img "$static_source" \
            --transition-type grow \
            --transition-duration 2.5 \
            --transition-fps 120 \
            --transition-pos "$rand_x,$rand_y"
    fi

    (
        pkill mpvpaper

        COLOR=$(magick "$static_source" -colorspace HSL -format "%[fx:100*s]" info:)

        if [ "$(echo "$COLOR < 1.0" | bc)" -eq 1 ]; then
            matugen image -b wal "$static_source" -t scheme-monochrome --fallback-color "#ffffff" --source-color-index 0 >/dev/null 2>&1
        else
            matugen image -b wal "$static_source" --source-color-index 0 >/dev/null 2>&1
        fi

        if [[ $is_video == "true" && $should_be_static == "false" ]]; then
            [[ $is_first_load == "false" ]] && sleep 2.2

            NV_PRIME_RENDER_OFFLOAD=0 mpvpaper -o "--loop --hwdec=vaapi --panscan=1.0 --no-audio" "*" "$wall_path" &
            disown
        fi
    ) &

    set_var "WALL_CURRENT" "$wall_path"
}

restore_wallpaper() {
    local last_wall=$(get_var "WALL_CURRENT")
    if [[ -n $last_wall && -f $last_wall ]]; then
        set_wallpaper "$last_wall"
    else
        return 1
    fi
}

static_wallpaper() {
    local current_state=$(get_var "WALL_STATIC_FORCED")
    local new_state=""

    case "$2" in
        "on" | "true") new_state="true" ;;
        "off" | "false") new_state="false" ;;
        "toggle" | *) [[ $current_state == "true" ]] && new_state="false" || new_state="true" ;;
    esac

    set_var "WALL_STATIC_FORCED" "$new_state"
    restore_wallpaper
}

launch_picker() {
    local theme="$HOME/.config/rofi/themes/gallery.rasi"
    local list=""

    declare -A wall_map

    while IFS= read -r f; do
        [[ -z $f ]] && continue

        local filename=$(basename "$f")
        local display=$(rx_format_string "$filename")
        local thumb=$(generate_cache "$f")

        wall_map["$display"]="$filename"

        list+="${display}\0icon\x1f${thumb}\n"
    done < <(ls "$WALL_DIR")

    local alpha=$(get_opacity_hex "0.9")
    local alpha_alt=$(get_opacity_hex "0.6")
    local base_bg=$(grep "background:" ~/.cache/retro/themes/rofi-colors.rasi | awk '{print $2}' | sed 's/[#;FF]//g')
    local base_bg_alt=$(grep "background-alt:" ~/.cache/retro/themes/rofi-colors.rasi | awk '{print $2}' | sed 's/[#;FF]//g')

    local choice=$(echo -en "$list" | rofi -dmenu -i -p "󰸉 Wallpapers" -theme "$theme" -theme-str "
                window { background-color: #${base_bg}${alpha}; } 
                inputbar { background-color: #${base_bg}${alpha}; }  
                element selected.normal { background-color: #${base_bg_alt}${alpha_alt}; }
            ")

    if [[ -n $choice ]]; then
        local actual_file="${wall_map[$choice]}"

        if [[ -n $actual_file ]]; then
            set_wallpaper "$actual_file"
        fi
    fi
}

case "$1" in
    "--set")
        set_wallpaper "$2"
        ;;

    "--cache")
        if [[ -n $2 ]]; then
            generate_cache "$2" >/dev/null
        else
            for f in "$WALL_DIR"/*; do
                [[ -f $f ]] && generate_cache "$f" >/dev/null
            done
        fi
        ;;

    "--restore")
        restore_wallpaper
        ;;

    "--static")
        static_wallpaper "$2"
        ;;

    "--list")
        ls -1 "$WALL_DIR"
        ;;

    "--picker")
        launch_picker
        ;;
esac
