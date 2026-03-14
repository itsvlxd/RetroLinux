#!/bin/bash

cmd_battery() {
    local battery_script="$RETRO_DIR/scripts/battery_core.sh"
    local action="$1"
    local value="$2"
    local options="$3"

    case "$action" in
        "raw")
            echo "$($battery_script --raw)"
            ;;

        "status")
            local raw_output=$($battery_script --info)
            IFS='|' read -r cap stat health power volt model saver sot <<<"$raw_output"

            local watts=$(awk "BEGIN {printf \"%.2f\", $power / 1000000}")
            local volts=$(awk "BEGIN {printf \"%.2f\", $volt / 1000000}")

            [[ $watts == .* ]] && watts="0$watts"
            [[ $volts == .* ]] && volts="0$volts"

            local bat_icon=$(get_battery_icon "$cap" "$stat")

            echo -e "\n ${PINK}󰂀 Battery: ${RESET}${model^^}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            printf " ${PINK}%s${RESET} %-14s %s%% (%s)\n" "$bat_icon" "Charge:" "$cap" "$stat"
            printf " ${PINK}󰚥${RESET} %-14s %s\n" "Health:" "$health"
            printf " ${PINK}󱐋${RESET} %-14s %s W\n" "Usage Draw:" "$watts"
            printf " ${PINK}󱈑${RESET} %-14s %s V\n" "Voltage:" "$volts"

            if [[ $sot != "N/A" ]]; then
                printf " ${PINK}󰔚${RESET} %-14s %b\n" "On Battery:" "${sot}"
            fi

            printf " ${PINK}󰌪${RESET} %-14s %s\n" "Saver Mode:" "$saver"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            local filled=$((cap / 5))
            printf " ${PINK}󰈈${RESET} "

            for ((i = 0; i < 20; i++)); do
                if ((i < filled)); then
                    r=$((200 + (41 * i / 19)))
                    g=$((200 - (86 * i / 19)))
                    b=$((200 + (7 * i / 19)))

                    printf "\e[38;2;${r};${g};${b}m█\e[0m"
                else
                    printf "\e[38;2;69;71;90m░\e[0m"
                fi
            done

            echo -e "\n"
            ;;

        "stats")
            echo -e "\n ${PINK}󰂀 Battery Usage Stats: ${RESET}Last 7 Days"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            for i in {0..6}; do
                local entry=$(get_var "BAT_STATS_$i")
                [[ -z $entry || $entry == "null" ]] && continue

                IFS='|' read -r d_date d_cycles d_seconds <<<"$entry"

                local day_name=$(date -d "$d_date" +%a)

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

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "limit")
            $battery_script --limit "$value" "$options" && rx_log "success" "Battery limit is now $2%" || rx_log "error" "Your hardware doesn't support charge limits."
            ;;

        "saver")
            [[ -z $value ]] && rx_log "info" "Usage: retro --battery saver [true|false|0-100]" && return 1

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

        *) rx_log "info" "Usage: retro --battery [status|stats|limit|saver|raw]" ;;
    esac
}

register_command "TOOLS" "-bat|--battery" "Smart battery management utility" "cmd_battery"
