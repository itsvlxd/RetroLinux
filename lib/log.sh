#!/bin/bash

rx_log() {
    local level="${1^^}"
    local message="$2"

    local icon=""
    local color=""

    case "${level^^}" in
        "INFO")
            icon=" "
            color="$PINK"
            ;;
        "SUCCESS")
            icon=" "
            color="$SUCCESS"
            ;;
        "WARN")
            icon=" "
            color="$WARN"
            ;;
        "ERROR")
            icon="󰅙 "
            color="$ERROR"
            ;;
        *)
            icon="󰀦 "
            color="$RESET"
            ;;
    esac

    echo -e "${color}[${icon}${level}]${RESET} ${message}"
}
