#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_keyring() {
    sudo -v

    rx_log "info" "Configuring keyring services..."

    local keyring_packages=(libsecret gnome-keyring)

    for pkg in "${keyring_packages[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            sudo pacman -S --noconfirm --needed "$pkg" 2>&1 | tail -3
        fi
    done

    systemctl --user enable secret-service.service 2>&1

    systemctl --user enable gnome-keyring-daemon.service 2>&1

    rx_log "success" "Keyring services configured"
}

