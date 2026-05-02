#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_install_packages() {
    rx_clear_logo
    rx_step "Installing essential packages..."

    local packages=(
        bc
        jq
        git
        sed
        grep
        rsync
        expect
        neovim
        fprintd
        udisks2
        usbutils
        net-tools
        inetutils
        base-devel
        pacman-contrib
        networkmanager
    )

    arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}" >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then
        gum style --foreground 2 "  Essential packages installed"
    else
        gum style --foreground 3 "  Warning: Some packages may have failed"
    fi

    echo
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_install_packages "$@"
fi
