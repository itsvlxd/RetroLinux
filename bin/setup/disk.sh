#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

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
    selected_display=$(echo "$disk_options" | gum choose --header "Select install disk" --height 15 --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "3" "Disk selection cancelled"
        rx_retry_or_exit "Disk selection required" || rx_abort
        return 1
    }
    DISK_SELECTED=$(echo "$selected_display" | awk '{print $1}')

    if rx_disk_has_partitions "$DISK_SELECTED"; then
        rx_clear_logo
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

if ! setup_disk; then
    rx_setup_fail "Disk"
fi

