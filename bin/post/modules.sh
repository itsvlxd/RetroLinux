#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_install_modules() {
    rx_clear_logo
    rx_step "Installing RetroLinux modules..."

    local ROOT_MODULES=("grub" "plymouth")
    local USER_MODULES=("hyprland" "matugen" "kitty" "retro")

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

    if [[ ${#ROOT_MODULES[@]} -gt 0 ]]; then
        gum style "Installing root modules..."
        echo

        for module in "${ROOT_MODULES[@]}"; do
            local output
            output=$(arch-chroot /mnt /opt/retrolinux/retro.sh --install "$module" -y 2>&1)
            local result=$?

            local last_line=$(echo "$output" | tail -1)

            if [[ $result -eq 0 ]] && ! echo "$last_line" | grep -iq "error"; then
                gum style --foreground 2 "$module module installed"
            else
                gum style --foreground 3 "Warning: $module module had issues"
            fi
        done

        echo
    fi

    if [[ ${#USER_MODULES[@]} -gt 0 ]]; then
        gum style "Installing user modules..."
        echo

        for module in "${USER_MODULES[@]}"; do
            local output
            output=$(arch-chroot /mnt su - "$username" -c "/opt/retrolinux/retro.sh --install $module -y" 2>&1)
            local result=$?

            local last_line=$(echo "$output" | tail -1)

            if [[ $result -eq 0 ]] && ! echo "$last_line" | grep -iq "error"; then
                gum style --foreground 2 "$module module installed"
            else
                gum style --foreground 3 "Warning: $module module had issues"
            fi
        done

        echo
    fi

    gum style --foreground 2 "Module installation complete"
    echo
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_install_modules "$@"
fi
