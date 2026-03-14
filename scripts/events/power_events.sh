#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/scripts/lib/battery.sh"

PWR_CORE="$RETRO_DIR/scripts/power_core.sh"
BAT_CORE="$RETRO_DIR/scripts/battery_core.sh"
VAR_CORE="$RETRO_DIR/scripts/variable_core.sh"
WALL_CORE="$RETRO_DIR/scripts/wallpaper_core.sh"

# TODO: Make a on idle event

on_power_disconnect() {
    local cap="$1"

    if [[ $(get_var "BAT_SAVER_ON_PWR_DIS") == "true" && $(get_var "BAT_SAVER_ACTIVE") != "true" ]]; then
        bash "$BAT_CORE" --saver "true"
        bash "$PWR_CORE" --set "saver"
    fi

    bash "$PWR_CORE" --restore

    if [[ $(get_var "WALL_STATIC_ON_BAT") == "true" ]]; then
        bash "$WALL_CORE" --restore
    fi

    set_var "BAT_DISCONNECT_TIME" "$(date +%s)"
}

on_power_connect() {
    bash "$PWR_CORE" --restore

    if [[ $(get_var "BAT_SAVER_ON_PWR_DIS") == "true" && $(get_var "BAT_SAVER_ACTIVE") == "true" ]]; then
        bash "$BAT_CORE" --saver "false"

        if [[ $(get_var "PWR_CURRENT") == "saver" ]]; then
            bash "$PWR_CORE" --toggle
        fi
    fi

    if [[ $(get_var "WALL_STATIC_ON_BAT") == "true" ]]; then
        bash "$WALL_CORE" --restore
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
    elif [[ $current_pwr == "saver" && $(get_var "BAT_SAVER_ACTIVE") != "true" ]]; then
        bash "$BAT_CORE" --saver "true"
    fi
}
