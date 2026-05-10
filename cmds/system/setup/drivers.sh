#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_drivers() {
    local scan_data
    scan_data=$(bash "$RETRO_DIR/scripts/driver_core.sh" --install)
    [[ -z $scan_data ]] && return 0
    [[ $scan_data == *"ALL_DRIVERS_INSTALLED"* ]] && return 0

    rx_log "info" "Missing drivers detected on your system, would you like to install them? ${PINK}[y/N]${RESET}: "
    read -r confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && return 0

    local driver_script="$RETRO_DIR/cmds/tools/driver.sh"

    [[ -f $driver_script ]] && source "$driver_script"

    cmd_driver "install"

    rx_log "success" "Hardware drivers installed"
}

