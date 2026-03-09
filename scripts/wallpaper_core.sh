#!/bin/bash

# TODO: Add a option to cache reset so it deleted the wallpapers saved in cache and
# the cache of the wallpaper frames to generate new ones
#
# also add a command to add a wallpaper inside the wallpaper menu

source "$RETRO_DIR/scripts/lib/battery.sh"
source "$RETRO_DIR/scripts/lib/variable.sh"

WALL_DIR="$HOME/.cache/retro/wallpapers"
FRAME_CACHE="$HOME/.cache/retro/wallpaper_frames"

mkdir -p "$FRAME_CACHE"

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
        wall_path="$wall_path"
    else
        return 1
    fi

    local filename=$(basename "$wall_path")
    local is_video=false
    [[ $filename =~ \.(mp4|mkv|webm)$ ]] && is_video=true

    local is_first_load=false
    if ! pgrep -x "awww-daemon" >/dev/null; then
        is_first_load=true
        nohup awww-daemon >/dev/null 2>&1 &
        sleep 0.1
    fi

    local static_source="$wall_path"
    if [[ $is_video == "true" ]]; then
        static_source=$(generate_cache "$wall_path")
    fi

    if [[ $is_first_load == "true" ]]; then
        awww img "$static_source" --transition-type fade --transition-duration 0
    else
        awww img "$static_source" --transition-type grow --transition-duration 2.5 --transition-fps 120
    fi

    (
        matugen image -b wal "$static_source" --source-color-index 0 >/dev/null 2>&1

        if [[ $is_video == "true" ]]; then
            local is_saver=$(get_var "BAT_SAVER_ACTIVE" "false")
            local force_static=$(get_var "WALL_STATIC_FORCED" "false")
            local static_on_bat=$(get_var "WALL_STATIC_ON_BAT" "false")
            local on_bat=$(is_on_battery)

            if [[ $is_saver == "false" && $force_static == "false" ]]; then
                if [[ $on_bat == "false" || $static_on_bat == "false" ]]; then
                    pkill mpvpaper
                    [[ $is_first_load == "false" ]] && sleep 2.2

                    NV_PRIME_RENDER_OFFLOAD=0 mpvpaper -o "--loop --hwdec=vaapi --panscan=1.0 --no-audio" "*" "$wall_path" &
                fi
            fi
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
        selected=$(ls "$WALL_DIR" | rofi -dmenu -p "󰸉 Wallpapers")
        [[ -n $selected ]] && set_wallpaper "$selected"
        ;;
esac
