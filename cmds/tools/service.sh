#!/bin/bash

cmd_service() {
    local action="$1"
    local arg1="$2"
    local arg2="$3"

    if [[ -z "$action" ]]; then
        action="help"
    fi

    action="${action,,}"

    case "$action" in
        list|ls)
            bash "$RETRO_DIR/scripts/service_core.sh" --list "$arg1" "$arg2"
            ;;

        running)
            bash "$RETRO_DIR/scripts/service_core.sh" --list "running" "service"
            ;;

        failed)
            bash "$RETRO_DIR/scripts/service_core.sh" --list-failed
            ;;

        enabled)
            bash "$RETRO_DIR/scripts/service_core.sh" --list-enabled
            ;;

        status)
            bash "$RETRO_DIR/scripts/service_core.sh" --status "$arg1"
            ;;

        start)
            bash "$RETRO_DIR/scripts/service_core.sh" --start "$arg1"
            ;;

        stop)
            bash "$RETRO_DIR/scripts/service_core.sh" --stop "$arg1"
            ;;

        restart|reload)
            bash "$RETRO_DIR/scripts/service_core.sh" --restart "$arg1"
            ;;

        enable)
            bash "$RETRO_DIR/scripts/service_core.sh" --enable "$arg1"
            ;;

        disable)
            bash "$RETRO_DIR/scripts/service_core.sh" --disable "$arg1"
            ;;

        logs|tail)
            bash "$RETRO_DIR/scripts/service_core.sh" --logs "$arg1" "$arg2"
            ;;

        clean|reset)
            bash "$RETRO_DIR/scripts/service_core.sh" --clean-failed
            ;;

        help|--help|-h)
            rx_log "info" "Usage: retro service <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list [filter]" "List all services"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "running" "Show running services"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "failed" "Show failed services"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "enabled" "Show enabled services"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status <name>" "Show service status"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "start <name>" "Start a service"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "stop <name>" "Stop a service"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "restart <name>" "Restart a service"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "enable <name>" "Enable at boot"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "disable <name>" "Disable at boot"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "logs <name> [n]" "Show service logs"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "clean" "Reset failed services"
            echo ""
            echo -e " ${PINK}  ${RESET}Examples${GRAY}:${RESET}"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro service list" "List all services"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro service running" "Show running services"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro service failed" "Show failed services"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro service status bluetooth" "Show bluetooth status"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro service restart NetworkManager" "Restart network service"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro service enable docker" "Enable docker at boot"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro service logs sshd 100" "Show last 100 log lines"
            echo ""
            ;;
        *)
            rx_log "error" "Unknown command: ${PINK}$action${RESET}"
            rx_log "info" "Run 'retro service' for help"
            return 1
            ;;
    esac
}

register_command "TOOLS" "service" "Manage system services and daemons" "cmd_service"
