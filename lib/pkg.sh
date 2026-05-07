#!/bin/bash

rx_pkg_install() {
    local list_file="$1"
    local sudo_run="${2:-false}"
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

    local install_cmd=""
    if command -v yay >/dev/null; then
        install_cmd="yay -S --needed --noconfirm"
    else
        install_cmd="pacman -S --needed --noconfirm"
    fi

    if [[ $sudo_run == "true" ]]; then
        sudo bash -c "$install_cmd ${missing_pkgs[*]}"
    else
        $install_cmd "${missing_pkgs[@]}"
    fi
}
