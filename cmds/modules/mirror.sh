#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

cmd_mirror() {
    local target="$1"

    rx_log "warn" "Starting mirror (physical copy) for: ${target:-all}"

    run_task "mirror" "$target"
}

register_command "MODULES" "-m|--mirror" "Hard copy repo files to system (Stability / Testing)" "cmd_mirror"
