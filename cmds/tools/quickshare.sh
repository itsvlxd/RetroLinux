#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

cmd_quickshare() {
    local qs_core="$RETRO_DIR/scripts/quickshare_core.sh"
    local action="${1,,}"
    shift 2>/dev/null || true

    case "$action" in
        "status")
            local output
            output=$(bash "$qs_core" --status)
            IFS='|' read -r state dir autostart pid autoaccept <<<"$output"

            rx_table_header "󰀀" "Android Quick Share"

            local state_color="$MUTE"
            local state_disp="○ Stopped"
            if [[ $state == "running" ]]; then
                state_color="$SUCCESS"
                state_disp="● Running"
            fi
            rx_table_row "󰅟" "Status:" "$state_disp" "$state_color" "20"

            rx_table_row "󱂚" "Device:" "$(hostname)" "$PINK" "20"
            rx_table_row "󰋋" "Download Dir:" "$dir" "$GRAY" "20"
            rx_table_row "󰇘" "Autostart:" "$([ $autostart == "true" ] && echo "On" || echo "Off")" "$PINK" "20"
            rx_table_row "󱂓" "Auto-accept:" "$([ $autoaccept == "true" ] && echo "On" || echo "Off")" "$PINK" "20"
            [[ -n $pid ]] && rx_table_row "󰒓" "PID:" "$pid" "$GRAY" "20"

            rx_table_separator
            rx_table_spacer
            ;;

        "start")
            local out
            out=$(bash "$qs_core" --start)
            if [[ $out == OK* ]]; then
                rx_log "success" "Android Quick Share started"
            elif [[ $out == *already_running* ]]; then
                rx_log "info" "Android Quick Share is already running"
            else
                rx_log "error" "Failed to start Android Quick Share ($out)"
                return 1
            fi
            ;;

        "stop")
            local out
            out=$(bash "$qs_core" --stop)
            if [[ $out == OK* ]]; then
                rx_log "success" "Android Quick Share stopped"
            else
                rx_log "info" "Android Quick Share is not running"
            fi
            ;;

        "dir")
            local dir="$1"
            if [[ -z $dir ]]; then
                local out
                out=$(bash "$qs_core" --status | cut -d'|' -f2)
                rx_log "info" "Download dir: ${PINK}$out${RESET}"
                return 0
            fi
            local res
            res=$(bash "$qs_core" --set-dir "$dir")
            if [[ $res == OK* ]]; then
                rx_log "success" "Download dir set to ${PINK}$dir${RESET}"
            else
                rx_log "error" "Failed to set download dir"
                return 1
            fi
            ;;

        "autoaccept")
            local state="${1,,}"
            if [[ -z $state ]]; then
                local out
                out=$(bash "$qs_core" --status | cut -d'|' -f5)
                rx_log "info" "Auto-accept: ${PINK}$([ $out == "true" ] && echo On || echo Off)${RESET}"
                return 0
            fi
            case "$state" in
                on|true|enable|1) state="on" ;;
                off|false|disable|0) state="off" ;;
                *) rx_log "error" "Usage: retro quickshare autoaccept <on|off>" && return 1 ;;
            esac
            local res
            res=$(bash "$qs_core" --auto-accept "$state")
            if [[ $res == OK* ]]; then
                rx_log "success" "Auto-accept ${state}"
            else
                rx_log "error" "Failed to set auto-accept"
                return 1
            fi
            ;;

        "autostart")
            local state="${1,,}"
            if [[ -z $state ]]; then
                local out
                out=$(bash "$qs_core" --status | cut -d'|' -f3)
                rx_log "info" "Autostart: ${PINK}$([ $out == "true" ] && echo On || echo Off)${RESET}"
                return 0
            fi
            case "$state" in
                on|true|enable|1) state="on" ;;
                off|false|disable|0) state="off" ;;
                *) rx_log "error" "Usage: retro quickshare autostart <on|off>" && return 1 ;;
            esac
            local res
            res=$(bash "$qs_core" --autostart "$state")
            if [[ $res == OK* ]]; then
                rx_log "success" "Autostart ${state}"
            else
                rx_log "error" "Failed to set autostart"
                return 1
            fi
            ;;

        "scan")
            local out
            out=$(python3 "$RETRO_DIR/scripts/python/quickshare_scan.py" 2>/dev/null)
            if [[ -z $out ]]; then
                rx_log "info" "No nearby Quick Share devices found"
                return 0
            fi
            rx_table_header "󰀀" "Nearby Devices"
            while IFS='|' read -r name addr port dtype; do
                [[ -z $name ]] && continue
                rx_table_row "󰛧" "$name" "$addr:$port ($dtype)" "$GRAY" "30"
            done <<<"$out"
            rx_table_separator
            rx_table_spacer
            ;;

        "send")
            if [[ $# -eq 0 ]]; then
                rx_log "error" "Usage: retro quickshare send <file...> [--target HOST:PORT]"
                return 1
            fi
            python3 "$RETRO_DIR/scripts/python/quickshare_send.py" "$@"
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                rx_log "success" "Files sent"
            else
                rx_log "warn" "Send canceled or failed"
            fi
            return $rc
            ;;

        *)
            rx_help_usage "retro quickshare <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show Android Quick Share status"
            rx_help_cmd "start" "Start the Quick Share receiver"
            rx_help_cmd "stop" "Stop the Quick Share receiver"
            rx_help_cmd "dir [path]" "Get or set the download directory"
            rx_help_cmd "autoaccept <on|off>" "Enable or disable auto-accepting transfers"
            rx_help_cmd "autostart <on|off>" "Enable or disable start at login"
            rx_help_cmd "scan" "Scan for nearby Quick Share devices"
            rx_help_cmd "send <file...>" "Send files to a nearby device"
            rx_help_examples
            rx_help_example "retro quickshare status" "Show status"
            rx_help_example "retro quickshare start" "Start receiver"
            rx_help_example "retro quickshare dir ~/Downloads" "Set download dir"
            rx_help_example "retro quickshare autoaccept on" "Auto-accept transfers"
            rx_help_example "retro quickshare scan" "Find nearby devices"
            rx_help_example "retro quickshare send photo.jpg" "Send a file"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "quickshare" "Native Android Quick Share receiver (no rquickshare)" "cmd_quickshare"
