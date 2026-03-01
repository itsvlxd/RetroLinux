#!/bin/bash

rx_bootstrap_yay() {
    if command -v yay >/dev/null; then
        rx_log "info" "yay is already installed. Updating system..."
        yay -Syu --noconfirm
    else
        rx_log "warn" "yay not found. Initializing build environment..."

        if sudo pacman -S --needed --noconfirm base-devel git; then
            rx_log "success" "Base-devel and git installed."
        else
            rx_log "error" "Failed to install base dependencies via pacman."
            return 1
        fi

        local temp_dir=$(mktemp -d)
        rx_log "info" "Cloning yay into temporary directory..."

        if git clone https://aur.archlinux.org/yay.git "$temp_dir"; then
            (
                cd "$temp_dir" || exit
                rx_log "info" "Building and installing yay..."
                makepkg -si --noconfirm
            )

            rm -rf "$temp_dir"

            if command -v yay >/dev/null; then
                rx_log "success" "yay installation complete."
            else
                rx_log "error" "makepkg finished but 'yay' command is not found."
                return 1
            fi
        else
            rx_log "error" "Failed to clone yay repository."
            rm -rf "$temp_dir"
            return 1
        fi
    fi
}
