#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_browser() {
    rx_log "info" "Configuring browser defaults..."
    local browser_choice="${BROWSER_CHOICE:-firefox}"
    command -v "$browser_choice" &>/dev/null || command -v yay &>/dev/null && yay -S --noconfirm "$browser_choice" 2>&1 | tail -3
    rx_log "success" "Browser configured: $browser_choice"
}