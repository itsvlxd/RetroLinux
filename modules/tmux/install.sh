#!/bin/bash

source "$RETRO_DIR/lib/log.sh"

install_tmux() {
    local tpm_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins/tpm"

    if [[ -d $tpm_dir ]]; then
        rx_log "info" "tpm already installed — skipping clone"
    else
        rx_log "info" "Cloning tpm (tmux plugin manager)..."
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
        rx_log "success" "tpm installed"
    fi

    rx_log "info" "Installing tmux plugins..."
    "$tpm_dir/bin/install_plugins"
    rx_log "success" "tmux plugins installed"
}

install_tmux
