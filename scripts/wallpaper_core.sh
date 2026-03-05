#!/bin/bash

VAR_SCRIPT="$RETRO_DIR/scripts/variable_core.sh"
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
    local engine=$(bash "$VAR_SCRIPT" get "CLR_ENGINE")
    local is_saver=$(bash "$VAR_SCRIPT" get "BAT_SAVER_ACTIVE")

    : ${engine:="matugen"}
    : ${is_saver:="false"}

    local is_video=false
    [[ $filename =~ \.(mp4|mkv|webm)$ ]] && is_video=true

    local color_source=$(generate_cache "$wall_path")

    if [[ $engine == "matugen" ]]; then
        matugen image "$color_source" --source-color-index 0
    else
        wal -i "$color_source" -n -q -e
    fi

    pkill mpvpaper

    if [[ $is_video == "true" ]]; then
        if [[ $is_saver == "true" ]]; then
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

    bash "$VAR_SCRIPT" set "WALL_CURRENT" "$wall_path"
}

restore_wallpaper() {
    local last_wall=$(bash "$VAR_SCRIPT" get "WALL_CURRENT")
    if [[ -n $last_wall && -f $last_wall ]]; then
        set_wallpaper "$last_wall"
    else
        return 1
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
    "--list")
        ls -1 "$WALL_DIR"
        ;;
    "--picker")
        selected=$(ls "$WALL_DIR" | rofi -dmenu -p "󰸉 Wallpapers")
        [[ -n $selected ]] && set_wallpaper "$selected"
        ;;
esac
