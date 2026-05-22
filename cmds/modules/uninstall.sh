#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

cmd_uninstall() {
    local target="$1"

    rx_log "warn" "Starting uninstallation for: ${PINK}${target:-all}${RESET}"

    run_task "uninstall" "$target"
}

register_command "MODULES" "-r|--remove" "Remove module configs from system and restore previous backup files" "cmd_uninstall"
