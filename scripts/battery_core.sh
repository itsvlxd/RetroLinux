#!/bin/bash

BAT_PATH=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)
AC_PATH=$(find /sys/class/power_supply/ \( -name "AC*" -o -name "ADP*" \) | head -n 1)

# TODO: Replace these with rx_var_get calls later
SAVER_ENABLED="false"
SAVER_THRESHOLD="20"
NOTIFY_THRESHOLD="15"

get_status_raw() {
    if [[ -z "$AC_PATH" ]]; then
        cat "$BAT_PATH/status" 2>/dev/null | tr '[:upper:]' '[:lower:]'
        return
    fi

    local ac_online=$(cat "$AC_PATH/online" 2>/dev/null || echo "0")
    local cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")

    if [[ "$ac_online" -eq 1 ]]; then
        [[ "$cap" -eq 100 ]] && echo "full" || echo "charging"
    else
        echo "discharging"
    fi
}

get_info() {
    local stat=$(get_status_raw)
    local cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")
    local health=$(cat "$BAT_PATH/capacity_level" 2>/dev/null || echo "N/A")
    local model=$(cat "$BAT_PATH/model_name" 2>/dev/null || echo "Generic")

    local p_raw=$(cat "$BAT_PATH/power_now" 2>/dev/null || echo "0")
    local v_raw=$(cat "$BAT_PATH/voltage_now" 2>/dev/null || echo "0")

    if [[ "$p_raw" -eq 0 ]]; then
        local i_raw=$(cat "$BAT_PATH/current_now" 2>/dev/null || echo "0")
        p_raw=$((i_raw * v_raw / 1000000))
    fi

    echo "$cap|$stat|$health|$p_raw|$v_raw|$model"
}

set_limit() {
    local limit="$1"
    local path="$BAT_PATH/charge_control_end_threshold"
    [[ -f "$path" ]] && echo "$limit" | sudo tee "$path" >/dev/null || return 1
}

set_saver() {
    local val="$1"

    if [[ "$val" == "true" ]]; then
        echo "true" >/tmp/retro_saver_active
        return 0
    elif [[ "$val" == "false" ]]; then
        echo "false" >/tmp/retro_saver_active
        return 0
    elif [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "$val" >/tmp/retro_saver_threshold
        return 0
    fi
    return 1
}

run_loop() {
    local last_stat=$(get_status_raw)
    local last_notified_cap=0

    while true; do
        local current_stat=$(get_status_raw)
        local current_cap=$(cat "$BAT_PATH/capacity")

        if [[ "$current_stat" != "$last_stat" ]]; then
            if [[ "$current_stat" == "charging" ]]; then
                notify-send "󱐋 Power Connected" "Battery is charging ($current_cap%)"
            elif [[ "$current_stat" == "discharging" ]]; then
                notify-send "󰂃 Power Disconnected" "System on battery ($current_cap%)"
            fi
            last_stat="$current_stat"
        fi

        if [[ "$current_stat" == "discharging" ]]; then
            if [[ "$current_cap" -le "$NOTIFY_THRESHOLD" ]]; then
                if [[ "$current_cap" -ne "$last_notified_cap" ]]; then
                    notify-send -u critical "󰂃 Battery Critical" "Level: ${current_cap}%"
                    last_notified_cap="$current_cap"
                fi
            fi

            if [[ "$current_cap" -le "$SAVER_THRESHOLD" ]]; then
                touch /tmp/retro_saver_on
            else
                rm -f /tmp/retro_saver_on
            fi
        else
            last_notified_cap=0
            rm -f /tmp/retro_saver_on
        fi

        sleep 2
    done
}

case "$1" in
"--raw") get_status_raw ;;
"--info") get_info ;;
"--limit") set_limit "$2" ;;
"--loop") run_loop ;;
"--saver") set_saver "$2" ;;
esac
