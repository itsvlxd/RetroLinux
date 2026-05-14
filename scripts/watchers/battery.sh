#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/lib/battery.sh"

check_battery_state() {
    local current_bat_stat
    current_bat_stat=$(get_bat_status)
    local current_cap
    current_cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")

    local forced_saver
    forced_saver=$(get_var "BAT_SAVER_FORCED")
    local target_saver="false"

    if [[ $forced_saver == "true" ]]; then
        target_saver=$(get_var "BAT_SAVER_ACTIVE" "false")
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

    local current_pwr_profile
    current_pwr_profile=$(get_var "PWR_CURRENT" "")
    if [[ $current_pwr_profile != "$last_pwr_profile" ]]; then
        broadcast_event "on_power_profile_changed" "$current_pwr_profile"
        last_notified_level=0
        last_pwr_profile="$current_pwr_profile"
    fi
}

check_battery_usage() {
    local p_raw
    p_raw=$(cat "$BAT_PATH/power_now" 2>/dev/null || echo "0")

    if [[ $p_raw -eq 0 ]]; then
        local v_raw
        v_raw=$(cat "$BAT_PATH/voltage_now" 2>/dev/null || echo "0")
        local i_raw
        i_raw=$(cat "$BAT_PATH/current_now" 2>/dev/null || echo "0")
        p_raw=$((i_raw * v_raw / 1000000))
    fi

    local total_w
    total_w=$(awk "BEGIN {printf \"%.2f\", $p_raw / 1000000}")

    local proc_list
    proc_list=$(ps -eo %cpu,pid,comm --sort=-%cpu 2>/dev/null | grep -vE '(%CPU|\[|ps|grep|awk|retro)' | head -n 10 | awk '{print $1"|"$2"|"$3}')

    local outlier_data
    outlier_data=$(echo "$proc_list" | awk -F'|' -v total_w="$total_w" '
    {
        n=$3
        if (n ~ /Isolated/) n="Zen-Worker"
        if (n ~ /Web/) n="Web-Content"

        cpu[NR]=$1; pid[NR]=$2; name[NR]=n;
        sum += $1;
    }
    END {
        if (NR < 3) exit
        top_cpu = cpu[1]; top_pid = pid[1]; top_name = name[1];
        others_sum = sum - top_cpu;
        avg_others = others_sum / (NR - 1);
        app_w = (top_cpu/100) * total_w;

        if (avg_others > 0 && top_cpu > (avg_others * 3) && top_cpu > 5.0 && app_w > 2.0) {
            printf "true|%s|%.2f|%s|%s", top_name, app_w, top_cpu, top_pid;
        } else {
            print "false|none|0|0|0";
        }
    }')

    IFS='|' read -r is_outlier rogue_name rogue_watts rogue_cpu rogue_pid <<<"$outlier_data"

    if [[ $is_outlier == "true" ]]; then
        local now
        now=$(date +%s)
        local last_app
        last_app=$(get_var "BAT_LAST_NOTIFIED_APP")
        local last_time
        last_time=$(get_var "BAT_LAST_NOTIFIED_TIME")
        [[ -z $last_time || $last_time == "null" ]] && last_time=0

        local cooldown=600
        local time_diff=$((now - last_time))
        local ignore_list
        ignore_list=$(get_var "BAT_IGNORE_APPS")

        if [[ "|$ignore_list|" != *"|$rogue_name|"* ]] && { [[ $rogue_name != "$last_app" ]] || ((time_diff > cooldown)); }; then
            broadcast_event "on_battery_usage_high" "$rogue_name" "$rogue_watts" "$rogue_cpu" "$rogue_pid"

            set_var "BAT_LAST_NOTIFIED_APP" "$rogue_name"
            set_var "BAT_LAST_NOTIFIED_TIME" "$now"
        fi
    else
        set_var "BAT_LAST_NOTIFIED_APP" "none"
    fi
}

start_watcher_battery() {
    [[ $(has_battery) != "true" ]] && exit 0

    last_bat_saver=$(get_var "BAT_SAVER_ACTIVE" "false")
    last_notified_level=0
    last_pwr_profile=$(get_var "PWR_CURRENT" "")

    saver_thresh=$(get_var "BAT_SAVER_THRESHOLD" "20")
    low_thresh=$(get_var "BAT_NOTIFY_THRESHOLD" "20")
    crit_thresh=$(get_var "BAT_NOTIFY_CRITICAL_THRESHOLD" "5")

    local tick_counter=0

    while true; do
        if ((tick_counter % 10 == 0)); then
            saver_thresh=$(get_var "BAT_SAVER_THRESHOLD" "20")
            low_thresh=$(get_var "BAT_NOTIFY_THRESHOLD" "20")
            crit_thresh=$(get_var "BAT_NOTIFY_CRITICAL_THRESHOLD" "5")
        fi

        check_battery_state

        if ((tick_counter % 60 == 0)); then
            check_battery_usage
        fi

        ((tick_counter++))
        sleep 15
    done
}