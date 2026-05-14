#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/bluetooth.sh"
source "$RETRO_DIR/lib/icons.sh"

cmd_bluetooth() {
    [[ $(has_bluetooth) != "true" ]] && rx_log "error" "No bluetooth adapter detected" && return 1

    local bt_script="$RETRO_DIR/scripts/bluetooth_core.sh"
    local action="${1,,}"

    _normalize_mac() {
        local raw_mac="$1"
        local mac=$(echo "$raw_mac" | tr '[:lower:]' '[:upper:]' | tr -d ':-')
        if [[ ${#mac} -eq 12 ]]; then
            echo "${mac:0:2}:${mac:2:2}:${mac:4:2}:${mac:6:2}:${mac:8:2}:${mac:10:2}"
        else
            echo "$raw_mac"
        fi
    }

    _bt_list() {
        local raw
        raw=$(bash "$bt_script" --paired-detailed)
        rx_table_header "󰂳" "Paired Bluetooth Devices"

        if [[ -z $raw ]]; then
            rx_table_simple "󰍉" "No paired devices found." "$GRAY"
        else
            echo "$raw" | while IFS='|' read -r _ _ device_type mac name connected; do
                [[ -z $device_type ]] && continue

                local icon type_color
                icon=$(get_bt_device_type_icon "$device_type")
                [[ $device_type == "phone" || $device_type == "computer" || $device_type == "audio" || $device_type == "audio+input" || $device_type == "controller" ]] && type_color="$PINK" || type_color="$GRAY"

                local conn_status conn_color
                if [[ $connected == "yes" ]]; then
                    conn_status="connected"
                    conn_color="$SUCCESS"
                else
                    conn_status="disconnected"
                    conn_color="$MUTE"
                fi

                local trust_badge=""
                if bluetoothctl info "$mac" 2>/dev/null | grep -q "Trusted: yes"; then
                    trust_badge=" ${SUCCESS}[trusted]${RESET}"
                fi

                printf " ${type_color}%s${RESET} %s ${GRAY}(%s)${RESET} ${conn_color}%s${RESET}%s\n" \
                    "$icon" "${name:0:32}" "$mac" "$conn_status" "$trust_badge"

                if [[ $connected == "yes" ]]; then
                    local device_card=$(get_bt_audio_card "$mac")
                    if [[ -n $device_card ]]; then
                        local profile=$(get_bt_audio_profile "$device_card")
                        local display=$(get_bt_profile_display_name "$profile" | sed -E \
                            's/High Fidelity Playback \(A2DP Sink, codec /A2DP /; s/Headset Head Unit \(HSP\/HFP, codec /HSP\//')
                        printf "  ${GRAY}%s${RESET}" "$display"
                    fi
                fi
                echo ""
            done
        fi
        rx_table_separator && rx_table_spacer
    }

    _bt_nearby() {
        local nearby_raw=$(bash "$bt_script" --nearby-detailed)
        [[ $nearby_raw == "ERR_SCAN_OFF" ]] && rx_log "error" "Bluetooth scanning is ${GRAY}OFF${RESET}" && return 1

        rx_table_header "󰂯" "Nearby Bluetooth Devices"
        if [[ -z $nearby_raw ]]; then
            rx_table_simple "󰍉" "No new devices found yet..." "$GRAY"
        else
            echo "$nearby_raw" | while IFS='|' read -r _ _ device_type mac name; do
                [[ -z $device_type ]] && continue

                local icon type_color
                icon=$(get_bt_device_type_icon "$device_type")
                [[ $device_type == "phone" || $device_type == "computer" || $device_type == "audio" || $device_type == "audio+input" || $device_type == "controller" ]] && type_color="$PINK" || type_color="$PINK"

                printf " ${type_color}%s${RESET} %s ${MUTE}(%s)${RESET} ${type_color}[%s]${RESET} ${MUTE}[PAIRABLE]${RESET}\n" \
                    "$icon" "${name:0:32}" "$mac" "$(get_bt_device_type_label "$device_type")"
            done
        fi
        rx_table_separator && rx_table_spacer
    }

    _bt_status() {
        local stats=$(bash "$bt_script" --status)

        IFS='|' read -r radio_on pwr_mode disc pair chip ver conns adapter <<<"$stats"

        local mode_color="$PINK"
        [[ $pwr_mode == "SAVER" ]] && mode_color="$SUCCESS"
        [[ $pwr_mode == "OFFLINE" ]] && mode_color="$ERROR"

        local radio_label="${MUTE}OFF${RESET}"
        [[ $radio_on == "yes" ]] && radio_label="${PINK}ON${RESET}"

        rx_table_header "󰂯" "Bluetooth Status"

        rx_table_row "󰂳" "Radio Power:" "$radio_label" "$PINK" "20"
        rx_table_row "󰈐" "Power Mode:" "${pwr_mode}" "$mode_color" "20"
        rx_table_row "󰈐" "Discoverable:" "${disc^^}" "$PINK" "20"
        rx_table_row "󰈐" "Pairable:" "${pair^^}" "$PINK" "20"

        local rx_status rx_dir
        local rx_raw=$(bash "$bt_script" --receive-status)
        IFS='|' read -r rx_status rx_dir <<<"$rx_raw"
        [[ -z $rx_dir ]] && rx_dir="$HOME/Downloads"
        [[ $rx_status == "running" ]] && rx_status="${SUCCESS}ACTIVE${RESET}" || rx_status="${MUTE}INACTIVE${RESET}"

        rx_table_row "󱃚" "Receive Agent:" "$rx_status" "$PINK" "20"
        rx_table_row_gray "󰁞" "Download Folder:" "${rx_dir:0:40}" "20"

        rx_table_row_gray "󰂱" "Adapter Chip:" "$chip" "20"
        rx_table_row_gray "󰄀" "Stack Version:" "Bluetooth $ver" "20"
        rx_table_row "󰂲" "Active Conns:" "${conns:-0} Device(s)" "$PINK" "20"

        rx_table_separator && rx_table_spacer
    }

    _bt_profile_show() {
        local mac="$1"
        local raw_info=$(bash "$bt_script" --profile-info "$mac" 2>/dev/null)
        [[ $raw_info == "NO_CARD" ]] && rx_log "warn" "Device ${PINK}$mac${RESET} is not connected." && return 1

        local active codec
        while IFS='|' read -r key value; do
            [[ $key == "ACTIVE" ]] && active="$value"
            [[ $key == "CODEC" ]] && codec="$value"
        done < <(echo "$raw_info")

        local device_name=$(get_bt_device_info "$mac")
        [[ -z $device_name ]] && device_name="$mac"
        rx_table_header "󰕌" "Audio Profile: ${device_name:0:32}"
        rx_table_row "󰈐" "Active:" "$(get_bt_profile_display_name "$active")" "$PINK" "20"
        rx_table_row "󰈐" "Codec:" "${codec:-unknown}" "$PINK" "20"
        rx_table_separator
        echo "$raw_info" | grep "^PROFILE" | while IFS='|' read -r _ _ is_active desc; do
            local color="$GRAY" marker="  "
            [[ $is_active == "1" ]] && color="$SUCCESS" marker="󰊠"
            printf " ${color}%s${RESET} %s\n" "$marker" "$desc"
        done
        rx_table_separator && rx_table_spacer
    }

    _bt_send() {
        local mac=$(_normalize_mac "$1")
        local file_path="$2"
        [[ -z $mac || -z $file_path ]] && rx_log "error" "Usage: retro bluetooth send <mac> <file>" && return 1
        [[ ! -f $file_path ]] && rx_log "error" "File not found: ${PINK}$file_path${RESET}" && return 1

        local can_send
        can_send=$(bash "$bt_script" --can-send "$mac")
        [[ $can_send != "true" ]] && rx_log "error" "Device does not support file reception (not a phone or PC)." && return 1

        local mac_clean=$(echo "$mac" | tr -d ':')
        local notif_id=$((0x$mac_clean % 1000000))
        [[ $notif_id -lt 10000 ]] && notif_id=$((notif_id + 10000))
        local result_file="/tmp/.bt_send_${notif_id}_result.txt"
        rm -f "$result_file"

        bash "$bt_script" --send "$mac" "$file_path" >/dev/null 2>&1 &
        local start_time=$SECONDS

        while true; do
            if [[ -f $result_file ]]; then
                local result
                result=$(cat "$result_file")
                rm -f "$result_file"

                if [[ $result == OK* ]]; then
                    local elapsed
                    elapsed=$(echo "$result" | cut -d'|' -f2)
                    rx_log "success" "File sent successfully in ${elapsed}s."
                else
                    local err
                    err=$(echo "$result" | cut -d'|' -f2)
                    rx_log "error" "Failed to send file (${err})."
                fi
                break
            fi

            sleep 0.5
            local elapsed=$((SECONDS - start_time))
            if [[ $elapsed -gt 180 ]]; then
                rx_log "error" "Transfer timed out."
                break
            fi
        done
    }

    _bt_restore() {
        local recv_state
        recv_state=$(get_var "BT_RECEIVE_ACTIVE")
        if [[ $recv_state == "true" ]]; then
            local res
            res=$(bash "$bt_script" --receive-restart)
            if [[ $res == OK* ]]; then
                rx_log "success" "OBEX receiver restored."
            else
                rx_log "warn" "Failed to restore receiver (${res#ERR|})."
            fi
        else
            bash "$bt_script" --receive-stop >/dev/null 2>&1
        fi
    }

    case "$action" in
        "on")
            local res=$(bash "$bt_script" --power-on)
            if [[ $res == OK* ]]; then
                rx_log "success" "Bluetooth radio powered ${PINK}ON${RESET}."
            else
                rx_log "error" "Hardware failure: Could not power on Bluetooth."
            fi
            ;;

        "off")
            bash "$bt_script" --receive-stop >/dev/null 2>&1

            local res=$(bash "$bt_script" --power-off)
            if [[ $res == OK* ]]; then
                rx_log "info" "Bluetooth radio powered ${GRAY}OFF${RESET}."
            else
                rx_log "error" "Failed to disable radio."
            fi
            ;;
        "scan")
            if [[ ${2,,} == "on" ]]; then
                bash "$bt_script" --scan-on
                rx_log "info" "Bluetooth scanning ${PINK}ENABLED${RESET} (3 min timeout)."
            else
                bash "$bt_script" --scan-off
                rx_log "info" "Bluetooth scanning ${GRAY}DISABLED${RESET}."
            fi
            ;;
        "list") _bt_list ;;
        "status") _bt_status ;;
        "nearby") _bt_nearby ;;
        "forget")
            [[ -z $2 ]] && rx_log "error" "Provide a Device MAC address." && return 1
            bash "$bt_script" --forget "$2"
            rx_log "success" "Device $2 has been forgotten."
            ;;
        "profile")
            shift
            local mac=$(_normalize_mac "$1")
            local prof="$2"
            local cod="$3"
            [[ -z $mac ]] && rx_log "error" "Usage: retro bluetooth profile <mac> [profile] [codec]" && return 1
            if [[ -z $prof ]]; then _bt_profile_show "$mac"; else
                local res=$(bash "$bt_script" --profile-set "$mac" "$prof" "$cod" 2>/dev/null)
                if [[ $res == ERR_* ]]; then rx_log "error" "Failed to set profile ($res)"; else
                    rx_log "success" "Profile set to ${PINK}$(get_bt_profile_display_name "$(echo "$res" | awk -F'|' '{print $2}')")${RESET}."
                fi
            fi
            ;;
        "send")
            shift
            _bt_send "$@"
            ;;
        "receive")
            shift
            local sub="${1,,}"
            if [[ $sub == "start" ]]; then
                local res
                res=$(bash "$bt_script" --receive-start)
                if [[ $res == OK* ]]; then
                    rx_log "success" "OBEX receiver started."
                else
                    rx_log "error" "Failed to start receiver (${res#ERR|})."
                fi
            elif [[ $sub == "restart" ]]; then
                local res
                res=$(bash "$bt_script" --receive-restart)
                if [[ $res == OK* ]]; then
                    rx_log "success" "OBEX receiver restarted."
                else
                    rx_log "error" "Failed to restart receiver (${res#ERR|})."
                fi
            elif [[ $sub == "stop" ]]; then
                bash "$bt_script" --receive-stop >/dev/null 2>&1
                rx_log "info" "OBEX receiver stopped."
            else
                local status
                status=$(bash "$bt_script" --receive-status)
                IFS='|' read -r st dir <<<"$status"
                [[ $st == "running" ]] && rx_log "info" "Receiver active. Download dir: ${PINK}$dir${RESET}" || rx_log "info" "Receiver inactive."
            fi
            ;;
        "restore")
            _bt_restore
            ;;
        "connect")
            [[ -z $2 ]] && rx_log "error" "Provide a Device MAC address." && return 1
            local mac=$(_normalize_mac "$2")
            [[ $(bluetoothctl show | grep -i "Discovering:" | awk '{print $2}') != "yes" ]] && bash "$bt_script" --scan-on
            rx_log "info" "Attempting to connect to ${PINK}$mac${RESET}..."
            local result
            result=$(bash "$bt_script" --connect "$mac" "$2")
            if [[ $result == OK* ]]; then
                rx_log "success" "Successfully connected to ${PINK}$mac${RESET}!"
            else
                rx_log "error" "Connection failed (${result})."
            fi
            ;;
        "disconnect")
            [[ -z $2 ]] && rx_log "error" "Provide a Device MAC address." && return 1
            local mac=$(_normalize_mac "$2")
            rx_log "info" "Disconnecting ${PINK}$mac${RESET}..."
            bash "$bt_script" --disconnect "$mac" >/dev/null 2>&1 && rx_log "success" "Disconnected." || rx_log "error" "Failed."
            ;;
        "discoverable")
            [[ $(bash "$bt_script" --toggle-discovery) == "on" ]] && rx_log "success" "Visible for 3 mins." || rx_log "info" "Hidden."
            ;;
        "trust")
            [[ -z $2 ]] && rx_log "error" "Usage: retro bluetooth trust <mac>" && return 1
            local mac=$(_normalize_mac "$2")
            local res
            res=$(bash "$bt_script" --trust "$mac")
            if [[ $res == OK* ]]; then
                rx_log "success" "Device ${PINK}$mac${RESET} is now trusted (auto-accepts files)."
            else
                rx_log "error" "Failed to trust device."
            fi
            ;;
        "untrust")
            [[ -z $2 ]] && rx_log "error" "Usage: retro bluetooth untrust <mac>" && return 1
            local mac=$(_normalize_mac "$2")
            local res
            res=$(bash "$bt_script" --untrust "$mac")
            if [[ $res == OK* ]]; then
                rx_log "info" "Device ${PINK}$mac${RESET} no longer trusted (prompts for each file)."
            else
                rx_log "error" "Failed to untrust device."
            fi
            ;;
        *)
            rx_help_usage "retro bluetooth <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "on / off" "Enable or disable Bluetooth radio"
            rx_help_cmd "status" "Show adapter and connection info"
            rx_help_cmd "scan [on|off]" "Toggle device discovery"
            rx_help_cmd "list" "List paired devices with type"
            rx_help_cmd "nearby" "Show discoverable devices"
            rx_help_cmd "profile <mac>" "Manage audio profile"
            rx_help_cmd "send <mac> <file>" "Send file to your phone/PC"
            rx_help_cmd "connect <mac>" "Connect to a device"
            rx_help_cmd "disconnect <mac>" "Disconnect a device"
            rx_help_cmd "forget <mac>" "Remove a paired device"
            rx_help_cmd "trust <mac>" "Mark device as trusted (auto-accept files)"
            rx_help_cmd "untrust <mac>" "Remove trust (prompts on each file)"
            rx_help_cmd "discoverable" "Toggle visibility mode"
            rx_help_cmd "receive [start|restart|stop]" "Manage file reception agent"
            rx_help_cmd "restore" "Restore saved Bluetooth state"
            rx_help_spacer
            rx_help_examples "Examples"
            rx_help_example "retro bluetooth profile AA:BB:CC:DD:EE:FF" "Show available audio profiles"
            rx_help_example "retro bluetooth profile AA:BB:CC:DD:EE:FF a2dp-sink ldac" "Switch to LDAC codec"
            rx_help_example "retro bluetooth send AA:BB:CC:DD:EE:FF ~/photo.jpg" "Send a file to your phone"
            rx_help_example "retro bluetooth receive restart" "Restart the receive agent"
            rx_help_spacer
            ;;
    esac
}

if [[ $(has_bluetooth) == "true" ]]; then
    register_command "TOOLS" "bluetooth" "Manage bluetooth settings and connections" "cmd_bluetooth"
fi
