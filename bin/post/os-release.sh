#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_os_release() {
    rx_clear_logo
    rx_step "Applying Retro Linux os-release..."

    local src="/opt/retrolinux/iso/profile/airootfs/etc/os-release"
    local dst="/mnt/etc/os-release"

    if [[ ! -f $src ]]; then
        gum style --foreground 3 "os-release template not found, skipping"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
    gum style --foreground 2 "Applied Retro Linux os-release"
    return 0
}

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    rx_post_os_release "$@"
fi
