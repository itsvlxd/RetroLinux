#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_modules() {
    rx_log "info" "Installing RetroLinux modules..."

    local type_flag=""
    if [[ ${INSTALL_TYPE:-complete} == "minimal" ]]; then
        type_flag="-t core"
        rx_log "info" "Installing minimal set (core modules only)..."
    else
        type_flag="-t all"
        rx_log "info" "Installing complete set (all modules)..."
    fi

    retro -i all -a root $type_flag -y
    retro -i all -a user $type_flag -y

    rx_log "success" "Module installation complete"
}
