#!/bin/bash

cmd_install() {
    local target="${1}"

    rx_log "info" "Starting installation for: ${PINK}${target:-all}${RESET}"

    run_task "install" "$target"
}

register_command "MODULES" "-i|--install" "Link repo files to system (Active Ricing)" "cmd_install"
