#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_fonts() {
    rx_log "info" "Configuring fonts..."

    $RETRO_DIR/retro.sh font "setup" -y

    rx_log "success" "Fonts configured"
}
