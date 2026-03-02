#!/bin/bash

rx_pkg_install() {
    local list_file="$1"
    if [[ ! -f "$list_file" ]]; then
        return 0
    fi

    local pkgs=$(grep -v '^#' "$list_file" | xargs)
    if [[ -z "$pkgs" ]]; then
        return 0
    fi

    rx_log "info" "Installing packages from $list_file"

    if command -v yay >/dev/null; then
        yay -S --needed --noconfirm $pkgs
    else
        sudo pacman -S --needed --noconfirm $pkgs
    fi
}
