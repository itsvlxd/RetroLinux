#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "battery"

get_info() {
    [[ $(has_battery) != "true" ]] && echo "no-battery" && return 1

    local stat=$(get_bat_status)
    local cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")
    local health=$(cat "$BAT_PATH/capacity_level" 2>/dev/null || echo "N/A")
    local model=$(cat "$BAT_PATH/model_name" 2>/dev/null || echo "Generic")
    local p_raw=$(cat "$BAT_PATH/power_now" 2>/dev/null || echo "0")
    local v_raw=$(cat "$BAT_PATH/voltage_now" 2>/dev/null || echo "0")
    local energy=$(cat "$BAT_PATH/energy_now" 2>/dev/null || cat "$BAT_PATH/charge_now" 2>/dev/null || echo "0")
    local power=$(cat "$BAT_PATH/power_now" 2>/dev/null || cat "$BAT_PATH/current_now" 2>/dev/null || echo "0")
    local estimate="N/A"

    local saver=$(get_var "BAT_SAVER_ACTIVE")

    if [[ $stat == *"discharging"* ]]; then
        local start_ts=$(get_var "BAT_DISCONNECT_TIME")

        if [[ -n $start_ts && $start_ts != "null" ]]; then
            local now=$(date +%s)
            local diff=$((now - start_ts))

            local days=$((diff / 86400))
            local hrs=$(((diff % 86400) / 3600))
            local mins=$(((diff % 3600) / 60))
            local secs=$((diff % 60))

            if ((days > 0)); then
                sot_label="${days}d $(printf "%02dh %02dm %02ds" $hrs $mins $secs)"
            elif ((hrs > 0)); then
                sot_label="$(printf "%02dh %02dm %02ds" $hrs $mins $secs)"
            else
                sot_label="$(printf "%02dm %02ds" $mins $secs)"
            fi
        else
            local now=$(date +%s)
            set_var "BAT_DISCONNECT_TIME" "$now"
            sot_label="00m 00s"
        fi
    else
        sot_label="N/A"
    fi

    if [[ $stat == *"discharging"* && $power -gt 0 ]]; then
        local seconds_left=$((energy * 3600 / power))

        local e_hrs=$((seconds_left / 3600))
        local e_mins=$(((seconds_left % 3600) / 60))

        estimate="$(printf "%dh %dm" $e_hrs $e_mins)"
    elif [[ $stat == *"charging"* && $power -gt 0 ]]; then
        local full_energy=$(cat "$BAT_PATH/energy_full" 2>/dev/null || cat "$BAT_PATH/charge_full" 2>/dev/null || echo "0")
        local needed=$((full_energy - energy))
        if [[ $needed -gt 0 ]]; then
            local seconds_to_full=$((needed * 3600 / power))
            estimate="$(printf "%dh %dm to full" $((seconds_to_full / 3600)) $(((seconds_to_full % 3600) / 60)))"
        fi
    fi

    if [[ $p_raw -eq 0 ]]; then
        local i_raw=$(cat "$BAT_PATH/current_now" 2>/dev/null || echo "0")
        p_raw=$((i_raw * v_raw / 1000000))
    fi

    local saver_label="OFF"

    if [[ $saver == "true" ]]; then
        saver_label="ON"
    fi

    echo "$cap|$stat|$health|$p_raw|$v_raw|$model|$saver_label|$sot_label|$estimate"
}

set_limit() {
    local limit="$1"
    local path="$BAT_PATH/charge_control_end_threshold"

    [[ -f $path ]] && echo "$limit" | sudo tee "$path" >/dev/null || return 1
}

get_internal_monitor() {
    hyprctl monitors -j | jq -r '.[] | select(.name | startswith("eDP")) | .name' | head -n 1
}

sync_hyprland_power() {
    local state="$1"

    local mon_name=$(get_internal_monitor)
    if [[ -z $mon_name ]]; then
        return 0
    fi

    read -r w h x y scale <<< $(hyprctl monitors -j | jq -r --arg n "$mon_name" \
        '.[] | select(.name==$n) | "\(.width) \(.height) \(.x) \(.y) \(.scale)"')

    if [[ $state == "true" ]]; then
        hyprctl keyword monitor "$mon_name, ${w}x${h}@60, ${x}x${y}, $scale" >/dev/null

        if command -v brightnessctl >/dev/null 2>&1; then
            brightnessctl set 30% >/dev/null 2>&1
        fi
    else
        hyprctl keyword monitor "$mon_name, highres, ${x}x${y}, $scale" >/dev/null

        local blur_state=$(get_var "RETRO_BLUR" "true")
        local shadow_state=$(get_var "RETRO_SHADOW" "true")
    fi
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

get_usage() {
    local limit="${1:-10}"

    local p_raw=$(cat "$BAT_PATH/power_now" 2>/dev/null || echo "0")
    local v_raw=$(cat "$BAT_PATH/voltage_now" 2>/dev/null || echo "0")

    if [[ $p_raw -eq 0 ]]; then
        local i_raw=$(cat "$BAT_PATH/current_now" 2>/dev/null || echo "0")
        p_raw=$((i_raw * v_raw / 1000000))
    fi

    [[ $p_raw -le 0 ]] && p_raw=10000
    local total_watts=$(awk "BEGIN {printf \"%.2f\", $p_raw / 1000000}")

    local proc_data=$(ps -eo %cpu,comm --sort=-%cpu | grep -vE '(%CPU|\[|ps|grep|awk|retro)' | awk '
    {
        name=$2;
        if (name ~ /Isolated/) name="Zen-Worker";
        if (name ~ /Web/) name="Web-Content";
        sum[name]+=$1
    } 
    END {
        for (i in sum) print sum[i]"|"i
    }' | sort -rn | head -n "$limit")

    echo "$total_watts"
    echo "$proc_data"
}

case "$1" in
    "--raw") get_bat_status ;;
    "--info") get_info ;;
    "--limit") set_limit "$2" ;;
    "--loop") run_loop ;;
    "--usage") get_usage "$2" ;;
    "--saver") set_saver "$2" "$3" ;;
    "--log") log_battery_event "$2" "$3" ;;
esac
