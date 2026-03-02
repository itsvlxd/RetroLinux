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

    # TODO: Add a log message like now please select the package manager you want to use
    # ALSO Make a var to like RETRO_PKG_HELPER and we will use that when pkg install

    echo -e " ${PINK}󰄾${RESET} Select Operation:"
    echo -e "  ${PINK}1)${RESET} $label_1 ${GRAY}(Go)${RESET}"
    echo -e "  ${PINK}2)${RESET} $label_2 ${GRAY}(Rust)${RESET}"
    echo -e "  ${PINK}3)${RESET} Back to Terminal"

    echo -ne "\n ${PINK}󰄾 ${RESET}Action: "
    read -r choice

    case "$choice" in
    1)
        if $has_yay; then
            rx_log "info" "Syncing system via yay..."
            yay -Syu --noconfirm
        else
            rx_install_helper "yay"
        fi
        ;;
    2)
        if $has_paru; then
            rx_log "info" "Syncing system via paru..."
            paru -Syu --noconfirm
        else
            rx_install_helper "paru"
        fi
        ;;
    *)
        return 0
        ;;
    esac
}

rx_install_helper() {
    local target="$1"
    [[ -z "$target" ]] && return 1

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
    fi
}
