#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_wallpaper() {
    rx_log "info" "Configuring wallpapers..."
    [[ -d "$RETRO_DIR/wallpapers" ]] && mkdir -p "$RETRO_CONFIG/wallpapers" && cp -rn "$RETRO_DIR/wallpapers/"* "$HOME/.config/retro/wallpapers/" 2>/dev/null
    "$RETRO_DIR/retro.sh" variable set RETRO_THEME retro 2>&1
    "$RETRO_DIR/retro.sh" wallpaper optimize 2>&1
    "$RETRO_DIR/retro.sh" wallpaper cache 2>&1
    rx_log "success" "Wallpapers configured"
}
