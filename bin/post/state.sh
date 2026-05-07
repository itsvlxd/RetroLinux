#!/bin/bash

export RETRO_STATE="/mnt/tmp/retroinstall_state"
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
FILEMANAGER_CHOICE=${FILEMANAGER_CHOICE:-thunar}
EDITOR_CHOICE=${EDITOR_CHOICE:-nvim}
BROWSER_CHOICE=${BROWSER_CHOICE:-firefox}
AUR_HELPER=${AUR_HELPER:-yay}
FINGERPRINT_ENABLED=${FINGERPRINT_ENABLED:-false}
SSH_ENABLED=${SSH_ENABLED:-false}
SSH_PORT=${SSH_PORT:-22}
SSH_PASSWORD_LOGIN=${SSH_PASSWORD_LOGIN:-false}
SSH_KEY_LOGIN=${SSH_KEY_LOGIN:-true}
SSH_ROOT_LOGIN=${SSH_ROOT_LOGIN:-false}
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
