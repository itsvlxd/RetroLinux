#!/bin/bash

cmd_uninstall() {
    local target="$1"

    rx_log "warn" "Starting uninstallation for: ${PINK}${target:-all}${RESET}"

    run_task "uninstall" "$target"
}

register_command "MODULES" "-r|--remove" "Uninstall module and restore backups" "cmd_uninstall"
