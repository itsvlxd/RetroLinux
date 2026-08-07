#!/bin/bash

export RETRO_STATE="/tmp/retroinstall_state"
source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_save_state() {
    gum style --foreground 7 "Saving installation state..." --padding "1 0 1 $PADDING_LEFT"

    local username=$(arch-chroot /mnt getent passwd 1000 2>/dev/null | cut -d: -f1)
    local home_dir

    if [[ -n $username ]]; then
        home_dir=$(arch-chroot /mnt getent passwd "$username" 2>/dev/null | cut -d: -f6)
    fi

    if [[ -n $username && -n $home_dir ]]; then
        arch-chroot /mnt tee "$home_dir/.retro_install" >/dev/null <<EOF
export INSTALL_TYPE=${INSTALL_TYPE:-complete}
export RICE_MODE=${RICE_MODE:-stable}
export RETRO_BRANCH=${RETRO_BRANCH:-develop}
export FILEMANAGER_CHOICE=${FILEMANAGER_CHOICE:-nemo}
export EDITOR_CHOICE=${EDITOR_CHOICE:-nvim}
export BROWSER_CHOICE=${BROWSER_CHOICE:-firefox}
export AUR_HELPER=${AUR_HELPER:-yay}
export FINGERPRINT_ENABLED=${FINGERPRINT_ENABLED:-false}
export SSH_ENABLED=${SSH_ENABLED:-false}
export SSH_PORT=${SSH_PORT:-22}
export SSH_PASSWORD_LOGIN=${SSH_PASSWORD_LOGIN:-false}
export SSH_KEY_LOGIN=${SSH_KEY_LOGIN:-true}
export SSH_ROOT_LOGIN=${SSH_ROOT_LOGIN:-false}
export NETWORK_TYPE=${NETWORK_TYPE:-}
export WIFI_SSID=${WIFI_SSID:-}
export WIFI_PASSWORD=${WIFI_PASSWORD:-}
export GRUB_THEME_CHOICE=${GRUB_THEME_CHOICE:-retropunk}
export BOOT_VIDEO_GRUB=${BOOT_VIDEO_GRUB:-1920x1080}
export GRUB_OS_PROBER=${GRUB_OS_PROBER:-false}
export GRUB_SNAPSHOTS_ENABLED=${GRUB_SNAPSHOTS_ENABLED:-true}
export GRUB_TIMEOUT=${GRUB_TIMEOUT:-10}
export GRUB_KERNEL=${GRUB_KERNEL:-linux}
export FIREWALL_ENGINE=${FIREWALL_ENGINE:-nftables}
EOF
        arch-chroot /mnt chown "1000:1000" "$home_dir/.retro_install"
        gum style --foreground 2 "State saved to ${home_dir}/.retro_install"
    else
        gum style --foreground 3 "Warning: Could not determine user home directory"
    fi

    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_save_state "$@"
fi
