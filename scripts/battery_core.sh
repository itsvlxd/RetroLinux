#!/bin/bash

# TODO: If battery = static wallpapers

BAT_PATH=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)
AC_PATH=$(find /sys/class/power_supply/ \( -name "AC*" -o -name "ADP*" \) | head -n 1)
VAR_SCRIPT="$RETRO_DIR/scripts/var_core.sh"

get_var() { bash "$VAR_SCRIPT" get "$1"; }
set_var() { bash "$VAR_SCRIPT" set "$1" "$2"; }

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
    if [[ "$val" == "true" || "$val" == "false" ]]; then
        set_var "BAT_SAVER_FORCED" "$val"
        return 0
    elif [[ "$val" =~ ^[0-9]+$ ]]; then
        set_var "BAT_SAVER_THRESHOLD" "$val"
        return 0
    fi
    return 1
}

run_loop() {
    local last_stat=$(get_status_raw)
    local last_notified_cap=0
    local last_critical_notified=0

    while true; do
        local current_stat=$(get_status_raw)
        local current_cap=$(cat "$BAT_PATH/capacity")

        local saver_threshold=$(get_var "BAT_SAVER_THRESHOLD")
        local notify_threshold=$(get_var "BAT_NOTIFY_THRESHOLD")
        local critical_threshold=$(get_var "BAT_NOTIFY_CRITICAL_THRESHOLD")
        local current_saver_state=$(get_var "BAT_SAVER_ACTIVE")

        : ${saver_threshold:=20}
        : ${notify_threshold:=30}
        : ${critical_threshold:=15}
        : ${current_saver_state:="false"}

        if [[ "$current_stat" != "$last_stat" ]]; then
            [[ "$current_stat" == "charging" ]] && notify-send -i battery-charging "󱐋 Power Connected"
            [[ "$current_stat" == "discharging" ]] && notify-send -i battery-caution "󰂃 Power Disconnected"
            last_stat="$current_stat"
        fi

        local target_state="$current_saver_state"

        if [[ "$current_stat" == "discharging" || "$current_stat" == "full" ]]; then
            if [[ "$current_cap" -le "$saver_threshold" ]]; then
                target_state="true"
            else
                target_state="false"
            fi

            if [[ "$current_cap" -le "$critical_threshold" ]]; then
                if [[ "$current_cap" -ne "$last_critical_notified" ]]; then
                    notify-send -u critical -i battery-empty "󰂃 Battery Critical!" "Level: ${current_cap}%"
                    last_critical_notified="$current_cap"
                fi
            elif [[ "$current_cap" -le "$notify_threshold" ]]; then
                if [[ "$current_cap" -ne "$last_notified_cap" ]]; then
                    notify-send -u normal -i battery-low "󰂃 Battery Low" "Level: ${current_cap}%"
                    last_notified_cap="$current_cap"
                fi
            fi
        else
            last_notified_cap=0
            last_critical_notified=0
            target_state="false"
        fi

        if [[ "$target_state" != "$current_saver_state" ]]; then
            bash "$RETRO_DIR/scripts/var_core.sh" set "BAT_SAVER_ACTIVE" "$target_state"

            if [[ "$target_state" == "true" ]]; then
                notify-send -u normal -i power-profile-saver "󰂯 Battery Saver" "Optimization Active ($current_cap%)"
            else
                notify-send -u normal -i power-profile-balanced "󰂯 Battery Saver" "Performance Restored"
            fi
        fi

        sleep 5
    done
}

case "$1" in
"--raw") get_status_raw ;;
"--info") get_info ;;
"--limit") set_limit "$2" ;;
"--loop") run_loop ;;
"--saver") set_saver "$2" ;;
esac
