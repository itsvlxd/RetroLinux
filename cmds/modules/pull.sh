#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

cmd_pull() {
    local target="$1"

    rx_log "warn" "Capturing system changes for: ${target:-all}"

    run_task "pull" "$target"
}

register_command "MODULES" "-p|--pull" "Capture live system config changes back into repo modules for version tracking" "cmd_pull"
