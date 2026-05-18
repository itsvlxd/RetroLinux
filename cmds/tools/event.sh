#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/icons.sh"

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

    _get_watchers() {
        ls -1 "$RETRO_DIR/daemon/watchers/"*.lua 2>/dev/null | while read -r f; do
            basename "$f" .lua
        done
    }

    _is_disabled() {
        [[ -f "/tmp/retro_logs/watcher_${1}.disabled" ]]
    }

    case "$action" in
        "trigger")
            [[ -z $value ]] && rx_log "error" "Please provide an event name to trigger." && return 1
            rx_log "info" "Firing event: ${PINK}$value${RESET} $rest"
            lua "$daemon_script" trigger "$value" $rest
            ;;

        "list")
            local watchers=()
            while IFS= read -r w; do
                [[ -n $w ]] && watchers+=("$w")
            done < <(_get_watchers)

            if [[ ${#watchers[@]} -eq 0 ]]; then
                rx_table_header "󱐋" "No event modules found"
                rx_table_spacer
                return
            fi

            local active=0
            local disabled=0
            for w in "${watchers[@]}"; do
                if _is_disabled "$w"; then
                    disabled=$((disabled + 1))
                else
                    active=$((active + 1))
                fi
            done

            rx_table_header "󱐋" "Event Modules"
            rx_table_row "󱐋" "Total:" "${#watchers[@]}" "$PINK" "18"
            rx_table_row "󰓅" "Active:" "$active" "$SUCCESS" "18"
            rx_table_row "󱐋" "Disabled:" "$disabled" "$ERROR" "18"
            rx_table_separator

            for w in "${watchers[@]}"; do
                local interval=""
                local mod_file="$RETRO_DIR/daemon/watchers/${w}.lua"
                if [[ -f $mod_file ]]; then
                    interval=$(grep -oP 'interval\s*=\s*\K\d+' "$mod_file" 2>/dev/null || echo "?")
                    [[ -n $interval ]] && interval="${interval}s"
                fi

                if _is_disabled "$w"; then
                    rx_table_row "󱐋" "$w" "disabled ${interval:+($interval)}" "$ERROR" "18"
                else
                    rx_table_row "󱐋" "$w" "active ${interval:+($interval)}" "$PINK" "18"
                fi
            done
            rx_table_separator && rx_table_spacer
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

        "enable")
            [[ -z $value ]] && rx_log "error" "Usage: retro event enable <name|all>" && return 1
            if [[ $value == "all" ]]; then
                local count=0
                for f in /tmp/retro_logs/watcher_*.disabled; do
                    [[ -f $f ]] || continue
                    local name=$(basename "$f" .disabled | sed 's/^watcher_//')
                    if [[ -f "$RETRO_DIR/daemon/watchers/${name}.lua" ]]; then
                        rm -f "$f"
                        count=$((count + 1))
                    fi
                done
                [[ $count -eq 0 ]] && rx_log "info" "No disabled event modules." || rx_log "success" "Enabled $count module(s). Restart the daemon to apply."
            else
                local disabled_file="/tmp/retro_logs/watcher_${value}.disabled"
                [[ ! -f $disabled_file ]] && rx_log "warn" "Module ${PINK}$value${RESET} is not disabled." && return 1
                rm -f "$disabled_file"
                rx_log "success" "Module ${PINK}$value${RESET} enabled. Restart the daemon to apply."
            fi
            ;;

        "disable")
            [[ -z $value ]] && rx_log "error" "Usage: retro event disable <name>" && return 1
            local disabled_file="/tmp/retro_logs/watcher_${value}.disabled"
            [[ ! -f "$RETRO_DIR/daemon/watchers/${value}.lua" ]] && rx_log "error" "Module ${PINK}$value${RESET} not found." && return 1
            touch "$disabled_file"
            rx_log "warn" "Module ${PINK}$value${RESET} disabled. Restart the daemon to apply."
            ;;

        *)
            rx_help_usage "retro event <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "trigger <event>" "Fire a system event"
            rx_help_cmd "list" "List all event modules"
            rx_help_cmd "start" "Start the event daemon"
            rx_help_cmd "stop" "Stop the event daemon"
            rx_help_cmd "restart" "Restart the event daemon"
            rx_help_cmd "status" "Show daemon status"
            rx_help_cmd "enable <name|all>" "Enable a module or all"
            rx_help_cmd "disable <name>" "Disable a module"
            rx_help_examples
            rx_help_example "retro event status" "Check if daemon is running"
            rx_help_example "retro event list" "Show all loaded modules"
            rx_help_example "retro event disable bluetooth" "Disable bluetooth watcher"
            rx_help_example "retro event enable all" "Enable all modules"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "event" "Manage system events and hooks" "cmd_event"
