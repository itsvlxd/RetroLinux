#!/bin/bash

source "$RETRO_DIR/scripts/lib/battery.sh"
source "$RETRO_DIR/scripts/lib/variable.sh"

EVENT_DIR="$RETRO_DIR/scripts/events"

# TODO: add modules rules like no_deps_uninstall

broadcast_event() {
    local event_name="$1"
    shift

    for hook_file in "$EVENT_DIR"/*.sh; do
        if [[ -f $hook_file ]]; then
            (
                source "$hook_file"
                if declare -f "$event_name" >/dev/null; then
                    "$event_name" "$@"
                fi
            )
        fi
    done
}

run_event_loop() {
    local last_bat_stat=$(get_bat_status)
    local last_on_battery=$(is_on_battery)
    local last_bat_saver=$(get_var "BAT_SAVER_ACTIVE")

    local last_usb_list=""
    local mount_root="$HOME/Mounts"
    local last_notified_level=0
    mkdir -p "$mount_root"

    local low_thresh=$(get_var "BAT_NOTIFY_THRESHOLD")
    local crit_thresh=$(get_var "BAT_NOTIFY_CRITICAL_THRESHOLD")
    local saver_thresh=$(get_var "BAT_SAVER_THRESHOLD")

    local last_pwr_profile=$(get_var "PWR_CURRENT")

    local slideshow_tick=0
    local current_rand_target=0

    local tick_counter=0

    # TODO: Need to implement the on_event_loop_start logic
    broadcast_event "on_event_loop_start"

    while true; do
        local notify_on_high_bat_usage=$(get_var "NOTIFY_ON_HIGH_BAT_USAGE")

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

        local slideshow_active=$(get_var "WALL_SLIDESHOW_ACTIVE" "false")

        if [[ $slideshow_active == "true" ]]; then
            local interval=$(get_var "WALL_SLIDESHOW_INTERVAL" "300")
            local target_ticks=$interval

            if [[ $interval == "random" ]]; then
                if ((current_rand_target == 0)); then
                    current_rand_target=$((RANDOM % 900 + 300))
                fi
                target_ticks=$current_rand_target
            fi

            if ((slideshow_tick >= target_ticks)); then
                broadcast_event "on_slideshow_tick"
                slideshow_tick=0
                current_rand_target=0
            fi

            ((slideshow_tick++))
        else
            slideshow_tick=0
        fi

        if ((tick_counter % 15 == 0)) && [[ $current_on_battery == "true" ]]; then
            local p_raw=$(cat "$BAT_PATH/power_now" 2>/dev/null || echo "0")
            if [[ $p_raw -eq 0 ]]; then
                local v_raw=$(cat "$BAT_PATH/voltage_now" 2>/dev/null || echo "0")
                local i_raw=$(cat "$BAT_PATH/current_now" 2>/dev/null || echo "0")
                p_raw=$((i_raw * v_raw / 1000000))
            fi
            local total_w=$(awk "BEGIN {printf \"%.2f\", $p_raw / 1000000}")
            local proc_list=$(ps -eo %cpu,pid,comm --sort=-%cpu | grep -vE '(%CPU|\[|ps|grep|awk|retro)' | head -n 10 | awk '{print $1"|"$2"|"$3}')

            local outlier_data=$(echo "$proc_list" | awk -F'|' -v total_w="$total_w" '
            {
                n=$3; 
                if (n ~ /Isolated/) n="Zen-Worker"; 
                if (n ~ /Web/) n="Web-Content";
                
                cpu[NR]=$1; pid[NR]=$2; name[NR]=n;
                sum += $1;
            }
            END {
                if (NR < 3) exit;
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
                local now=$(date +%s)
                local last_app=$(get_var "BAT_LAST_NOTIFIED_APP")
                local last_time=$(get_var "BAT_LAST_NOTIFIED_TIME")
                [[ -z $last_time || $last_time == "null" ]] && last_time=0

                local cooldown=600
                local time_diff=$((now - last_time))
                local ignore_list=$(get_var "BAT_IGNORE_APPS")

                if [[ "|$ignore_list|" != *"|$rogue_name|"* ]] && { [[ $rogue_name != "$last_app" ]] || ((time_diff > cooldown)); }; then
                    broadcast_event "on_battery_usage_high" "$rogue_name" "$rogue_watts" "$rogue_cpu" "$rogue_pid"

                    set_var "BAT_LAST_NOTIFIED_APP" "$rogue_name"
                    set_var "BAT_LAST_NOTIFIED_TIME" "$now"
                fi
            else
                set_var "BAT_LAST_NOTIFIED_APP" "none"
            fi
        fi

        if ((tick_counter % 2 == 0)); then
            local current_usb_list=$(lsblk -nlo NAME,RM,TYPE | awk '$2=="1" && $3=="part" {print $1}' | xargs)
            local ignore_list=$(get_var "USB_IGNORE_DRIVES")

            for dev_name in $current_usb_list; do
                if [[ ! " $last_usb_list " =~ " $dev_name " ]]; then
                    local dev_path="/dev/$dev_name"
                    local label=$(lsblk -nlo LABEL "$dev_path" | xargs)
                    [[ -z $label ]] && label="USB_$dev_name"

                    local actual_mount=$(findmnt -nlo TARGET "$dev_path")

                    if [[ -z $actual_mount ]]; then
                        udisksctl mount -b "$dev_path" --no-user-interaction >/dev/null 2>&1
                        sleep 0.5
                        actual_mount=$(findmnt -nlo TARGET "$dev_path")
                    fi

                    if [[ -n $actual_mount ]]; then
                        local symlink_path="$mount_root/$label"
                        ln -sfn "$actual_mount" "$symlink_path"

                        if [[ "|$ignore_list|" != *"|$label|"* ]]; then
                            broadcast_event "on_usb_connected" "$label" "$symlink_path"
                        fi
                    fi
                fi
            done

            for old_dev in $last_usb_list; do
                if [[ ! " $current_usb_list " =~ " $old_dev " ]]; then
                    broadcast_event "on_usb_disconnected" "$old_dev" "$mount_root"
                fi
            done

            last_usb_list="$current_usb_list"
        fi

        local pkg_min=$(get_var "RETRO_PKG_UPDATE_MIN" "20")
        local pkg_interval=$((pkg_min * 60))
        local now=$(date +%s)

        if ((tick_counter % 60 == 0)) && ((now - last_pkg_check > pkg_interval)); then
            local helper=$(get_var "PKG_HELPER" "yay")

            local pac_count=$(checkupdates 2>/dev/null | wc -l)
            local aur_count=$($helper -Qu 2>/dev/null | wc -l)
            local total=$((pac_count + aur_count))

            local raw_thresh=$(get_var "RETRO_PKG_UPDATE_THRESH" "20")
            local thresh=$(echo "$raw_thresh" | tr -dc '0-9')
            [[ -z $thresh ]] && thresh=20

            if [ "$total" -gt 0 ] && [ "$total" -ge "$thresh" ]; then
                local sample=$( (
                    checkupdates 2>/dev/null
                    $helper -Qu 2>/dev/null
                ) | head -n 3 | awk '{print $1}' | xargs | sed 's/ /, /g')
                broadcast_event "on_pkg_updates_available" "$total" "$sample"
            fi

            last_pkg_check=$now
        fi

        local ignored_macs=$(get_var "BT_MAC_IGNORE")
        local currently_pairing=$(get_var "BT_PAIRING_IN_PROGRESS")

        local pairing_dev=$(bluetoothctl devices Connected | awk '{print $2}' | while read -r mac; do
            if [[ "|$ignored_macs|" != *"|$mac|"* ]] && [[ "|$currently_pairing|" != *"|$mac|"* ]]; then
                if [[ $(bluetoothctl info "$mac" | grep "Paired: no") ]]; then
                    echo "$mac"
                    break
                fi
            fi
        done)

        if [[ -n $pairing_dev ]]; then
            local dev_name=$(bluetoothctl info "$pairing_dev" | grep "Name:" | sed 's/.*Name: //' | xargs)
            [[ -z $dev_name ]] && dev_name=$(bluetoothctl info "$pairing_dev" | grep "Alias:" | sed 's/.*Alias: //' | xargs)

            broadcast_event "on_bluetooth_pairing_request" "$dev_name" "$pairing_dev"
        fi

        local current_connected_list=$(bluetoothctl devices Connected | awk '{print $2}' | xargs)

        for mac in $current_connected_list; do
            if [[ ! " $last_bt_connected_list " =~ " $mac " ]]; then
                if [[ $(bluetoothctl info "$mac" | grep "Paired: yes") ]]; then
                    local dev_name=$(bluetoothctl info "$mac" | grep "Name:" | sed 's/.*Name: //' | xargs)
                    broadcast_event "on_bluetooth_connected" "$dev_name" "$mac"
                fi
            fi
        done

        for mac in $last_bt_connected_list; do
            if [[ ! " $current_connected_list " =~ " $mac " ]]; then
                local dev_name=$(bluetoothctl info "$mac" | grep "Name:" | sed 's/.*Name: //' | xargs)
                broadcast_event "on_bluetooth_disconnected" "$dev_name" "$mac"
            fi
        done

        last_bt_connected_list="$current_connected_list"

        ((tick_counter++))
        sleep 1
    done
}

case "$1" in
    "--loop") run_event_loop ;;
    "--trigger") broadcast_event "$2" "${@:3}" ;;
esac
