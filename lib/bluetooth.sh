#!/bin/bash

BT_ADAPTER_PATH="/sys/class/bluetooth/hci0"

has_bluetooth() {
    [[ -d "$BT_ADAPTER_PATH" ]] && echo "true" || echo "false"
}

get_bt_connected_devices() {
    bluetoothctl devices Connected 2>/dev/null | awk '{print $2}' | xargs
}

get_bt_device_info() {
    local mac="$1"
    [[ -z $mac ]] && return

    local name
    name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Name:" | sed 's/.*Name: //' | xargs)
    [[ -z $name ]] && name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Alias:" | sed 's.*Alias: .' | xargs)

    echo "$name"
}

is_bt_device_paired() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    bluetoothctl info "$mac" 2>/dev/null | grep -q "Paired: yes" && echo "true" || echo "false"
}