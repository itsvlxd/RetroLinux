#!/bin/bash

RESET='\033[0m'
BOLD='\033[1m'

CLR_PINK='\033[38;5;201m'
CLR_SUCCESS='\033[38;5;76m'
CLR_WARN='\033[38;5;214m'
CLR_ERROR='\033[38;5;196m'

CLR_LABEL='\033[38;5;244m'

rx_log() {
    local level="${1^^}"
    local message="$2"

    local icon=""
    local color=""

    case "${level^^}" in
    "INFO")
        icon=" "
        color="$CLR_PINK"
        ;;
    "SUCCESS")
        icon=" "
        color="$CLR_SUCCESS"
        ;;
    "WARN")
        icon=" "
        color="$CLR_WARN"
        ;;
    "ERROR")
        icon="󰅙 "
        color="$CLR_ERROR"
        ;;
    *)
        icon="󰀦 "
        color="$RESET"
        ;;
    esac

    echo -e "${color}[${icon}${level}]${RESET} ${message}"
}
