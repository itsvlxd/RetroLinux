#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_aur() {
    rx_load_state

    local username=$(arch-chroot /mnt getent passwd 1000 2>/dev/null | cut -d: -f1)
    if [[ -z $username ]]; then
        username="root"
    fi

    local aur_helper="${AUR_HELPER:-yay}"

    if [[ -z $aur_helper ]] || [[ ! $aur_helper =~ ^(yay|paru)$ ]]; then
        aur_helper="yay"
    fi

    if command -v "$aur_helper" >/dev/null 2>&1; then
        gum style --foreground 7 "AUR helper already selected: ${PINK}${aur_helper}${RESET}"
        echo
        return 0
    fi

    rx_clear_logo
    rx_step "Installing AUR helper..."

    echo
    gum style "Installing ${aur_helper}..."
    echo

    arch-chroot /mnt pacman -S --noconfirm --needed base-devel git >/dev/null 2>&1

    if [[ -n $username ]]; then
        local aur_repo=""
        local aur_dir=""
        case "$aur_helper" in
            yay)
                aur_repo="https://aur.archlinux.org/yay-bin.git"
                aur_dir="yay-bin"
                ;;
            paru)
                aur_repo="https://aur.archlinux.org/paru.git"
                aur_dir="paru"
                ;;
        esac

        arch-chroot /mnt su - "$username" -c "
            cd /tmp &&
            rm -rf $aur_dir &&
            git clone --depth 1 $aur_repo &&
            cd $aur_dir &&
            makepkg -si --noconfirm
        " >/dev/null 2>&1

        if [[ $? -eq 0 ]]; then
            gum style --foreground 2 "${aur_helper} installed"
        else
            gum style --foreground 3 "Warning: ${aur_helper} installation failed"
        fi
    else
        gum style --foreground 3 "Warning: No user found, skipping AUR helper"
    fi

    echo
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_aur "$@"
fi

