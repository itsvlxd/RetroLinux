#!/bin/bash

cmd_cleanup() {
    local action="$1"
    local arg1="$2"
    local arg2="$3"

    if [[ -z "$action" ]]; then
        action="help"
    fi

    action="${action,,}"

    case "$action" in
        status|healthy|health)
            bash "$RETRO_DIR/scripts/cleanup_core.sh" --status
            ;;

        clean|clean-all)
            bash "$RETRO_DIR/scripts/cleanup_core.sh" --clean-all
            ;;

        cache|caches)
            bash "$RETRO_DIR/scripts/cleanup_core.sh" --clean-caches
            ;;

        thumbnails|thumbs)
            bash "$RETRO_DIR/scripts/cleanup_core.sh" --clean-thumbnails
            ;;

        logs)
            bash "$RETRO_DIR/scripts/cleanup_core.sh" --clean-logs "$arg1"
            ;;

        pacman)
            if [[ "$EUID" -ne 0 ]]; then
                rx_log "warn" "Pacman cleanup requires root privileges"
                rx_log "info" "Run with sudo or as root"
                return 1
            fi
            bash "$RETRO_DIR/scripts/cleanup_core.sh" --clean-pacman
            ;;

        orphans)
            if [[ "$EUID" -ne 0 ]]; then
                rx_log "warn" "Orphan removal requires root privileges"
                rx_log "info" "Run with sudo or as root"
                return 1
            fi
            bash "$RETRO_DIR/scripts/cleanup_core.sh" --clean-orphans
            ;;

        temp)
            bash "$RETRO_DIR/scripts/cleanup_core.sh" --clean-temp
            ;;

        *)
            rx_log "info" "Usage: retro cleanup <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show system health overview"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "clean" "Run full cleanup"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "cache" "Clean user cache"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "thumbs" "Clean thumbnails"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "logs [days]" "Clean journal logs"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "pacman" "Clean pkg cache (root)"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "orphans" "Remove orphans (root)"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "temp" "Clean old temp files"
            echo ""
            echo -e " ${PINK}  ${RESET}Examples${GRAY}:${RESET}"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro cleanup status" "Show disk/memory usage"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro cleanup clean" "Run all cleanup tasks"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro cleanup cache" "Clear user cache"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro cleanup logs 3" "Keep last 3 days of logs"
            printf " ${GRAY}%-30s${RESET} %s\n" "sudo retro cleanup pacman" "Clear pacman pkg cache"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "cleanup" "Clean caches, logs, and maintain system health" "cmd_cleanup"
