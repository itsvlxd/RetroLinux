#!/bin/bash

on_battery_saver_enabled() {
    local current_pwr=$(get_var "PWR_CURRENT")
    if [[ $current_pwr != "saver" ]]; then
        bash "$PWR_CORE" --set saver
    fi

    bash "$WALL_CORE" --restore true
}

on_battery_saver_disabled() {
    local current_pwr=$(get_var "PWR_CURRENT")
    if [[ $current_pwr == "saver" ]]; then
        bash "$PWR_CORE" --toggle
    fi

    bash "$WALL_CORE" --restore true
}
