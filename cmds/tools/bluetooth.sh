#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/bluetooth.sh"

cmd_bluetooth() {
    [[ $(has_bluetooth) != "true" ]] && rx_log "error" "No bluetooth adapter detected" && return 1
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
            rx_table_header "󰂳" "Paired Bluetooth Devices"
            bash "$bt_script" --list | while read -r line; do
                local mac=$(echo "$line" | awk '{print $2}')
                local name=$(echo "$line" | cut -d' ' -f3-)
                rx_table_simple "󰂲" "$name ($mac)" "$GRAY"
            done
            rx_table_separator
            rx_table_spacer
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

            rx_table_header "󰘐" "Nearby Bluetooth Devices"

            if [[ -z $nearby_raw ]]; then
                rx_table_simple "󰍉" "No new devices found yet..." "$GRAY"
            else
                echo "$nearby_raw" | while read -r line; do
                    local mac=$(echo "$line" | awk '{print $2}')
                    local name=$(echo "$line" | cut -d' ' -f3-)
                    rx_table_simple "󰍉" "$name ($mac)" "$GRAY"
                done
            fi
            rx_table_separator
            rx_table_spacer
            ;;

        "connect")
            [[ -z $2 ]] && rx_log "error" "Provide a Device MAC address." && return 1
            local mac="$2"

            local is_scanning=$(bluetoothctl show | grep -i "Discovering:" | awk '{print $2}' | xargs)
            if [[ $is_scanning != "yes" ]]; then
                #rx_log "error" "Bluetooth scanning is ${GRAY}OFF${RESET}."
                #rx_log "info" "Scanning must be active to establish a handshake."
                #return 1

                cmd_bluetooth "scan" "on"
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

            rx_table_header "󰂯" "Bluetooth Status"
            rx_table_row "󰈐" "Power Mode:" "${pwr_mode} (Radio: ${pwr_stat^^})" "$mode_color" "20"
            rx_table_row "󰈐" "Discoverable:" "${disc^^}" "$PINK" "20"
            rx_table_row "󰈐" "Pairable:" "${pair^^}" "$PINK" "20"
            rx_table_row_gray "󰂱" "Adapter:" "$chip" "20"
            rx_table_row_gray "󰄀" "Stack Version:" "Bluetooth $ver" "20"
            rx_table_row "󰂲" "Active Conns:" "$conns Device(s)" "$PINK" "20"
            rx_table_separator
            rx_table_spacer
            ;;

        *)
            rx_help_usage "retro bluetooth <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show adapter and connection info"
            rx_help_cmd "scan [on|off]" "Toggle device discovery"
            rx_help_cmd "list" "List paired devices"
            rx_help_cmd "nearby" "Show discoverable devices"
            rx_help_cmd "connect <mac>" "Connect to a device"
            rx_help_cmd "disconnect <mac>" "Disconnect a device"
            rx_help_cmd "forget <mac>" "Remove a paired device"
            rx_help_cmd "discoverable" "Toggle visibility mode"
            rx_help_spacer
            ;;
    esac
}

if [[ $(has_bluetooth) == "true" ]]; then
    register_command "TOOLS" "bluetooth" "Manage bluetooth settings and connections" "cmd_bluetooth"
fi
