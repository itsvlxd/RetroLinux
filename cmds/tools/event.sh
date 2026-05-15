#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

cmd_event() {
    local daemon_script="$RETRO_DIR/daemon/event_daemon.lua"
    local action="${1,,}"
    local value="$2"
    local rest="${@:3}"

    if ! command -v lua &>/dev/null; then
        rx_log "error" "Lua runtime not found. Install with: sudo pacman -S lua"
        return 1
    fi

    export RETRO_DIR
    export RETRO_CONFIG

    case "$action" in
        "trigger")
            [[ -z $value ]] && rx_log "error" "Please provide an event name to trigger." && return 1
            rx_log "info" "Firing event: ${PINK}$value${RESET} $rest"
            lua "$daemon_script" trigger "$value" $rest
            ;;

        "list")
            lua "$daemon_script" list
            ;;

        "start")
            rx_log "info" "Starting the event daemon..."

            local pid_file="/tmp/retro_event_daemon.pid"
            if [[ -f $pid_file ]]; then
                local old_pid=$(cat "$pid_file")
                if kill -0 "$old_pid" 2>/dev/null; then
                    rx_log "error" "The daemon is already running (PID: $old_pid)."
                    return 0
                else
                    rm -f "$pid_file"
                fi
            fi

            nohup lua "$daemon_script" loop >/dev/null 2>&1 &
            local daemon_pid=$!
            sleep 0.3
            if kill -0 "$daemon_pid" 2>/dev/null; then
                echo "$daemon_pid" > "$pid_file"
                rx_log "success" "Event daemon started in the background."
            else
                rx_log "error" "Daemon failed to start."
                return 1
            fi
            ;;

        "stop")
            lua "$daemon_script" stop
            ;;

        "restart")
            lua "$daemon_script" stop >/dev/null 2>&1
            sleep 0.5
            cmd_event "start"
            ;;

        "status")
            lua "$daemon_script" status
            ;;

        "log")
            if [[ -z $value ]]; then
                lua "$daemon_script" log
            elif [[ $value == "true" || $value == "false" ]]; then
                lua "$daemon_script" log "$value"
            elif [[ $value == "limit" ]]; then
                lua "$daemon_script" log limit "$3" "$4"
            else
                lua "$daemon_script" log "$value" "$3"
            fi
            ;;

        *)
            rx_help_usage "retro event <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "trigger <event>" "Fire a system event"
            rx_help_cmd "list" "List all event hooks"
            rx_help_cmd "start" "Start the event daemon"
            rx_help_cmd "stop" "Stop the event daemon"
            rx_help_cmd "restart" "Restart the event daemon"
            rx_help_cmd "status" "Show daemon status"
            rx_help_cmd "log <name>" "View watcher logs"
            rx_help_cmd "log true/false" "Enable/disable all logs"
            rx_help_cmd "log limit <n>" "Set log line cap"
            rx_help_examples
            rx_help_example "retro event status" "Check if daemon is running"
            rx_help_example "retro event list" "Show all loaded hooks"
            rx_help_example "retro event log usb" "View USB watcher logs"
            rx_help_example "retro event log true" "Enable log generation"
            rx_help_example "retro event log false" "Disable log generation"
            rx_help_example "retro event log limit 200" "Set log cap to 200 lines"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "event" "Manage system events and hooks" "cmd_event"
