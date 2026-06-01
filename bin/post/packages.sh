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
        unzip
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
        sudo

        inter-font
        ttf-jetbrains-mono-nerd

        "${KERNEL_SELECTION}-headers"
    )

    arch-chroot /mnt pacman -S --noconfirm --needed "${packages[@]}" 2>&1

    local username=$(arch-chroot /mnt getent passwd 1000 2>/dev/null | cut -d: -f1)
    if [[ -n $username ]]; then
        arch-chroot /mnt bash -c "
            mkdir -p /etc/sudoers.d &&
            echo '$username ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/retro-post-install &&
            chmod 440 /etc/sudoers.d/retro-post-install
        " 2>/dev/null
    fi

    arch-chroot /mnt fc-cache -f 2>&1

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
