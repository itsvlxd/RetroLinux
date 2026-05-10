#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_modules() {
    rx_log "info" "Installing RetroLinux modules..."

    sudo "$RETRO_DIR/retro.sh" -i all -a root -y 2>&1

    "$RETRO_DIR/retro.sh" -i all -a user -y 2>&1

    rx_log "success" "Module installation complete"
}
