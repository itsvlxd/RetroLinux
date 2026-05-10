#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_terminal() {
    rx_log "info" "Configuring terminal executor..."
    (command -v yay &>/dev/null || command -v paru &>/dev/null) || { rx_log "warn" "AUR helper not found"; return 1; }
    command -v xdg-terminal-exec &>/dev/null || yay -S --noconfirm xdg-terminal-exec 2>&1 | tail -3
    mkdir -p "$HOME/.config/xdg-terminal-exec"
    cat > "$HOME/.config/xdg-terminal-exec/config" << EOF
[General]
terminal=kitty.desktop
EOF
    rx_log "success" "Terminal executor configured (kitty)"
}