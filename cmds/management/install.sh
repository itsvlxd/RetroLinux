#!/bin/bash

cmd_install() {
    local target="$1"

    [[ ! $(command -v yay) ]] && rx_log "warn" "yay missing, fixing..." && rx_bootstrap_yay
    rx_log "info" "Initiating deployment for: ${target:-all}"
    run_task "install" "$target"
    rx_log "success" "Installation cycle complete."
}

register_command "MANAGEMENT" "-i|--install" "Link repo files to system (Active Ricing)" "cmd_install"
