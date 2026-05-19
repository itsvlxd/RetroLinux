#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"

rx_pkg_install() {
    local list_file="$1"
    local sudo_run="${2:-false}"
    [[ ! -f $list_file ]] && return 0

    local all_pkgs=$(grep -v '^#' "$list_file" | xargs)
    [[ -z $all_pkgs ]] && return 0

    local missing_pkgs=()
    local skipped_pkgs=()
    for pkg in $all_pkgs; do
        if pacman -Qq "$pkg" >/dev/null 2>&1; then
            continue
        fi

        if [[ $RETRO_CHROOT == "true" ]]; then
            if pacman -Si "$pkg" >/dev/null 2>&1; then
                missing_pkgs+=("$pkg")
            else
                skipped_pkgs+=("$pkg")
            fi
        else
            missing_pkgs+=("$pkg")
        fi
    done

    if [[ ${#skipped_pkgs[@]} -gt 0 ]]; then
        rx_log "warn" "Skipping AUR packages (will install on first boot): ${PINK}${skipped_pkgs[*]}${RESET}"
    fi

    [[ ${#missing_pkgs[@]} -eq 0 ]] && return 0

    rx_log "info" "Installing missing packages: ${PINK}${missing_pkgs[*]}${RESET}"

    local install_cmd=""
    if [[ $RETRO_CHROOT == "true" ]]; then
        install_cmd="pacman -S --needed --noconfirm"
    elif [[ $EUID -eq 0 ]]; then
        install_cmd="pacman -S --needed --noconfirm"
    else
        local helper
        helper=$(get_var "PKG_HELPER" "yay")
        if command -v "$helper" >/dev/null 2>&1; then
            install_cmd="$helper -S --needed --noconfirm"
        else
            if ! command -v pacman >/dev/null 2>&1; then
                rx_log "error" "No package manager available"
                return 1
            fi
            rx_log "warn" "Using pacman (no AUR helper found, AUR packages will fail)"
            install_cmd="sudo pacman -S --needed --noconfirm"
        fi
    fi

    if [[ $sudo_run == "true" && $EUID -ne 0 ]]; then
        sudo bash -c "$install_cmd ${missing_pkgs[*]}"
    else
        $install_cmd "${missing_pkgs[@]}"
    fi
}
