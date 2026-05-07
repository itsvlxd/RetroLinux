#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_editor() {
    sudo -v
    rx_log "info" "Configuring default text editor..."
    local target_editor="${EDITOR_CHOICE:-nvim}"
    command -v "$target_editor" &>/dev/null || sudo pacman -S --noconfirm "$target_editor" 2>&1 | tail -3
    local editor_path
    editor_path=$(which "$target_editor")
    grep -q "^EDITOR=" /etc/environment 2>/dev/null || echo "EDITOR=$target_editor" | sudo tee -a /etc/environment
    grep -q "^VISUAL=" /etc/environment 2>/dev/null || echo "VISUAL=$target_editor" | sudo tee -a /etc/environment
    grep -q "^SUDO_EDITOR=" /etc/environment 2>/dev/null || echo "SUDO_EDITOR=$target_editor" | sudo tee -a /etc/environment
    echo "Defaults editor=$editor_path" | sudo tee /etc/sudoers.d/editor
    rx_log "success" "Default editor set to: $target_editor"
}