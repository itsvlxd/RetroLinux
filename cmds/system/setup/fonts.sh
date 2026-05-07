#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_fonts() {
    rx_log "info" "Configuring fonts..."
    source "$RETRO_DIR/lib/helpers.sh"
    source "$RETRO_DIR/cmds/tools/font.sh"
    export SKIP_PROMPT=true
    cmd_font "setup"
    rx_log "success" "Fonts configured"
}