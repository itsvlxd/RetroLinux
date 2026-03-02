#!/bin/bash

cmd_update() {
    local target="$1"
    rx_log "info" "Syncing repository with $(rx_git_branch)"

    if git pull; then
        rx_log "success" "Git pull successful"
        cmd_install "$target"
    else
        rx_log "error" "Git pull failed. Check your connection or conflicts."
        return 1
    fi
}

register_command "SYSTEM" "-u|--update" "Sync repo and refresh all modules" "cmd_update"
