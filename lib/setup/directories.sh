#!/bin/bash

rx_default_directories() {
    local dirs=("Desktop" "Downloads" "Pictures" "Music" "Videos" "Documents")
    local missing=()

    for dir in "${dirs[@]}"; do
        [[ ! -d "$HOME/$dir" ]] && missing+=("$dir")
    done

    [[ ${#missing[@]} -eq 0 ]] && return 0

    rx_log "info" "Some standard folders are missing: ${PINK}${missing[*]}${RESET}"
    echo -ne " ${PINK}󰄾 ${RESET}Would you like me to create them? [y/N]: "
    read -r allow

    if [[ ! $allow =~ ^[Yy]$ ]]; then
        rx_log "info" "Skipped folder creation."
        return 0
    fi

    for dir in "${missing[@]}"; do
        mkdir -p "$HOME/$dir"
    done

    rx_log "success" "Folders created."
    return 0
}
