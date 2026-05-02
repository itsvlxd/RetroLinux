#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_aur() {
    rx_clear_logo
    rx_step "Let's configure your AUR helper..."
    
    echo
    if gum confirm --affirmative "yay" --negative "paru" "Select AUR helper" --padding "$GUM_CONFIRM_PADDING"; then
        local aur_helper="yay"
        local aur_repo="https://aur.archlinux.org/yay-bin.git"
        local aur_dir="yay-bin"
    else
        local aur_helper="paru"
        local aur_repo="https://aur.archlinux.org/paru.git"
        local aur_dir="paru"
    fi
    
    echo
    gum style "Installing ${aur_helper}..."
    echo
    
    arch-chroot /mnt pacman -S --noconfirm --needed base-devel git >/dev/null 2>&1
    
    local username=$(arch-chroot /mnt getent passwd 1000 | cut -d: -f1)
    
    if [[ -n "$username" ]]; then
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rx_post_aur "$@"
fi
