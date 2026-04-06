#!/bin/bash

cmd_bluetooth() {
    local bt_script="$RETRO_DIR/scripts/bluetooth_core.sh"
    local action="${1,,}"

    case "$action" in
        "scan")
            local state="${2,,}"
            if [[ $state == "on" ]]; then
                bash "$bt_script" --scan-on
                rx_log "info" "Bluetooth scanning ${PINK}ENABLED${RESET}."
                rx_log "info" "Scan will timeout in 3 minutes."
            else
                bash "$bt_script" --scan-off
                rx_log "info" "Bluetooth scanning ${GRAY}DISABLED${RESET}."
            fi
            ;;

        "list")
            echo -e "\n ${PINK}󰂳 Paired Bluetooth Devices${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            bash "$bt_script" --list | while read -r line; do
                local mac=$(echo "$line" | awk '{print $2}')
                local name=$(echo "$line" | cut -d' ' -f3-)
                echo -e " ${PINK}󰂲${RESET} $name ${GRAY}$mac${RESET}"
            done
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "forget")
            [[ -z $2 ]] && rx_log "error" "Provide a Device MAC address." && return 1
            bash "$bt_script" --forget "$2"
            rx_log "success" "Device $2 has been forgotten."
            ;;

        "nearby")
            local nearby_raw=$(bash "$bt_script" --nearby)

            if [[ $nearby_raw == "ERR_SCAN_OFF" ]]; then
                rx_log "error" "Bluetooth scanning is ${GRAY}OFF${RESET}"
                return 1
            fi

            echo -e "\n ${PINK}󰂰 Nearby Bluetooth Devices${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            if [[ -z $nearby_raw ]]; then
                echo -e " ${GRAY}  No new devices found yet...${RESET}"
            else
                echo "$nearby_raw" | while read -r line; do
                    local mac=$(echo "$line" | awk '{print $2}')
                    local name=$(echo "$line" | cut -d' ' -f3-)
                    echo -e " ${PINK}󰍉${RESET} $name ${GRAY}$mac${RESET}"
                done
            fi
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "connect")
            [[ -z $2 ]] && rx_log "error" "Provide a Device MAC address." && return 1
            local mac="$2"

            local is_scanning=$(bluetoothctl show | grep -i "Discovering:" | awk '{print $2}' | xargs)
            if [[ $is_scanning != "yes" ]]; then
                rx_log "error" "Bluetooth scanning is ${GRAY}OFF${RESET}."
                rx_log "info" "Scanning must be active to establish a handshake."
                return 1
            fi

            rx_log "info" "Attempting to connect to ${PINK}$mac${RESET}..."

            bluetoothctl connect "$mac" >/dev/null 2>&1 &

            local timeout=300
            local count=0
            local user_notified=false

            rx_log "info" "Please accept the pair request in the notification..."

            while [[ $count -lt $timeout ]]; do
                local lock=$(get_var "BT_PAIRING_IN_PROGRESS")

                if [[ $lock == *"$mac"* ]]; then
                    if [[ $user_notified == "false" ]]; then
                        user_notified=true
                    fi
                elif [[ $user_notified == "true" ]]; then
                    break
                fi

                if [[ $(bluetoothctl info "$mac" | grep "Paired: yes") ]]; then
                    break
                fi

                sleep 1
                ((count++))
            done

            if [[ $(bluetoothctl info "$mac" | grep "Paired: yes") ]]; then
                rx_log "success" "Successfully connected to ${PINK}$mac${RESET}!"
            else
                rx_log "error" "Failed to connect. Attempt timed out or was rejected."
            fi
            ;;

        "disconnect")
            [[ -z $2 ]] && rx_log "error" "Provide a Device MAC address." && return 1
            rx_log "info" "Disconnecting ${PINK}$2${RESET}..."

            if bash "$bt_script" --disconnect "$2" >/dev/null 2>&1; then
                rx_log "success" "Device disconnected."
            else
                rx_log "error" "Could not disconnect device."
            fi
            ;;

        "discoverable")
            local result=$(bash "$bt_script" --toggle-discovery)

            if [[ $result == "on" ]]; then
                rx_log "success" "Bluetooth is now ${PINK}VISIBLE${RESET} and ${PINK}PAIRABLE${RESET}."
                rx_log "info" "Visibility will timeout in 3 minutes for security."
            else
                rx_log "info" "Bluetooth visibility ${GRAY}DISABLED${RESET}."
            fi
            ;;

        "status")
            local stats=$(bash "$bt_script" --status)
            IFS='|' read -r pwr_stat pwr_mode disc pair chip ver conns <<<"$stats"

            local mode_color="$PINK"
            [[ $pwr_mode == "SAVER" ]] && mode_color="$MUTE"

            echo -e "\n ${PINK}󰂯 Bluetooth Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            printf " ${PINK}󰈐${RESET} %-20s ${mode_color}%s${RESET} ${GRAY}(Radio: %s)${RESET}\n" "Power Mode:" "$pwr_mode" "${pwr_stat^^}"
            printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Discoverable:" "${disc^^}"
            printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Pairable:" "${pair^^}"
            printf " ${PINK}󰂱${RESET} %-20s ${GRAY}%s${RESET}\n" "Adapter:" "$chip"
            printf " ${PINK}󰄀${RESET} %-20s ${GRAY}Bluetooth %s${RESET}\n" "Stack Version:" "$ver"
            printf " ${PINK}󰂲${RESET} %-20s ${PINK}%s Device(s)${RESET}\n" "Active Conns:" "$conns"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        *)
            rx_log "info" "Usage: retro bluetooth <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show adapter and connection info"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "scan [on|off]" "Toggle device discovery"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List paired devices"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "nearby" "Show discoverable devices"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "connect <mac>" "Connect to a device"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "disconnect <mac>" "Disconnect a device"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "forget <mac>" "Remove a paired device"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "discoverable" "Toggle visibility mode"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "bluetooth" "Manage bluetooth settings and connections" "cmd_bluetooth"
