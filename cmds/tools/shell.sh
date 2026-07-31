#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/colors.sh"

cmd_shell() {
    local action="${1,,}"
    local core="$RETRO_DIR/scripts/shell_core.sh"

    case "$action" in
        start)
            local result=$(bash "$core" --start)
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "RetroShell started"
            else
                rx_log "error" "Failed to start RetroShell"
            fi
            ;;
        stop|quit)
            local result=$(bash "$core" --stop)
            if echo "$result" | grep -q "^OK"; then
                rx_log "info" "RetroShell stopped"
            else
                rx_log "info" "RetroShell is not running"
            fi
            ;;
        restart|reload)
            bash "$core" --stop >/dev/null 2>&1
            sleep 1
            local result=$(bash "$core" --start)
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "RetroShell restarted"
            else
                rx_log "error" "Failed to restart RetroShell"
            fi
            ;;
        run)
            local cmd="${@:2}"
            local valid_cmds="launcher clipboard emoji tmux notes wallpapers screenshot screenrecord lockscreen overview powermenu tools assistant config dashboard media-play-pause media-next media-prev"
            if [[ -z $cmd ]]; then
                rx_log "info" "Commands: ${PINK}launcher${RESET}, ${PINK}clipboard${RESET}, ${PINK}emoji${RESET}, ${PINK}tmux${RESET}, ${PINK}notes${RESET}, ${PINK}wallpapers${RESET}, ${PINK}screenshot${RESET}, ${PINK}screenrecord${RESET}, ${PINK}lockscreen${RESET}, ${PINK}overview${RESET}, ${PINK}powermenu${RESET}, ${PINK}tools${RESET}, ${PINK}assistant${RESET}, ${PINK}config${RESET}, ${PINK}dashboard${RESET}, ${PINK}media-play-pause${RESET}, ${PINK}media-next${RESET}, ${PINK}media-prev${RESET}"
                return 0
            fi
            if ! echo "$valid_cmds" | grep -qw "$cmd"; then
                rx_log "error" "Unknown command: ${PINK}$cmd${RESET}"
                return 1
            fi
            local result=$(bash "$core" --run "$cmd")
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "Command sent: ${PINK}$cmd${RESET}"
            elif echo "$result" | grep -q "not_running"; then
                rx_log "error" "RetroShell is not running"
            else
                rx_log "error" "Failed to send command"
            fi
            ;;
        lock)
            bash "$core" --lock
            rx_log "success" "Screen locked"
            ;;
        status)
            local status=$(bash "$core" --status)
            local state="${status%%|*}"
            local pid="${status#*|}"
            if [[ $state == "running" ]]; then
                rx_table_row "󰒓" "Status:" "● Running (PID $pid)" "$SUCCESS" "14"
            else
                rx_table_row "󰒓" "Status:" "○ Not running" "$MUTE" "14"
            fi
            ;;
        "")
            ;&
        help)
            rx_help_usage "retro shell <command>"
            rx_help_commands "Commands"
            rx_help_cmd "start" "Launch RetroShell" 20
            rx_help_cmd "stop" "Stop RetroShell" 20
            rx_help_cmd "restart" "Restart RetroShell" 20
            rx_help_cmd "status" "Check if running" 20
            rx_help_cmd "lock" "Activate lockscreen" 20
            rx_help_cmd "run <cmd>" "Send IPC command" 20
            rx_help_spacer
            ;;
        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}

register_command "TOOLS" "shell" "Launch and control RetroShell" "cmd_shell"