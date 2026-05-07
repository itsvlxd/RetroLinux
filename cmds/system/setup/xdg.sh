#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_xdg() {
    rx_log "info" "Configuring XDG directories..."
    local xdg_packages=(xdg-user-dirs xdg-utils shared-mime-info desktop-file-utils)
    for pkg in "${xdg_packages[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            sudo pacman -S --noconfirm --needed "$pkg" 2>&1 | tail -3
        fi
    done
    command -v xdg-user-dirs-update &>/dev/null && xdg-user-dirs-update
    rx_log "success" "XDG directories configured"
}