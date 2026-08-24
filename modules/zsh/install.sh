#!/bin/bash

source "$RETRO_DIR/lib/log.sh"

install_zsh() {
    local current_shell
    current_shell=$(getent passwd "$USER" | cut -d: -f7)

    rx_log "info" "Clearing p10k instant prompt cache..."
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-"*.zsh
    rx_log "success" "p10k cache cleared"

    if [[ "$current_shell" == *"zsh"* ]]; then
        rx_log "info" "Default shell is already zsh — skipping"
        return 0
    fi

    rx_log "warn" "Default shell is ${PINK}${current_shell}${RESET}, switching to zsh..."
    chsh -s "$(command -v zsh)"
    rx_log "success" "Default shell changed to zsh (takes effect on next login)"
}

install_zsh
