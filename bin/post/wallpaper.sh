#!/bin/bash

export RETRO_STATE="/tmp/retroinstall_state"
source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_wallpaper() {
    rx_load_state
    rx_clear_logo
    rx_step "Configuring wallpapers..."

    local username=$(arch-chroot /mnt getent passwd 1000 | cut -d: -f1)

    if [[ -z $username ]]; then
        gum style --foreground 3 "Warning: No user found, skipping wallpaper setup"
        echo
        return 0
    fi

    local wallpaper_res="${WALLPAPER_RES:-1920x1080}"

    arch-chroot /mnt su - "$username" -c "
        if [[ -d /opt/retrolinux/wallpapers ]]; then
            mkdir -p ~/.cache/retro/wallpapers
            cp -rn /opt/retrolinux/wallpapers/* ~/.cache/retro/wallpapers/ 2>/dev/null
        fi
    " 2>&1

    arch-chroot /mnt su - "$username" -c "bash /opt/retrolinux/retro.sh variable set RETRO_THEME retro" 2>&1
    #arch-chroot /mnt su - "$username" -c "bash /opt/retrolinux/retro.sh wallpaper set car-in-neon-gas-station.mp4" 2>&1
    arch-chroot /mnt su - "$username" -c "bash /opt/retrolinux/retro.sh variable set WALL_RES_MAP $wallpaper_res" 2>&1
    arch-chroot /mnt su - "$username" -c "bash /opt/retrolinux/retro.sh wallpaper optimize" 2>&1
    arch-chroot /mnt su - "$username" -c "bash /opt/retrolinux/retro.sh wallpaper cache" 2>&1
    #arch-chroot /mnt su - "$username" -c "bash /opt/retrolinux/retro.sh wallpaper restore" 2>&1

    gum style --foreground 5 "Wallpapers configured (${PINK}$wallpaper_res${RESET})"
    echo
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_wallpaper "$@"
fi

