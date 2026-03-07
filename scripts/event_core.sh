#!/bin/bash

source "$RETRO_DIR/scripts/lib/battery.sh"
source "$RETRO_DIR/scripts/lib/variable.sh"

EVENT_DIR="$RETRO_DIR/scripts/events"

broadcast_event() {
    local event_name="$1"
    local args="${@:2}"

    for hook_file in "$EVENT_DIR"/*.sh; do
        if [[ -f $hook_file ]]; then
            (
                source "$hook_file"
                if declare -f "$event_name" >/dev/null; then
                    "$event_name" $args
                fi
            )
        fi
    done
}

run_event_loop() {
    local last_bat_stat=$(get_bat_status)
    local last_on_battery=$(is_on_battery)
    local last_bat_saver=$(get_var "BAT_SAVER_ACTIVE")
    local last_notified_level=0

    local low_thresh=$(get_var "BAT_NOTIFY_THRESHOLD")
    local crit_thresh=$(get_var "BAT_NOTIFY_CRITICAL_THRESHOLD")
    local saver_thresh=$(get_var "BAT_SAVER_THRESHOLD")

    local last_pwr_profile=$(get_var "PWR_CURRENT")

    local tick_counter=0

    # TODO: Need to implement the on_event_loop_start logic
    broadcast_event "on_event_loop_start"

    while true; do
        local current_bat_stat=$(get_bat_status)
        local current_on_battery=$(is_on_battery)
        local current_pwr_profile=$(get_var "PWR_CURRENT")
        local current_cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")

        if ((tick_counter % 10 == 0)); then
            low_thresh=$(get_var "BAT_NOTIFY_THRESHOLD")
            crit_thresh=$(get_var "BAT_NOTIFY_CRITICAL_THRESHOLD")
            saver_thresh=$(get_var "BAT_SAVER_THRESHOLD")
            forced_saver=$(get_var "BAT_SAVER_FORCED")
        fi

        if [[ $current_on_battery != "$last_on_battery" ]]; then
            if [[ $current_on_battery == "true" ]]; then
                broadcast_event "on_power_disconnect" "$current_cap"
            else
                broadcast_event "on_power_connect" "$current_cap"
                last_notified_level="$current_on_battery"
            fi
            last_on_battery="$current_on_battery"
            tick_counter=0
        fi

        local target_saver="false"
        if [[ $forced_saver == "true" ]]; then
            target_saver=$(get_var "BAT_SAVER_ACTIVE")
        else
            if [[ $current_bat_stat == "discharging" && $current_cap -le $saver_thresh ]]; then
                target_saver="true"
            fi
        fi

        if [[ $target_saver != "$last_bat_saver" ]]; then
            set_var "BAT_SAVER_ACTIVE" "$target_saver"

            if [[ $target_saver == "true" ]]; then
                broadcast_event "on_battery_saver_enabled"
            else
                broadcast_event "on_battery_saver_disabled"
            fi
            last_bat_saver="$target_saver"
        fi

        if [[ $current_bat_stat == "discharging" ]]; then
            if [[ $current_cap -le $crit_thresh ]]; then
                if [[ $current_cap -ne $last_notified_level ]]; then
                    broadcast_event "on_battery_critical" "$current_cap"
                    last_notified_level="$current_cap"
                fi
            elif [[ $current_cap -le $low_thresh ]]; then
                if [[ $current_cap -ne $last_notified_level ]]; then
                    broadcast_event "on_battery_low" "$current_cap"
                    last_notified_level="$current_cap"
                fi
            fi
        fi

        if [[ $current_pwr_profile != $last_pwr_profile ]]; then
            broadcast_event "on_power_profile_changed" "$current_pwr_profile"

            last_notified_level=0
            last_pwr_profile="$current_pwr_profile"
        fi

        ((tick_counter++))
        sleep 1
    done
}

case "$1" in
    "--loop") run_event_loop ;;
    "--trigger") broadcast_event "$2" "${@:3}" ;;
esac
