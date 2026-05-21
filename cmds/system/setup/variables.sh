#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/xdg.sh"

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

    if [[ $filemanager_choice == "yazi" ]]; then
        mkdir -p "$HOME/.local/share/applications"
        cat >"$HOME/.local/share/applications/yazi.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Yazi
Exec=kitty -e yazi %u
Icon=yazi
Terminal=true
Categories=System;FileManagement;
MimeType=inode/directory;application/x-directory;
EOF
    fi

    rx_xdg_reset_defaults >/dev/null
    rx_log "success" "File manager configured: $filemanager_choice"

    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
}
