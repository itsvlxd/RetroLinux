#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

# TODO: remake the modules some to be level root level user

setup_modules() {
    rx_log "info" "Installing RetroLinux modules..."
    local root_modules=("retro" "grub" "plymouth")
    local user_modules=("hyprland" "matugen")
    for module in "${root_modules[@]}"; do
        "$RETRO_DIR/retro.sh" --install "$module" -y 2>&1 | tail -3
    done
    for module in "${user_modules[@]}"; do
        "$RETRO_DIR/retro.sh" --install "$module" -y 2>&1 | tail -3
    done
    rx_log "success" "Module installation complete"
}

