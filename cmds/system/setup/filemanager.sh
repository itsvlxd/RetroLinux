#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_filemanager() {
    rx_log "info" "Configuring file manager defaults..."
    local fm_choice="${FILEMANAGER_CHOICE:-thunar}"
    command -v "$fm_choice" &>/dev/null || command -v yay &>/dev/null && yay -S --noconfirm "$fm_choice" 2>&1 | tail -3
    rx_log "success" "File manager configured: $fm_choice"
}