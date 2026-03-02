#!/bin/bash

cmd_battery() {
    local battery_script="$RETRO_DIR/scripts/battery_core.sh"
    local action="$1"
    local value="$2"

    case "$action" in
    "raw")
        echo "$($battery_script --raw)"
        ;;
    "status")
        local raw_output=$($battery_script --info)
        IFS='|' read -r cap stat health power volt model <<<"$raw_output"

        local watts=$(awk "BEGIN {printf \"%.2f\", $power / 1000000}")
        local volts=$(awk "BEGIN {printf \"%.2f\", $volt / 1000000}")

        [[ "$watts" == .* ]] && watts="0$watts"
        [[ "$volts" == .* ]] && volts="0$volts"

        local theme_color="$PINK"
        [[ $cap -lt 20 ]] && theme_color="\e[31m"

        echo -e "\n ${theme_color}󱐋 Battery: ${RESET}${model^^}"
        echo -e " ${theme_color}󰇝${MUTE} ───────────────────────────────────────"

        printf " ${theme_color}󰁹${RESET} %-14s %s%% (%s)\n" "Charge:" "$cap" "$stat"
        printf " ${theme_color}󰚥${RESET} %-14s %s\n" "Health:" "$health"
        printf " ${theme_color}󱐋${RESET} %-14s %s W\n" "Usage:" "$watts"
        printf " ${theme_color}󱈑${RESET} %-14s %s V\n" "Voltage:" "$volts"

        echo -e " ${theme_color}󰇝${MUTE} ───────────────────────────────────────"

        local filled=$((cap / 5))
        local empty=$((20 - filled))
        printf " ${theme_color}󰈈${RESET} ["

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

        echo -e "]\n"
        ;;
    "limit")
        $battery_script --limit "$value" && rx_log "success" "Limit set to $2%" || rx_log "error" "Not supported"
        ;;
    "saver")
        [[ -z "$value" ]] && rx_log "info" "Usage: retro --battery saver [true|false|0-100]" && return 1

        if $battery_script --saver "$value"; then
            if [[ "$value" == "true" ]]; then
                rx_log "success" "Battery Saver: ${PINK}Forced ON"
            elif [[ "$value" == "false" ]]; then
                rx_log "success" "Battery Saver: ${PINK}Forced OFF"
            elif [[ "$value" == "0" ]]; then
                rx_log "success" "Battery Saver threshold: ${PINK}Disabled"
            else
                rx_log "success" "Battery Saver threshold set to: ${PINK}${value}%"
            fi
        else
            rx_log "error" "Could not update saver state."
        fi
        ;;
    "loop")
        pkill -f "battery_core.sh --loop"
        rx_log "info" "Starting Battery Monitor Daemon..."

        nohup bash "$battery_script" --loop >/dev/null 2>&1 &
        rx_log "success" "Daemon is now monitoring in background."
        ;;
    *) rx_log "info" "Usage: retro --battery [status|limit|saver|loop|raw]" ;;
    esac
}

register_command "TOOLS" "-bat|--battery" "Smart battery management utility" "cmd_battery"
