#!/bin/bash

VARS="$HOME/.config/hypr/scripts/vars.sh"

DEBUG=true
VIDEO_TRANSITION=true
BATTERY_SAVER=$($VARS get battery_saver)
COLOR_ENGINE=$($VARS get color_engine)

WALL_DIR="$HOME/.config/hypr/wallpapers"
THEME_FILE="$HOME/.config/hypr/colors.conf"
STATE_FILE="$HOME/.cache/retro/last_wallpaper"
FRAME_CACHE="$HOME/.cache/retro/wallpaper_frames"
CACHE_SCRIPT="$HOME/.config/hypr/scripts/cache-frames.sh"
HYPRLAND_THEME="$HOME/.cache/retro/themes/hyprland-colors.conf"
ROFI_THEME="$HOME/.config/rofi/wallpaper-gallery.rasi"

debug_log() {
    [ "$DEBUG" = true ] && echo -e "\e[34m[DEBUG $(date +'%H:%M:%S')]\e[0m $1"
}

if [ -n "$1" ]; then
    selected_path="$1"
    selected=$(basename "$selected_path")
    debug_log "Manual Load: Using argument path: $selected_path"
else
    debug_log "No argument found. Launching Rofi Gallery..."
    options=""
    for file in "$WALL_DIR"/*; do
        name=$(basename "$file")
        if [[ "$file" == *.mp4 || "$file" == *.mkv || "$file" == *.webm ]]; then
            icon="$FRAME_CACHE/$name.png"
            [ ! -f "$icon" ] && icon="video-x-generic"
        else
            icon="$file"
        fi
        options+="$name\0icon\x1f$icon\n"
    done

    selected=$(echo -e "$options" | rofi -dmenu -i -p "󰸉 Wallpapers" -theme "$ROFI_THEME")
    [ -z "$selected" ] && exit 0
    selected_path="$WALL_DIR/$selected"
fi

FULL_PATH="$selected_path"

mkdir -p "$(dirname "$STATE_FILE")"
echo "$FULL_PATH" >"$STATE_FILE"
debug_log "Saved $FULL_PATH to $STATE_FILE"

if [[ "$selected" == *.mp4 || "$selected" == *.mkv || "$selected" == *.webm ]]; then
    IMAGE_FOR_COLORS="$FRAME_CACHE/$selected.png"
    if [ ! -f "$IMAGE_FOR_COLORS" ]; then
        debug_log "Frame missing for $selected. Generating..."
        bash "$CACHE_SCRIPT" "$FULL_PATH"
    fi
else
    IMAGE_FOR_COLORS="$FULL_PATH"
fi

pkill mpvpaper

debug_log "Applying colors using engine: \e[35m$COLOR_ENGINE\e[0m"

if [ "$COLOR_ENGINE" = "matugen" ]; then
    matugen image "$IMAGE_FOR_COLORS" --source-color-index 0
else
    wal -i "$IMAGE_FOR_COLORS" -n -q -e

    cp "$HOME/.cache/wal/hyprland-colors.conf" "$HOME/.cache/retro/themes/hyprland-colors.conf"
    cp "$HOME/.cache/wal/kitty-colors.conf" "$HOME/.cache/retro/themes/kitty-colors.conf"
    cp "$HOME/.cache/wal/colors.json" "$HOME/.cache/retro/themes/nvim-colors.json"
fi

TRANSITIONS=("grow" "outer" "wipe" "wave" "center" "fade")
RAND_TYPE=${TRANSITIONS[$RANDOM % ${#TRANSITIONS[@]}]}
RAND_POS="0.$(($RANDOM % 9 + 1)),0.$(($RANDOM % 9 + 1))"

if [[ "$selected" == *.mp4 || "$selected" == *.mkv || "$selected" == *.webm ]]; then
    if [ "$BATTERY_SAVER" = "true" ]; then
        awww img "$IMAGE_FOR_COLORS" --transition-type "$RAND_TYPE" --transition-fps 120
    else
        [ "$VIDEO_TRANSITION" = true ] && awww img "$IMAGE_FOR_COLORS" --transition-type "$RAND_TYPE" --transition-fps 120
        [ -z "$1" ] && sleep 2.2

        NV_PRIME_RENDER_OFFLOAD=0 mpvpaper -o "--loop --hwdec=vaapi --override-display-fps=30 --panscan=1.0" "*" "$FULL_PATH" &
    fi
else
    awww img "$FULL_PATH" --transition-type "$RAND_TYPE" --transition-duration 2.5 --transition-fps 120 --transition-pos "$RAND_POS"
fi

# --- 5. REFRESH ---
#hyprctl reload
pkill -USR2 waybar
#kill -SIGUSR1 $(pgrep kitty) 2>/dev/null
debug_log "\e[32mTheme update complete: $selected\e[0m"
