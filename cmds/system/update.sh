#!/bin/bash

cmd_update() {
    local target="$1"

    if [[ ! -d "$RETRO_DIR/.git" ]]; then
        rx_log "error" "Not a git repository: $RETRO_DIR"
        return 1
    fi

    rx_log "info" "Syncing repository with $(rx_git_branch)"

    if git -C "$RETRO_DIR" pull; then
        rx_log "success" "Git pull successful"

        if [[ $SKIP_PROMPT != true ]]; then
            rx_log "info" "Would you like to update all modules? ${PINK}[y/N]${RESET}"
            read -r confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                cmd_install "$target"
            else
                rx_log "info" "Skipping module updates."
            fi
        else
            cmd_install "$target"
        fi
    else
        rx_log "error" "Git pull failed. Check your connection or conflicts."
        return 1
    fi
}

register_command "SYSTEM" "-u|--update" "Sync repo and refresh all modules" "cmd_update"
