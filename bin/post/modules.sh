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

    rx_load_state
    local install_type="${INSTALL_TYPE:-complete}"

    local type_flag=""
    if [[ "$install_type" == "minimal" ]]; then
        type_flag="-t core"
        gum style "Installing minimal set (core modules only)..."
    else
        type_flag="-t all"
        gum style "Installing complete set (all modules)..."
    fi

    echo

    gum style "Installing root modules..."

    arch-chroot /mnt /opt/retrolinux/retro.sh -i all -a root $type_flag -y 2>&1

    gum style "Installing user modules..."

    local home_dir=$(arch-chroot /mnt getent passwd "$username" 2>/dev/null | cut -d: -f6)
    arch-chroot /mnt bash -c "HOME=$home_dir USER=$username /opt/retrolinux/retro.sh -i all -a user $type_flag -y" 2>&1

    # Fix ownership of user config dirs that were installed as root
    if [[ -n $home_dir ]]; then
        arch-chroot /mnt bash -c "
            for d in \"$home_dir\"/.config/*/; do
                [[ -d \$d ]] && chown -R \"$username:\" \"\$d\" 2>/dev/null
            done
            for f in \"$home_dir\"/.config/*; do
                [[ -f \$f ]] && chown \"$username:\" \"\$f\" 2>/dev/null
            done
        " 2>/dev/null
    fi

    gum style --foreground 2 "Module installation complete"
    echo
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_install_modules "$@"
fi
