#!/bin/bash

setup_disk() {
    rx_load_state
    rx_step "Let's select where to install RetroLinux..."

    local available_disks
    available_disks=$(rx_get_available_disks) || {
        rx_step_error "3" "Could not list available disks"
        rx_retry_or_exit "Cannot list disks" || rx_abort
        return 1
    }

    if [[ -z $available_disks ]]; then
        rx_step_error "3" "No disks found"
        rx_retry_or_exit "No disks available" || rx_abort
        return 1
    fi

    local disk_options=""
    while IFS= read -r device; do
        if [[ -n $device ]]; then
            local disk_info
            disk_info=$(rx_get_disk_info "$device")
            disk_options="$disk_options$disk_info"$'\n'
        fi
    done <<<"$available_disks"

    local selected_display
    selected_display=$(echo "$disk_options" | gum choose --header "Select install disk" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "3" "Disk selection cancelled"
        rx_retry_or_exit "Disk selection required" || rx_abort
        return 1
    }
    DISK_SELECTED=$(echo "$selected_display" | awk '{print $1}')
    rx_save_state

    if [[ ! -b $DISK_SELECTED ]]; then
        rx_step_error "3" "Invalid disk selected"
        rx_retry_or_exit "Invalid disk" || rx_abort
        return 1
    fi

    return 0
}

if [[ "${RETRO_SETUP_SOURCED:-}" != "1" ]]; then
    export RETRO_SETUP_SOURCED=1
    source "$RETRO_INSTALL/lib/display.sh"
    source "$RETRO_INSTALL/lib/errors.sh"
    source "$RETRO_INSTALL/lib/gum.sh"
    source "$RETRO_INSTALL/lib/wifi.sh"
    source "$RETRO_INSTALL/lib/qr.sh"
    source "$RETRO_INSTALL/lib/locale.sh"
    source "$RETRO_INSTALL/lib/timezone.sh"
    source "$RETRO_INSTALL/lib/handlers.sh"
    source "$RETRO_INSTALL/lib/output.sh"
    source "$RETRO_INSTALL/lib/debug.sh"
    source "$RETRO_INSTALL/lib/disk.sh"
    source "$RETRO_INSTALL/lib/progress.sh"
    rx_set_retro_colors
fi

setup_disk