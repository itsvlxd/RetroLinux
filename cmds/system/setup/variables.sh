#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_variables() {
    rx_log "info" "Initializing system variables..."
    local filemanager_choice="${FILEMANAGER_CHOICE:-thunar}"
    local editor_choice="${EDITOR_CHOICE:-nvim}"
    local install_type="${INSTALL_TYPE:-complete}"
    local aur_helper="${AUR_HELPER:-yay}"

    local defaults=(
        "PKG_HELPER|$aur_helper"
        "RETRO_FILEMANAGER_CMD|$filemanager_choice"
        "RETRO_EDITOR_CMD|$editor_choice"
        "RETRO_INSTALL|$install_type"
    )

    for entry in "${defaults[@]}"; do
        IFS='|' read -r key val <<<"$entry"
        "$RETRO_DIR/retro.sh" variable set "$key" "$val" 2>/dev/null
    done
    rx_log "success" "System variables initialized"

    local grub_theme="${GRUB_THEME_CHOICE:-retropunk}"
    local grub_resolution="${BOOT_VIDEO_GRUB:-1920x1080}"
    local grub_os_prober="${GRUB_OS_PROBER:-false}"
    local grub_snapshots="${GRUB_SNAPSHOTS_ENABLED:-true}"
    local grub_timeout="${GRUB_TIMEOUT:-10}"

    local grub_defaults=(
        "GRUB_THEME_CHOICE|$grub_theme"
        "BOOT_VIDEO_GRUB|$grub_resolution"
        "GRUB_OS_PROBER|$grub_os_prober"
        "GRUB_SNAPSHOTS_ENABLED|$grub_snapshots"
        "GRUB_TIMEOUT|$grub_timeout"
    )

    for entry in "${grub_defaults[@]}"; do
        IFS='|' read -r key val <<<"$entry"
        "$RETRO_DIR/retro.sh" variable set "$key" "$val" 2>/dev/null
    done
    rx_log "success" "GRUB variables initialized"

    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
}
