#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/scripts/lib/battery.sh"

get_info() {
    local stat=$(get_bat_status)
    local cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")
    local health=$(cat "$BAT_PATH/capacity_level" 2>/dev/null || echo "N/A")
    local model=$(cat "$BAT_PATH/model_name" 2>/dev/null || echo "Generic")
    local p_raw=$(cat "$BAT_PATH/power_now" 2>/dev/null || echo "0")
    local v_raw=$(cat "$BAT_PATH/voltage_now" 2>/dev/null || echo "0")
    local saver=$(get_var "BAT_SAVER_ACTIVE")

    if [[ $stat == *"discharging"* ]]; then
        local start_ts=$(get_var "BAT_DISCONNECT_TIME")

        if [[ -n $start_ts && $start_ts != "null" ]]; then
            local now=$(date +%s)
            local diff=$((now - start_ts))
            sot_label=$(rx_format_time "$diff")
        else
            local now=$(date +%s)
            set_var "BAT_DISCONNECT_TIME" "$now"
            sot_label="N/A"
        fi
    else
        sot_label="N/A"
    fi

    if [[ $p_raw -eq 0 ]]; then
        local i_raw=$(cat "$BAT_PATH/current_now" 2>/dev/null || echo "0")
        p_raw=$((i_raw * v_raw / 1000000))
    fi

    local saver_label="OFF"

    if [[ $saver == "true" ]]; then
        saver_label="ON"
    fi

    echo "$cap|$stat|$health|$p_raw|$v_raw|$model|$saver_label|$sot_label"
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

log_battery_event() {
    local type="$1"
    local val="$2"
    local today=$(date +%Y-%m-%d)

    local entry_0=$(get_var "BAT_STATS_0")

    if [[ $entry_0 == "null" || -z $entry_0 || $entry_0 != *"|"* ]]; then
        entry_0="$today|0|0"
    fi

    IFS='|' read -r d_date d_cycles d_seconds <<<"$entry_0"

    if [[ $d_date != "$today" ]]; then
        for i in {5..0}; do
            local next_idx=$((i + 1))
            local moving_data=$(get_var "BAT_STATS_$i")
            [[ $moving_data == "null" ]] && moving_data="0000-00-00|0|0"
            set_var "BAT_STATS_$next_idx" "$moving_data"
        done
        d_date="$today"
        d_cycles=0
        d_seconds=0
    fi

    if [[ $type == "cycle" ]]; then
        d_cycles=$((d_cycles + val))
    else
        d_seconds=$((d_seconds + val))
    fi

    set_var "BAT_STATS_0" "${d_date}|${d_cycles}|${d_seconds}"
}

case "$1" in
    "--raw") get_bat_status ;;
    "--info") get_info ;;
    "--limit") set_limit "$2" ;;
    "--loop") run_loop ;;
    "--saver") set_saver "$2" "$3" ;;
    "--log") log_battery_event "$2" "$3" ;;
esac
