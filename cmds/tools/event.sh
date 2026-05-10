#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

cmd_event() {
    local event_script="$RETRO_DIR/scripts/event_core.sh"
    local hook_dir="$RETRO_DIR/scripts/events"
    local action="${1,,}"
    local value="$2"
    local args="${@:3}"

    case "$action" in
        "trigger")
            [[ -z $value ]] && rx_log "error" "Please provide an event name to trigger." && return 1

            rx_log "info" "Firing event: ${PINK}$value${RESET} $args"

            bash "$event_script" --trigger "$value" $args
            ;;

        "list")
            rx_table_header "󱐋" "Event Modules"

            local watcher_dir="$RETRO_DIR/scripts/watchers"

            local watcher_scripts=$(ls "$watcher_dir"/*.sh 2>/dev/null)
            for w in $watcher_scripts; do
                local name=$(basename "$w")
                local func_count=$(grep -c "^start_watcher_" "$w")
                rx_table_list_single "󱐋" "$name [$func_count watcher]" "$GRAY"
            done

            local hooks=$(ls "$hook_dir"/*.sh 2>/dev/null)
            for h in $hooks; do
                local name=$(basename "$h")
                local func_count=$(grep -c "^[a-zA-Z0-9_]*()" "$h")
                rx_table_list_single "󱐋" "$name [$func_count hooks]" "$GRAY"
            done

            if [[ -z $watcher_scripts && -z $hooks ]]; then
                rx_table_simple "󰓅" "(No modules found)" "$MUTE"
            fi
            rx_table_separator
            rx_table_spacer
            ;;

        "start")
            rx_log "info" "Starting the event worker..."

            if pgrep -f "event_core.sh --loop" >/dev/null; then
                rx_log "error" "The worker is already running."
            else
                nohup bash "$event_script" --loop >/dev/null 2>&1 &
                rx_log "success" "Event worker started in the background."
            fi
            ;;

        "stop")
            rx_log "info" "Stopping the event worker..."
            pkill -f "event_core.sh --loop" && rx_log "success" "Worker stopped." || rx_log "error" "No active worker found."
            ;;

        "restart")
            cmd_event "stop"
            sleep 0.5
            cmd_event "start"
            ;;

        "status")
            local pids=$(pgrep -f "event_core.sh --loop" | grep -v "$$" | xargs)
            rx_table_header "󱐋" "Event Worker Status"
            if [[ -n $pids ]]; then
                local pid=$(echo "$pids" | awk '{print $1}')
                local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | xargs)

                rx_table_row "󱐋" "State:" "ACTIVE (PID: $pid)" "$SUCCESS" "14"
                rx_table_row "󱎫" "Uptime:" "$uptime" "$PINK" "14"
            else
                rx_table_row "󱐋" "State:" "INACTIVE" "$ERROR" "14"
                rx_table_row "󱎫" "Uptime:" "N/A" "$MUTE" "14"
            fi
            rx_table_row "󰓅" "Path:" "$event_script" "$GRAY" "14"
            rx_table_separator
            rx_table_spacer
            ;;

        *)
            rx_help_usage "retro event <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "trigger <event>" "Fire a system event"
            rx_help_cmd "list" "List all event hooks"
            rx_help_cmd "start" "Start the event worker daemon"
            rx_help_cmd "stop" "Stop the event worker daemon"
            rx_help_cmd "restart" "Restart the event worker daemon"
            rx_help_cmd "status" "Show event worker status"
            rx_help_examples
            rx_help_example "retro event status" "Check if daemon is running"
            rx_help_example "retro event list" "Show all loaded hooks"
            rx_help_example "retro event trigger battery_low" "Fire specific event"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "event" "Manage system events and hooks" "cmd_event"
