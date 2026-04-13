#!/bin/bash

check_power_state() {
    local current_on_battery
    current_on_battery=$(is_on_battery)

    if [[ $current_on_battery != "$last_on_battery" ]]; then
        local current_cap
        current_cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")

        if [[ $current_on_battery == "true" ]]; then
            broadcast_event "on_power_disconnect" "$current_cap"
        else
            broadcast_event "on_power_connect" "$current_cap"
        fi

        last_on_battery="$current_on_battery"
    fi
}

start_watcher_power() {
    last_on_battery=$(is_on_battery)

    stdbuf -oL udevadm monitor --udev --subsystem-match=power_supply 2>/dev/null | \
    while read -r _; do
        check_power_state
    done
}