#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/battery.sh"

cmd_battery() {
    [[ $(has_battery) != "true" ]] && rx_log "error" "No battery detected" && return 1
    local battery_script="$RETRO_DIR/scripts/battery_core.sh"
    local action="${1,,}"
    local value="$2"
    local options="$3"

    case "$action" in
        "raw")
            echo "$($battery_script --raw)"
            ;;

        "status")
            local raw_output=$($battery_script --info)
            IFS='|' read -r cap stat health power volt model saver sot est <<<"$raw_output"

            local watts=$(awk "BEGIN {printf \"%.2f\", $power / 1000000}")
            local volts=$(awk "BEGIN {printf \"%.2f\", $volt / 1000000}")

            [[ $watts == .* ]] && watts="0$watts"
            [[ $volts == .* ]] && volts="0$volts"

            local bat_icon=$(get_battery_icon "$cap" "$stat")

            rx_table_header "󰂀" "Battery: ${model^^}"
            rx_table_row "󰓅" "Charge:" "${cap}%" "$PINK" "14"
            rx_table_row "󰚥" "Health:" "$health" "$PINK" "14"
            rx_table_row "󱐋" "Usage Draw:" "$watts W" "$PINK" "14"
            rx_table_row "󱈑" "Voltage:" "$volts V" "$PINK" "14"

            if [[ $sot != "N/A" ]]; then
                rx_table_row "󰔚" "On Battery:" "$sot" "$PINK" "14"
            fi

            if [[ $est != "N/A" ]]; then
                local est_icon="󱎫"
                [[ $stat == *"charging"* ]] && est_icon="󱐋"
                rx_table_row "$est_icon" "Remaining:" "$est" "$PINK" "14"
            fi

            rx_table_row "󰌪" "Saver Mode:" "$saver" "$PINK" "14"

            rx_table_separator

            local filled=$((cap / 5))
            printf " ${PINK}󰏰${RESET} "

            for ((i = 0; i < 20; i++)); do
                if ((i < filled)); then
                    printf "${PINK}█${RESET}"
                else
                    printf "${GRAY}░${RESET}"
                fi
            done

            echo ""
            rx_table_spacer
            ;;

        "stats")
            rx_table_header "󰂀" "Battery Usage Stats: Last 7 Days"

            local has_data=false
            for i in {0..6}; do
                local entry=$(get_var "BAT_STATS_$i")
                [[ -z $entry || $entry == "null" ]] && continue
                has_data=true

                IFS='|' read -r d_date d_cycles d_seconds <<<"$entry"

                local day_name=$(date -d "$d_date" +%a 2>/dev/null || echo "$d_date")

                local divisor=$d_cycles
                ((divisor == 0)) && divisor=1
                local avg_min=$(((d_seconds / divisor) / 60))

                local bar_size=$((avg_min / 30))
                ((bar_size > 15)) && bar_size=15

                local bar=""
                for ((j = 0; j < bar_size; j++)); do bar+="${PINK}█${RESET}"; done
                for ((j = bar_size; j < 15; j++)); do bar+="${MUTE}░${RESET}"; done

                printf " ${PINK} ${RESET}%s ${RESET}%b [${PINK}%s${RESET} charge(s)] Avg: ${PINK}%sm${RESET}\n" \
                    "$day_name" "$bar" "$d_cycles" "$avg_min"
            done

            if [[ $has_data != "true" ]]; then
                rx_table_simple "󰂀" "No usage data recorded yet" "$MUTE"
                rx_table_simple "󰇚" "Stats are recorded when on battery power" "$MUTE"
            fi

            rx_table_separator
            rx_table_spacer
            ;;

        "usage")
            local raw_output=$($battery_script --raw)

            if [[ $raw_output != "discharging" ]]; then
                rx_log "error" "Cannot calculate app usage while charging or fully charged."
                return 1
            fi

            local requested_count="${value:-10}"
            [[ ! $requested_count =~ ^[0-9]+$ ]] && requested_count=10

            local raw_data=$($battery_script --usage "$requested_count")
            local total_watts=$(echo "$raw_data" | head -n 1)
            local procs=$(echo "$raw_data" | tail -n +2)

            rx_table_header "󱈑" "Power Consumption: ${total_watts}W Total"

            local count=0
            while IFS='|' read -r cpu cmd; do
                [[ -z $cpu || $cpu == "0.0" ]] && continue
                ((count++))

                local est_w=$(awk "BEGIN {printf \"%.2f\", ($cpu / 100) * $total_watts}")

                printf " ${PINK}󰣖 ${RESET}%-22s ${GRAY}%-12s${RESET} ${PINK}%sW${RESET}\n" \
                    "${cmd:0:20}" "${cpu}%" "$est_w"
            done <<<"$procs"

            for ((i = count; i < requested_count; i++)); do
                printf " ${MUTE}%-22s %-12s %-8s${RESET}\n" "---" "0.0%" "0.00W"
            done

            rx_table_separator
            rx_table_spacer
            ;;

        "limit")
            $battery_script --limit "$value" "$options" && rx_log "success" "Battery limit is now $2%" || rx_log "error" "Your hardware doesn't support charge limits."
            ;;

        "saver")
            [[ -z $value ]] && rx_log "info" "Usage: retro battery saver [true|false|0-100]" && return 1

            local force_tag=""
            if [[ $options == "-f" || $options == "--force" ]]; then
                force_tag=" ${GRAY}(Forced)${RESET}"
            fi

            if $battery_script --saver "$value" "$options"; then
                if [[ $value == "true" ]]; then
                    rx_log "success" "Battery Saver is now ${PINK}ON${RESET}$force_tag"
                elif [[ $value == "false" ]]; then
                    rx_log "success" "Battery Saver is now ${PINK}OFF${RESET}$force_tag"
                elif [[ $value == "0" ]]; then
                    rx_log "success" "Auto-saver is now ${PINK}disabled${RESET}."
                else
                    rx_log "success" "Got it. Auto-saver will kick in at ${PINK}${value}%${RESET}."
                fi
            else
                rx_log "error" "Couldn't update the saver settings."
            fi
            ;;

        *)
            rx_help_usage "retro battery <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show battery info and charge bar"
            rx_help_cmd "stats" "Show 7-day battery usage history"
            rx_help_cmd "usage [count]" "List top power-consuming processes"
            rx_help_cmd "limit <percent>" "Set battery charge threshold"
            rx_help_cmd "saver [mode] [-f]" "Configure battery saver mode"
            rx_help_cmd "raw" "Output raw battery status string"
            rx_help_spacer
            ;;
    esac
}

if [[ $(has_battery) == "true" ]]; then
    register_command "TOOLS" "battery" "Smart battery management utility" "cmd_battery"
fi
