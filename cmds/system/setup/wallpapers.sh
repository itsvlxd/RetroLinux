#!/bin/bash

VAR_SCRIPT="$RETRO_DIR/scripts/variable_core.sh"
WALL_CORE="$RETRO_DIR/scripts/wallpaper_core.sh"
CACHE_WALLS="$HOME/.cache/retro/wallpapers"
SOURCE_WALLS="$RETRO_DIR/wallpapers"

rx_setup_wallpapers() {
    local current_wall=$(bash "$VAR_SCRIPT" --get "WALL_CURRENT")
    if [[ -n $current_wall ]]; then
        return 0
    fi

    if [[ ! -d $SOURCE_WALLS ]]; then
        rx_log "error" "Source wallpapers not found in $SOURCE_WALLS"
        return 1
    fi

    rx_log "info" "Initializing wallpaper assets..."

    mkdir -p "$CACHE_WALLS"

    cp -r "$SOURCE_WALLS"/* "$CACHE_WALLS/"

    if [[ -f $WALL_CORE ]]; then
        bash "$WALL_CORE" --cache
        bash "$WALL_CORE" --set "car-in-neon-gas-station.1920x1080.mp4" >/dev/null 2>&1 &
    else
        rx_log "error" "Wallpaper core script missing."
        return 1
    fi

    rx_log "success" "Wallpaper system ready."
}
