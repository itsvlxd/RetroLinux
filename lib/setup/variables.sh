#!/bin/bash

# TODO: Add the edit command which open the variables file
# using the default text editor

rx_vars_defaults() {
    local force_flag="$1"
    local var_script="$RETRO_DIR/scripts/variable_core.sh"

    local defaults=(
        # Retro
        "RETRO_ACTIVE_OPACITY|0.9"
        "RETRO_INACTIVE_OPACITY|0.8"
        "RETRO_ROUNDING|10"
        "RETRO_GAP_IN|5"
        "RETRO_GAP_OUT|20"

        # Battery
        "BAT_SAVER_THRESHOLD|50"
        "BAT_SAVER_ACTIVE|false"
        "BAT_SAVER_FORCED|false"
        "BAT_SAVER_ON_PWR_DIS|false"

        "BAT_NOTIFY_THRESHOLD|30"
        "BAT_NOTIFY_CRITICAL_THRESHOLD|15"

        # Wallpaper
        "WALL_STATIC_FORCED|false"
        "WALL_STATIC_ON_BAT|true"

        # Power
        "PWR_CURRENT|balanced"
        "PWR_PREVIOUS|saver"
        "PWR_BAT_SAVER|7"
        "PWR_BAT_BALANCED|14"
        "PWR_BAT_PERFORMANCE|35"
        "PWR_AC_SAVER|15"
        "PWR_AC_BALANCED|28"
        "PWR_AC_PERFORMANCE|65"

        # Kitty
        "KITTY_FONT|JetBrainsMono Nerd Font"
        "KITTY_FONT_SIZE|9.5"
        "KITTY_PADDING_WIDTH|5"
        "KITTY_PADDING_HEIGHT|5"
    )

    local count=0
    local is_forcing=false
    [[ $force_flag == "-f" || $force_flag == "--force" ]] && is_forcing=true

    for entry in "${defaults[@]}"; do
        IFS='|' read -r key val <<<"$entry"

        if [[ $is_forcing == "true" ]]; then
            bash "$var_script" --set "$key" "$val"
            ((count++))
        else
            local current_val=$(bash "$var_script" --get "$key")
            if [[ -z $current_val ]]; then
                bash "$var_script" --set "$key" "$val"
                ((count++))
            fi
        fi
    done

    if [[ $is_forcing == "true" ]]; then
        rx_log "success" "Vars reset: $count values forced to defaults."
    elif [[ $count -gt 0 ]]; then
        rx_log "success" "Setup: $count missing variables initialized."
    fi

    return 0
}
