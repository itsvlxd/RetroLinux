#!/bin/bash

source "$RETRO_DIR/scripts/lib/battery.sh"
source "$RETRO_DIR/scripts/lib/variable.sh"

WALL_CORE="$RETRO_DIR/scripts/wallpaper_core.sh"
PWR_CORE="$RETRO_DIR/scripts/power_core.sh"

get_info() {
    local stat=$(get_bat_status)
    local cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")
    local health=$(cat "$BAT_PATH/capacity_level" 2>/dev/null || echo "N/A")
    local model=$(cat "$BAT_PATH/model_name" 2>/dev/null || echo "Generic")
    local p_raw=$(cat "$BAT_PATH/power_now" 2>/dev/null || echo "0")
    local v_raw=$(cat "$BAT_PATH/voltage_now" 2>/dev/null || echo "0")
    local saver=$(get_var "BAT_SAVER_ACTIVE")

    if [[ $p_raw -eq 0 ]]; then
        local i_raw=$(cat "$BAT_PATH/current_now" 2>/dev/null || echo "0")
        p_raw=$((i_raw * v_raw / 1000000))
    fi

    local saver_label="OFF"

    if [[ $saver == "true" ]]; then
        saver_label="ON"
    fi

    echo "$cap|$stat|$health|$p_raw|$v_raw|$model|$saver_label"
}

set_limit() {
    local limit="$1"
    local path="$BAT_PATH/charge_control_end_threshold"

    [[ -f $path ]] && echo "$limit" | sudo tee "$path" >/dev/null || return 1
}

set_saver() {
    local val="$1"
    local force="$2"

    if [[ $val == "true" ]]; then
        set_var "BAT_SAVER_FORCED" "true"
        set_var "BAT_SAVER_ACTIVE" "true"
        return 0

    elif [[ $val == "false" ]]; then
        if [[ $force == "-f" || $force == "--force" ]]; then
            set_var "BAT_SAVER_FORCED" "true"
            set_var "BAT_SAVER_ACTIVE" "false"
        else
            set_var "BAT_SAVER_FORCED" "false"
        fi
        return 0

    elif [[ $val =~ ^[0-9]+$ ]]; then
        set_var "BAT_SAVER_THRESHOLD" "$val"
        set_var "BAT_SAVER_FORCED" "false"
        return 0
    fi

    return 1
}

case "$1" in
    "--raw") get_bat_status ;;
    "--info") get_info ;;
    "--limit") set_limit "$2" ;;
    "--loop") run_loop ;;
    "--saver") set_saver "$2" "$3" ;;
esac
