#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_fingerprint() {
    local fingerprint_enabled="${FINGERPRINT_ENABLED:-false}"
    [[ "$fingerprint_enabled" != "true" ]] && { rx_log "info" "Fingerprint disabled, skipping"; return 0; }
    rx_log "info" "Configuring fingerprint authentication..."
    command -v fprintd &>/dev/null || sudo pacman -S --noconfirm fprintd 2>&1 | tail -3
    systemctl start fprintd 2>&1
    source "$RETRO_DIR/cmds/tools/fingerprint.sh"
    cmd_fingerprint "setup"
    rx_log "success" "Fingerprint authentication configured"
}