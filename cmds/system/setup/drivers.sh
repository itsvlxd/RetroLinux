#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_drivers() {
    rx_log "info" "Installing hardware drivers..."
    if [[ ! -f "$RETRO_DIR/cmds/tools/driver.sh" ]]; then
        rx_log "warn" "Driver tool not found"
        return 1
    fi
    source "$RETRO_DIR/cmds/tools/driver.sh"
    cmd_driver "install" "-y"
    rx_log "success" "Hardware drivers installed"
}