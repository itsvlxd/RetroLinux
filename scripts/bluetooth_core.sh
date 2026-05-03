#!/bin/bash

get_bt_status() {
    local bt_info=$(bluetoothctl show)
    local radio_on=$(echo "$bt_info" | grep -i "Powered:" | awk '{print $2}' | xargs)
    local disc=$(echo "$bt_info" | grep -i "Discoverable:" | awk '{print $2}' | xargs)
    local pair=$(echo "$bt_info" | grep -i "Pairable:" | awk '{print $2}' | xargs)

    local hci_path="/sys/class/bluetooth/hci0/device/power"
    local pwr_ctrl=$(cat "$hci_path/control" 2>/dev/null || echo "on")
    local pwr_stat=$(cat "$hci_path/runtime_status" 2>/dev/null || echo "active")

    local hw_mode="NORMAL"
    [[ $pwr_ctrl == "auto" || $pwr_stat == "suspended" ]] && hw_mode="SAVER"

    local chip_name="Intel Meteor Lake BT"
    if [[ -f "/sys/class/bluetooth/hci0/device/uevent" ]]; then
        chip_name="Intel Wireless Bluetooth"
    fi

    local ver="5.4"
    if command -v btmgmt >/dev/null 2>&1; then
        local lmp
        lmp=$(timeout 3 btmgmt info 2>/dev/null | grep -i "ver" | awk '{print $4}' | head -n 1)
        case "$lmp" in 13) ver="5.4" ;; 12) ver="5.3" ;; 11) ver="5.2" ;; esac
    fi

    local conns=$(bluetoothctl devices Connected | wc -l)

    echo "${radio_on:-no}|${hw_mode}|${disc:-no}|${pair:-no}|${chip_name}|${ver}|${conns}"
}

get_nearby() {
    local check_count=0
    local is_scanning="no"

    while [ $check_count -lt 3 ]; do
        is_scanning=$(bluetoothctl show | grep -i "Discovering:" | awk '{print $2}' | xargs)
        [[ $is_scanning == "yes" ]] && break
        sleep 0.2
        ((check_count++))
    done

    if [[ $is_scanning != "yes" ]]; then
        echo "ERR_SCAN_OFF"
        return 1
    fi

    local paired_macs=$(bluetoothctl devices Paired | awk '{print $2}')

    bluetoothctl devices | while read -r line; do
        local mac=$(echo "$line" | awk '{print $2}')
        if [[ ! $paired_macs =~ $mac ]]; then
            echo "$line"
        fi
    done
}

toggle_discovery() {
    local info=$(bluetoothctl show)
    local current=$(echo "$info" | grep -i "Discoverable:" | awk '{print $2}' | xargs)

    if [[ $current == "yes" ]]; then
        bluetoothctl discoverable off >/dev/null 2>&1
        bluetoothctl pairable off >/dev/null 2>&1
        echo "off"
    else
        bluetoothctl discoverable on >/dev/null 2>&1
        bluetoothctl pairable on >/dev/null 2>&1
        bluetoothctl discoverable-timeout 180 >/dev/null 2>&1
        echo "on"
    fi
}

case "$1" in
    "--status") get_bt_status ;;
    "--toggle-discovery") toggle_discovery ;;
    "--scan-on")
        (
            echo "power on"
            echo "scan on"
            sleep 180
        ) | bluetoothctl >/dev/null 2>&1 &
        ;;
    "--scan-off")
        pkill -f "bluetoothctl"
        ;;
    "--list") bluetoothctl devices Paired ;;
    "--nearby") get_nearby ;;
    "--connect")
        bluetoothctl connect "$2"
        ;;
    "--disconnect") bluetoothctl disconnect "$2" ;;
    "--forget") bluetoothctl remove "$2" ;;
esac
