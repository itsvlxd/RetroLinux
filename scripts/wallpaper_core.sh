#!/bin/bash

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
        wall_path="$WALL_DIR/$input_path"
    else
        return 1
    fi

    local filename=$(basename "$wall_path")
    local engine=$(get_var "CLR_ENGINE")
    local is_saver=$(get_var "BAT_SAVER_ACTIVE")
    local force_static=$(get_var "WALL_STATIC_FORCED")
    local static_on_bat=$(get_var "WALL_STATIC_ON_BAT")
    local on_bat=$(is_on_battery)

    : ${engine:="matugen"}
    : ${is_saver:="false"}
    : ${force_static:="false"}
    : ${static_on_bat:="false"}

    local is_video=false
    [[ $filename =~ \.(mp4|mkv|webm)$ ]] && is_video=true

    local should_be_static=false
    if [[ $is_saver == "true" ]]; then
        should_be_static=true
    elif [[ $force_static == "true" ]]; then
        should_be_static=true
    elif [[ $on_bat == "true" && $static_on_bat == "true" ]]; then
        should_be_static=true
    fi

    local color_source=$(generate_cache "$wall_path")

    if [[ $engine == "matugen" ]]; then
        matugen image -b wal "$color_source" --source-color-index 0
    else
        wal -i "$color_source" -n -q -e
    fi

    pkill mpvpaper

    if [[ $is_video == "true" ]]; then
        if [[ $should_be_static == "true" ]]; then
            awww img "$color_source" --transition-type fade --transition-duration 0
        else
            pgrep -x "awww-daemon" >/dev/null || awww-daemon &
            awww img "$color_source" --transition-type grow --transition-duration 2.5 --transition-fps 120

            sleep 2.2
            NV_PRIME_RENDER_OFFLOAD=0 mpvpaper -o "--loop --hwdec=vaapi --panscan=1.0 --no-audio" "*" "$wall_path" &
        fi
    else
        awww img "$wall_path" --transition-type grow --transition-duration 2.5 --transition-fps 120
    fi

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
