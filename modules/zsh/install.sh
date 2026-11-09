#!/bin/bash

source "$RETRO_DIR/lib/log.sh"

install_zsh() {
    local current_shell
    current_shell=$(getent passwd "$USER" | cut -d: -f7)
    local zsh_settings="$HOME/.zsh_settings"

    rx_log "info" "Clearing p10k instant prompt cache..."
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-"*.zsh
    rx_log "success" "p10k cache cleared"

    if [[ ! -f $zsh_settings ]]; then
        touch "$zsh_settings"
        rx_log "info" "Created $zsh_settings file"
    fi

    if [[ $current_shell == *"zsh"* ]]; then
        rx_log "info" "Default shell is already zsh — skipping"
        return 0
    fi

    local zsh_path
    zsh_path=$(command -v zsh)
    if [[ -z $zsh_path ]]; then
        rx_log "error" "zsh is not installed"
        return 1
    fi

    rx_log "warn" "Default shell is ${PINK}${current_shell}${RESET}, switching to zsh..."
    if chsh -s "$zsh_path"; then
        rx_log "success" "Default shell changed to zsh (takes effect on next login)"
    else
        rx_log "error" "Failed to change default shell to zsh"
        return 1
    fi
}

install_zsh
