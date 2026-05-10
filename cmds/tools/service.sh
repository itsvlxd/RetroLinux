#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

cmd_service() {
    local action="$1"
    local arg1="$2"
    local arg2="$3"

    if [[ -z $action ]]; then
        action="help"
    fi

    action="${action,,}"

    case "$action" in
        list | ls)
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --list "$arg1" "$arg2")

            if echo "$result" | grep -q "result=none"; then
                rx_table_header "󰒑" "System Services"
                rx_table_row "󰒑" "No services found" "" "$MUTE" "30"
                rx_table_separator
                rx_table_spacer
                return
            fi

            rx_table_header "󰒑" "System Services"

            while IFS='|' read -r _ name load active sub description; do
                [[ -z $name || $name == UNIT* || $name == "Legend"* || $name == "●"* ]] && continue

                rx_table_list_row "$name" "$active" "$sub" "" "$PINK" "$GRAY"
            done <<<"$result"

            rx_table_separator
            rx_table_spacer
            ;;

        running)
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --list "running" "service")

            if echo "$result" | grep -q "result=none"; then
                rx_table_header "󰒑" "Running Services"
                rx_table_row "󰒑" "No running services" "" "$MUTE" "30"
                rx_table_separator
                rx_table_spacer
                return
            fi

            rx_table_header "󰒑" "Running Services"

            while IFS='|' read -r _ name load active sub description; do
                [[ -z $name || $name == UNIT* || $name == "Legend"* || $name == "ACTIVE"* || $name == "SUB"* || $name == "●"* ]] && continue

                rx_table_list_row "󰒑" "$name" "$active" "" "$PINK" "$GRAY"
            done <<<"$result"

            rx_table_separator
            rx_table_spacer
            ;;

        failed)
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --list-failed)

            if echo "$result" | grep -q "result=none"; then
                rx_table_header "󰚥" "Failed Services"
                rx_table_row "󰚥" "No failed services" "" "$MUTE" "30"
                rx_table_separator
                rx_table_spacer
                return
            fi

            local count=$(echo "$result" | grep -oP "count=\K[0-9]+")

            rx_table_header "󰚥" "Failed Services"

            while IFS='|' read -r _ name description; do
                [[ -z $name || $name == "failed" || $name == "count" || $name == "Legend"* ]] && continue
                rx_table_list_row "󰒑" "$name" "" "$description" "$ERROR" "$ERROR" "$GRAY"
            done <<<"$result"

            rx_table_row "󰒑" "Total:" "${count:-0} failed services" "$GRAY" "30"
            rx_table_separator
            rx_table_spacer
            ;;

        enabled)
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --list-enabled)

            if echo "$result" | grep -q "result=none"; then
                rx_table_header "󰒑" "Enabled Services (Boot)"
                rx_table_row "󰒑" "No enabled services" "" "$MUTE" "30"
                rx_table_separator
                rx_table_spacer
                return
            fi

            rx_table_header "󰒑" "Enabled Services (Boot)"

            while IFS='|' read -r _ name state; do
                [[ -z $name || $name == "enabled" || $name == "Legend"* ]] && continue
                rx_table_list_row "󰒑" "$name" "$state" "" "$PINK" "$MUTE"
            done <<<"$result"

            rx_table_separator
            rx_table_spacer
            ;;

        status)
            [[ -z $arg1 ]] && rx_log "error" "Service name required" && return 1

            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --status "$arg1")

            if echo "$result" | grep -q "result=error"; then
                local reason=$(echo "$result" | grep -oP "reason=\K[^|]+")
                rx_log "error" "Service ${PINK}$arg1${RESET} not found"
                return 1
            fi

            local svc=$(echo "$result" | grep -oP "service=\K[^|]+")
            local status=$(echo "$result" | grep -oP "status=\K[^|]+")
            local enabled=$(echo "$result" | grep -oP "enabled=\K[^|]+")
            local pid=$(echo "$result" | grep -oP "pid=\K[^|]+")
            local mem=$(echo "$result" | grep -oP "memory=\K[^|]+")
            local since=$(echo "$result" | grep -oP "since=\K[^|]+")

            local status_color="$MUTE"
            case "$status" in
                active | running) status_color="$SUCCESS" ;;
                failed) status_color="$ERROR" ;;
                inactive | dead) status_color="$MUTE" ;;
            esac

            local enabled_color="$MUTE"
            case "$enabled" in
                enabled) enabled_color="$SUCCESS" ;;
                enabled-runtime) enabled_color="$WARN" ;;
                masked) enabled_color="$ERROR" ;;
            esac

            rx_table_header "󰒑" "Service: $svc"
            rx_table_row "󰈐" "Status:" "${status:-unknown}" "$status_color" "20"
            rx_table_row "󰒑" "Enabled:" "${enabled:-unknown}" "$enabled_color" "20"

            if [[ $pid -gt 0 && $pid != "0" ]]; then
                rx_table_row_gray "󰃺" "PID:" "$pid" "20"
            fi

            if [[ -n $mem && $mem != "[not set]" && $mem != "18446744073709551615" && $mem != "N/A" ]]; then
                local mem_mb=$((mem / 1024 / 1024))
                rx_table_row_gray "󰠮" "Memory:" "$mem_mb MB" "20"
            fi

            if [[ -n $since && $since != "[not set]" && $since != "N/A" ]]; then
                rx_table_row_gray "󰶐" "Since:" "$since" "20"
            fi

            rx_table_separator
            rx_table_spacer
            ;;

        start)
            [[ -z $arg1 ]] && rx_log "error" "Service name required" && return 1

            rx_log "info" "Starting ${PINK}$arg1${RESET}..."
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --start "$arg1")

            if echo "$result" | grep -q "result=success"; then
                rx_log "success" "Service ${PINK}$arg1${RESET} started"
            else
                rx_log "error" "Failed to start ${PINK}$arg1${RESET}"
                return 1
            fi
            ;;

        stop)
            [[ -z $arg1 ]] && rx_log "error" "Service name required" && return 1

            rx_log "info" "Stopping ${PINK}$arg1${RESET}..."
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --stop "$arg1")

            if echo "$result" | grep -q "result=success"; then
                rx_log "success" "Service ${PINK}$arg1${RESET} stopped"
            else
                rx_log "error" "Failed to stop ${PINK}$arg1${RESET}"
                return 1
            fi
            ;;

        restart | reload)
            [[ -z $arg1 ]] && rx_log "error" "Service name required" && return 1

            rx_log "info" "Restarting ${PINK}$arg1${RESET}..."
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --restart "$arg1")

            if echo "$result" | grep -q "result=success"; then
                rx_log "success" "Service ${PINK}$arg1${RESET} restarted"
            else
                rx_log "error" "Failed to restart ${PINK}$arg1${RESET}"
                return 1
            fi
            ;;

        enable)
            [[ -z $arg1 ]] && rx_log "error" "Service name required" && return 1

            rx_log "info" "Enabling ${PINK}$arg1${RESET} at boot..."
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --enable "$arg1")

            if echo "$result" | grep -q "result=success"; then
                rx_log "success" "Service ${PINK}$arg1${RESET} enabled"
            else
                rx_log "error" "Failed to enable ${PINK}$arg1${RESET}"
                return 1
            fi
            ;;

        disable)
            [[ -z $arg1 ]] && rx_log "error" "Service name required" && return 1

            rx_log "info" "Disabling ${PINK}$arg1${RESET} at boot..."
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --disable "$arg1")

            if echo "$result" | grep -q "result=success"; then
                rx_log "success" "Service ${PINK}$arg1${RESET} disabled"
            else
                rx_log "error" "Failed to disable ${PINK}$arg1${RESET}"
                return 1
            fi
            ;;

        logs | tail)
            [[ -z $arg1 ]] && rx_log "error" "Service name required" && return 1

            rx_log "info" "Showing logs for ${PINK}$arg1${RESET}..."
            bash "$RETRO_DIR/scripts/service_core.sh" --logs "$arg1" "$arg2"
            ;;

        clean | reset)
            rx_log "info" "Resetting failed state..."
            local result=$(bash "$RETRO_DIR/scripts/service_core.sh" --clean-failed)

            if echo "$result" | grep -q "result=success"; then
                rx_log "success" "Failed state reset"
            else
                rx_log "error" "Failed to reset failed state"
                return 1
            fi
            ;;

        *)
            rx_help_usage "retro service <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "list [filter]" "List all services"
            rx_help_cmd "running" "Show running services"
            rx_help_cmd "failed" "Show failed services"
            rx_help_cmd "enabled" "Show enabled services"
            rx_help_cmd "status <name>" "Show service status"
            rx_help_cmd "start <name>" "Start a service"
            rx_help_cmd "stop <name>" "Stop a service"
            rx_help_cmd "restart <name>" "Restart a service"
            rx_help_cmd "enable <name>" "Enable at boot"
            rx_help_cmd "disable <name>" "Disable at boot"
            rx_help_cmd "logs <name> [n]" "Show service logs"
            rx_help_cmd "clean" "Reset failed services"
            rx_help_examples
            rx_help_example "retro service list" "List all services"
            rx_help_example "retro service running" "Show running services"
            rx_help_example "retro service failed" "Show failed services"
            rx_help_example "retro service status bluetooth" "Show bluetooth status"
            rx_help_example "retro service restart NetworkManager" "Restart network service"
            rx_help_example "retro service enable docker" "Enable docker at boot"
            rx_help_example "retro service logs sshd 100" "Show last 100 log lines"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "service" "Manage system services and daemons" "cmd_service"

