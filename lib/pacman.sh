#!/bin/bash

rx_optimize_pacman() {
    local PINK='\e[38;5;201m'
    local GRAY='\e[38;5;244m'
    local RESET='\e[0m'

    echo -e " This will enable ${PINK}Color${RESET}, ${PINK}ILoveCandy${RESET}, and ${PINK}Multilib${RESET} in /etc/pacman.conf."
    echo -ne " ${PINK}󰄾 ${RESET}Allow retro to modify pacman.conf? [y/N]: "
    read -r allow

    if [[ ! "$allow" =~ ^[Yy]$ ]]; then
        rx_log "info" "Optimization skipped."
        return 0
    fi

    rx_log "info" "Applying overrides to /etc/pacman.conf..."

    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf

    if grep -q "^Color" /etc/pacman.conf && ! grep -q "ILoveCandy" /etc/pacman.conf; then
        sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
        rx_log "success" "Visuals: Color & ILoveCandy enabled."
    fi

    if grep -q "#\[multilib\]" /etc/pacman.conf; then
        sudo sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
        rx_log "success" "System: Multilib repository enabled."
    else
        rx_log "info" "Multilib already active or not found."
    fi

    rx_log "info" "Syncing package databases..."
    sudo pacman -Sy
}
