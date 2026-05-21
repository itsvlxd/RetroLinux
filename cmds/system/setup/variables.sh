#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_variables() {
    rx_log "info" "Initializing system variables..."
    local filemanager_choice="${FILEMANAGER_CHOICE:-thunar}"
    local editor_choice="${EDITOR_CHOICE:-nvim}"
    local install_type="${INSTALL_TYPE:-complete}"
    local aur_helper="${AUR_HELPER:-yay}"

    local defaults=(
        "PKG_HELPER|$aur_helper"
        "RETRO_FILEMANAGER_CMD|$filemanager_choice"
        "RETRO_EDITOR_CMD|$editor_choice"
        "RETRO_INSTALL|$install_type"
    )

    for entry in "${defaults[@]}"; do
        IFS='|' read -r key val <<<"$entry"
        "$RETRO_DIR/retro.sh" variable set "$key" "$val" 2>/dev/null
    done
    rx_log "success" "System variables initialized"

    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
}
