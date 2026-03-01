#!/bin/bash

cmd_pull() {
    local target="$1"
    rx_log "warn" "Capturing system changes for: ${target:-all}"

    run_task "pull" "$target"
}

register_command "MANAGEMENT" "-p|--pull" "Capture system changes back to repo" "cmd_pull"
