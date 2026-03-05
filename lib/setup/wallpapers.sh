#!/bin/bash

VAR_SCRIPT="$RETRO_DIR/scripts/variable_core.sh"
WALL_CORE="$RETRO_DIR/scripts/wallpaper_core.sh"
SOURCE_WALLS="$RETRO_DIR/wallpapers"
CACHE_WALLS="$HOME/.cache/retro/wallpapers"

rx_setup_wallpapers() {
    rx_log "info" "Initializing Retro Arch wallpaper assets..."

    mkdir -p "$CACHE_WALLS"

    if [[ -d $SOURCE_WALLS ]]; then
        rx_log "info" "Syncing wallpapers to $CACHE_WALLS..."
        cp -r "$SOURCE_WALLS"/* "$CACHE_WALLS/"
    else
        rx_log "error" "Source wallpapers not found in $SOURCE_WALLS"
        return 1
    fi

    rx_log "info" "Generating frame cache for video fallback..."

    if [[ -f $WALL_CORE ]]; then
        bash "$WALL_CORE" "--cache"
    else
        rx_log "error" "Wallpaper core script not found. Skipping cache generation."
    fi

    bash "$WALL_CORE" "--set" "car-in-neon-gas-station.1920x1080.mp4" >/dev/null 2>&1 &
}
