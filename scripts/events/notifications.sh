#!/bin/bash

on_power_disconnect() {
    local cap="$1"
    notify-send -u normal -i battery-caution \
        "Power Disconnected" "Now on battery power (${cap}%)"
}

on_power_connect() {
    local cap="$1"
    if [[ $cap -eq 100 ]]; then
        notify-send -u normal -i battery-full-charging \
            "Power Connected" "Running on AC (Battery bypassed)"
    else
        notify-send -u normal -i battery-charging \
            "Power Connected" "Charging up (${cap}%)"
    fi
}

on_battery_saver_enabled() {
    notify-send -u normal -i power-profile-saver \
        "Battery Saver" "Power draw capped to extend runtime"
}

on_battery_saver_disabled() {
    notify-send -u normal -i power-profile-balanced \
        "Battery Saver" "Standard power limits restored"
}

on_battery_low() {
    local cap="$1"

    if [[ $cap == "30" ]]; then
        notify-send -u normal -i battery-low \
            "Battery Low" "${cap}% remaining — find a plug soon"

    fi
}

on_battery_critical() {
    local cap="$1"

    if [[ $cap == "15" ]]; then
        notify-send -u critical -i battery-empty \
            "Battery Critical" "Only ${cap}% left. Connect power now."

    fi
}
