#!/bin/bash

export RETRO_STATE="/tmp/retroinstall_state"
source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_install_packages() {
    rx_load_state
    rx_clear_logo
    rx_step "Installing essential packages..."

    local packages=(
        bc
        jq
        git
        sed
        gum
        grep
        rsync
        expect
        neovim
        fprintd
        udisks2
        usbutils
        net-tools
        inetutils
        memtest86+
        base-devel
        imagemagick
        pacman-contrib
        networkmanager
    )

    arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}" 2>&1

    if [[ $? -eq 0 ]]; then
        gum style --foreground 5 "Essential packages installed"
    else
        gum style --foreground 3 "Warning: Some packages may have failed"
    fi

    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_install_packages "$@"
fi

