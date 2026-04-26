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

    if rx_disk_has_partitions "$DISK_SELECTED"; then
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Warning: $DISK_SELECTED contains existing partitions"
        gum style --padding "0 0 0 $PADDING_LEFT" "All data on this disk will be ERASED to set up BTRFS encryption."
        echo
        gum style --padding "0 0 0 $PADDING_LEFT" "This cannot be undone."
        echo
        if ! gum confirm --affirmative "I understand, continue" --negative "Go back" "Confirm disk wipe" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
            RX_GO_BACK_TO="disk"
            rx_save_state
            return 42
        fi
    fi

    rx_save_state

    if [[ ! -b $DISK_SELECTED ]]; then
        rx_step_error "3" "Invalid disk selected"
        rx_retry_or_exit "Invalid disk" || rx_abort
        return 1
    fi

    return 0
}

if [[ ${RETRO_SETUP_SOURCED:-} != "1" ]]; then
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
