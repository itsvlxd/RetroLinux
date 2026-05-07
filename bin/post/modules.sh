#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_install_modules() {
    rx_clear_logo
    rx_step "Installing RetroLinux modules..."

    local username=$(arch-chroot /mnt getent passwd 1000 2>/dev/null | cut -d: -f1)

    if [[ -z $username ]]; then
        username="root"
        gum style --foreground 3 "No user with UID 1000 found, using root"
    fi

    echo

    if [[ ! -f /mnt/opt/retrolinux/retro.sh ]]; then
        gum style --foreground 1 "RetroLinux script not found, skipping module install"
        echo
        return 1
    fi

    gum style "Installing root modules..."

    arch-chroot /mnt /opt/retrolinux/retro.sh -i all -a root -y 2>&1

    gum style "Installing user modules..."

    arch-chroot /mnt su - "$username" -c "/opt/retrolinux/retro.sh -i all -a user -y" 2>&1

    gum style --foreground 2 "Module installation complete"
    echo
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_install_modules "$@"
fi
