#!/bin/bash

on_power_disconnect() {
    local cap="$1"

    if [[ $(get_var "BAT_SAVER_ON_PWR_DIS") == "true" && $(get_var "BAT_SAVER_ACTIVE") != "true" ]]; then
        bash "$PWR_CORE" --set "saver" &
    fi

    if [[ $(get_var "WALL_STATIC_ON_BAT") == "true" ]]; then
        bash "$WALL_CORE" --restore true &
    fi

    set_var "BAT_DISCONNECT_TIME" "$(date +%s)"
}

on_power_connect() {
    bash "$PWR_CORE" --restore-prev &

    if [[ $(get_var "BAT_SAVER_ON_PWR_DIS") == "true" && $(get_var "BAT_SAVER_ACTIVE") == "true" ]]; then
        bash "$BAT_CORE" --saver "false" &
    fi

    if [[ $(get_var "WALL_STATIC_ON_BAT") == "true" ]]; then
        bash "$WALL_CORE" --restore true &
    fi

    local start=$(get_var "BAT_DISCONNECT_TIME")

    if [[ -n $start && $start != "null" ]]; then
        local end=$(date +%s)
        local total_sec=$((end - start))

        bash "$BAT_CORE" --log "duration" "$total_sec"
        bash "$BAT_CORE" --log "cycle" "1"

        set_var "BAT_DISCONNECT_TIME" "null"
    fi
}

on_power_profile_changed() {
    local current_pwr=$1

    if [[ $current_pwr != "saver" && $(get_var "BAT_SAVER_ACTIVE") == "true" ]]; then
        bash "$BAT_CORE" --saver "false"
        sync_hyprland_power "false"
    elif [[ $current_pwr == "saver" && $(get_var "BAT_SAVER_ACTIVE") != "true" ]]; then
        bash "$BAT_CORE" --saver "true"
        sync_hyprland_power "true"
    fi

    bash "$WALL_CORE" --restore true
}
