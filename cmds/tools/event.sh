#!/bin/bash

cmd_event() {
    local event_script="$RETRO_DIR/scripts/event_core.sh"
    local hook_dir="$RETRO_DIR/scripts/hooks"
    local action="$1"
    local value="$2"
    local args="${@:3}"

    case "$action" in
        "trigger")
            [[ -z $value ]] && rx_log "error" "Please provide an event name to trigger." && return 1

            rx_log "info" "Firing event: ${PINK}$value${RESET} $args"

            bash "$event_script" --trigger "$value" $args
            ;;

        "list")
            echo -e "\n ${PINK}󱐋 Active Event Modules: ${RESET}${hook_dir}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            local hooks=$(ls "$hook_dir"/*.sh 2>/dev/null)
            if [[ -z $hooks ]]; then
                echo -e " ${MUTE}  (No scripts found)${RESET}"
            else
                for h in $hooks; do
                    local name=$(basename "$h")
                    local func_count=$(grep -c "^[a-zA-Z0-9_]*()" "$h")
                    printf " ${PINK} ${RESET} %-24s ${GRAY}[%s hooks]${RESET}\n" "$name:" "$func_count"
                done
            fi
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
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
            local pid=$(pgrep -f "event_core.sh --loop")
            echo -e "\n ${PINK}󱐋 Event Worker Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            if [[ -n $pid ]]; then
                local uptime=$(ps -o etime= -p "$pid" | xargs)

                printf " ${PINK}󱐋${RESET} %-14s ${SUCCESS}ACTIVE${RESET} ${GRAY}(PID: %s)${RESET}\n" "State:" "$pid"
                printf " ${PINK}󱎫${RESET} %-14s ${PINK}%s${RESET}\n" "Uptime:" "$uptime"
            else
                printf " ${PINK}󱐋${RESET} %-14s ${ERROR}INACTIVE${RESET}\n" "State:"
                printf " ${PINK}󱎫${RESET} %-14s ${MUTE}N/A${RESET}\n" "Uptime:"
            fi
            printf " ${PINK}󰓅${RESET} %-14s %s\n" "Path:" "$event_script"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        *)
            rx_log "info" "Usage: retro --event [trigger|list|start|stop|restart|status]"
            ;;
    esac
}

register_command "TOOLS" "-evt|--event" "Manage system events and hooks" "cmd_event"
