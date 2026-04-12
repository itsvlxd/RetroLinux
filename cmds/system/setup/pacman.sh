#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

rx_optimize_pacman() {
    local config="/etc/pacman.conf"

    local has_color=$(
        grep -q "^Color" "$config"
        echo $?
    )
    local has_candy=$(
        grep -q "^ILoveCandy" "$config"
        echo $?
    )
    local extra_is_commented=$(
        grep -q "^#\[extra\]" "$config"
        echo $?
    )
    local multi_is_commented=$(
        grep -q "^#\[multilib\]" "$config"
        echo $?
    )

    if [[ $has_color -eq 0 && $has_candy -eq 0 && $extra_is_commented -ne 0 && $multi_is_commented -ne 0 ]]; then
        return 0
    fi

    rx_help_section "Pacman Optimizations"
    rx_log "info" "I noticed some Pacman optimizations (Color, ILoveCandy, Extra, Multilib) aren't active."

    rx_log "info" "Would you like me to enable them in /etc/pacman.conf? ${PINK}[y/N]${RESET}"
    read -r allow

    if [[ ! $allow =~ ^[Yy]$ ]]; then
        rx_log "info" "Pacman optimization skipped."
        return 0
    fi

    rx_log "info" "Applying visual and system tweaks to Pacman..."

    sudo sed -i 's/^#Color/Color/' "$config"

    if grep -q "^Color" "$config" && ! grep -q "ILoveCandy" "$config"; then
        sudo sed -i '/^Color/a ILoveCandy' "$config"
        rx_log "success" "Visuals: Color & ILoveCandy are now active."
    fi

    if [[ $extra_is_commented -eq 0 ]]; then
        sudo sed -i '/\[extra\]/,/Include/ s/^#//' "$config"
        rx_log "success" "System: Extra repository enabled."
    fi

    if [[ $multi_is_commented -eq 0 ]]; then
        sudo sed -i '/\[multilib\]/,/Include/ s/^#//' "$config"
        rx_log "success" "System: Multilib repository enabled."
    fi

    rx_log "info" "Refreshing package databases..."
    sudo pacman -Sy
}
