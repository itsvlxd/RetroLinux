#!/bin/bash

rx_bootstrap_pkg_manager() {
    local has_yay=false
    local has_paru=false
    command -v yay >/dev/null 2>&1 && has_yay=true
    command -v paru >/dev/null 2>&1 && has_paru=true

    local label_1="Install yay"
    local label_2="Install paru"
    $has_yay && label_1="Update yay"
    $has_paru && label_2="Update paru"

    rx_log "info" "Select the AUR helper you want to use for this system."

    echo -e " ${PINK}󰄾${RESET} Select Operation:"
    echo -e "  ${PINK}1)${RESET} $label_1 ${GRAY}(Go)${RESET}"
    echo -e "  ${PINK}2)${RESET} $label_2 ${GRAY}(Rust)${RESET}"
    echo -e "  ${PINK}3)${RESET} Back to Terminal"

    echo -ne "\n ${PINK}󰄾 ${RESET}Action: "
    read -r choice

    case "$choice" in
        1)
            local helper="yay"
            if $has_yay; then
                rx_log "info" "Syncing system via yay..."

                yay -Syu --noconfirm
            else
                rx_install_helper "$helper"
            fi

            bash "$RETRO_VAR" set "RETRO_PKG_HELPER" "$helper"
            ;;
        2)
            local helper="paru"
            if $has_paru; then
                rx_log "info" "Syncing system via paru..."

                paru -Syu --noconfirm
            else
                rx_install_helper "$helper"
            fi

            bash "$RETRO_VAR" set "RETRO_PKG_HELPER" "$helper"
            ;;
        *)
            return 0
            ;;
    esac
}

rx_install_helper() {
    local target="$1"
    [[ -z $target ]] && return 1

    rx_log "info" "Installing ${PINK}${target}${RESET}..."

    sudo pacman -S --needed --noconfirm base-devel git

    local temp_dir=$(mktemp -d)
    if git clone "https://aur.archlinux.org/${target}.git" "$temp_dir"; then
        (
            cd "$temp_dir" || exit 1
            makepkg -si --noconfirm
        )
        rm -rf "$temp_dir"
        rx_log "success" "${target} integrated."
    else
        rx_log "error" "AUR connection failed."
        rm -rf "$temp_dir"
        return 1
    fi
}
