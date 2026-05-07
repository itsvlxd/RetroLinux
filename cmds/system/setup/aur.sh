#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_aur() {
    local aur_helper="${AUR_HELPER:-yay}"
    if command -v "$aur_helper" &>/dev/null; then
        rx_log "info" "$aur_helper already installed"
        return 0
    fi
    if ! command -v git &>/dev/null; then
        sudo pacman -S --noconfirm git
    fi
    local tmp_dir="/tmp/aur_build"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir" || return 1
    rm -rf "$aur_helper"
    git clone --depth 1 "https://aur.archlinux.org/${aur_helper}-bin.git"
    cd "$aur_helper-bin" || return 1
    makepkg -si --noconfirm
    rx_log "success" "$aur_helper installed"
}