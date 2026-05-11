#!/bin/bash

source "$RETRO_DIR/lib/bluetooth.sh"
source "$RETRO_DIR/lib/helpers.sh"

touch /tmp/.bt_watcher_start 2>/dev/null

check_bluetooth_state() {
    local ignored_macs=$(get_var "BT_MAC_IGNORE")
    local currently_pairing=$(get_var "BT_PAIRING_IN_PROGRESS")

    bluetoothctl devices Connected 2>/dev/null | awk '{print $2}' | xargs | while read -r mac; do
        [[ -z $mac ]] && continue

        if [[ $ignored_macs != *"$mac"* ]] && [[ $currently_pairing != *"$mac"* ]]; then
            if bluetoothctl info "$mac" 2>/dev/null | grep -q "Paired: no"; then
                local dev_name=$(get_bt_device_info "$mac")
                broadcast_event "on_bluetooth_pairing_request" "$dev_name" "$mac"
            fi
        fi
    done

    local current_list
    current_list=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}' | xargs)

    for mac in $current_list; do
        if [[ ! $last_bt_connected_list =~ $mac ]]; then
            if [[ $(is_bt_device_paired "$mac") == "true" ]]; then
                local dev_name=$(get_bt_device_info "$mac")
                broadcast_event "on_bluetooth_connected" "$dev_name" "$mac"
            fi
        fi
    done

    for mac in $last_bt_connected_list; do
        if [[ ! $current_list =~ $mac ]]; then
            local dev_name=$(get_bt_device_info "$mac")
            [[ -z $dev_name ]] && dev_name="Unknown Device"
            broadcast_event "on_bluetooth_disconnected" "$dev_name" "$mac"
        fi
    done

    last_bt_connected_list="$current_list"
}

_bt_check_incoming() {
    local obex_dir="$HOME/Downloads"
    local last_file
    last_file=$(get_var "BT_LAST_INCOMING_FILE" "")

    if [[ -d $obex_dir ]]; then
        local newest
        newest=$(find "$obex_dir" -maxdepth 1 -type f -newer /tmp/.bt_watcher_start 2>/dev/null | sort -r | head -1)
        if [[ -n $newest && "$newest" != "$last_file" ]]; then
            local sender_name sender_mac
            sender_name=$(get_var "BT_INCOMING_SENDER_NAME" "Unknown")
            sender_mac=$(get_var "BT_INCOMING_SENDER_MAC" "")

            local file_name=$(basename "$newest")
            local file_size
            file_size=$(du -h "$newest" 2>/dev/null | awk '{print $1}')

            broadcast_event "on_bluetooth_file_received" "$sender_name" "$sender_mac" "$file_name" "$newest" "$file_size"

            set_var "BT_LAST_INCOMING_FILE" "$newest"
        fi
    fi

    touch /tmp/.bt_watcher_start 2>/dev/null
}

start_watcher_bluetooth() {
    [[ $(has_bluetooth) != "true" ]] && exit 0

    last_bt_connected_list=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}' | xargs)

    while true; do
        check_bluetooth_state
        _bt_check_incoming
        sleep 2
    done
}
