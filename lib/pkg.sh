#!/bin/bash

rx_pkg_install() {
    local list_file="$1"
    [[ ! -f $list_file ]] && return 0

    local all_pkgs=$(grep -v '^#' "$list_file" | xargs)
    [[ -z $all_pkgs ]] && return 0

    local missing_pkgs=()
    for pkg in $all_pkgs; do
        if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done

    [[ ${#missing_pkgs[@]} -eq 0 ]] && return 0

    rx_log "info" "Installing missing packages: ${PINK}${missing_pkgs[*]}${RESET}"

    if command -v yay >/dev/null; then
        yay -S --needed --noconfirm "${missing_pkgs[@]}"
    else
        sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"
    fi
}
