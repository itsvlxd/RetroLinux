#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"

MOUNT_ROOT="$HOME/Mounts"

check_usb_state() {
    local current_usb_list
    current_usb_list=$(lsblk -nlo NAME,RM,TYPE 2>/dev/null | awk '$2 ~ /^1$/ && $3 ~ /^part$/ {print $1}' | xargs)

    for dev_name in $current_usb_list; do
        if [[ ! $last_usb_list =~ (^| )$dev_name( |$) ]]; then
            local dev_path="/dev/$dev_name"
            local label
            label=$(lsblk -nlo LABEL "$dev_path" 2>/dev/null | xargs)
            [[ -z $label ]] && label="USB_$dev_name"

            local actual_mount
            actual_mount=$(findmnt -nlo TARGET "$dev_path" 2>/dev/null | xargs)

            if [[ -z $actual_mount ]]; then
                udisksctl mount -b "$dev_path" --no-user-interaction >/dev/null 2>&1
                sleep 0.5
                actual_mount=$(findmnt -nlo TARGET "$dev_path" 2>/dev/null | xargs)
            fi

            if [[ -n $actual_mount ]]; then
                local symlink_path="$MOUNT_ROOT/$label"
                ln -sfn "$actual_mount" "$symlink_path"

                local ignore_list
                ignore_list=$(get_var "USB_IGNORE_DRIVES")
                if [[ "|$ignore_list|" != *"|$label|"* ]]; then
                    broadcast_event "on_usb_connected" "$label" "$symlink_path"
                fi
            fi
        fi
    done

    for old_dev in $last_usb_list; do
        if [[ ! $current_usb_list =~ (^| )$old_dev( |$) ]]; then
            broadcast_event "on_usb_disconnected" "$old_dev" "$MOUNT_ROOT"
        fi
    done

    last_usb_list="$current_usb_list"
}

start_watcher_usb() {
    mkdir -p "$MOUNT_ROOT"

    last_usb_list=$(lsblk -nlo NAME,RM,TYPE 2>/dev/null | awk '$2 ~ /^1$/ && $3 ~ /^part$/ {print $1}' | xargs)

    check_usb_state

    stdbuf -oL udevadm monitor --udev --subsystem-match=block 2>/dev/null |
        while read -r _; do

            while read -t 1 -r _; do
                continue
            done

            check_usb_state

        done
}

