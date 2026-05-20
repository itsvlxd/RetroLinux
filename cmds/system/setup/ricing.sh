#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_ricing_mode() {
    local rice_mode="${RICE_MODE:-stable}"

    if [[ $rice_mode == "advanced" ]]; then
        "$RETRO_DIR/retro.sh" variable set RETRO_RICING "true" 2>/dev/null
        rx_log "success" "Advanced ricing mode enabled (RETRO_RICING=true)"
    else
        "$RETRO_DIR/retro.sh" variable set RETRO_RICING "false" 2>/dev/null
        rx_log "success" "Stable ricing mode enabled (RETRO_RICING=false)"
    fi
}
