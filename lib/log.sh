#!/bin/bash

rx_log() {
    local level="${1^^}"
    local message="$2"
    local icon=""
    local color=""
    local echo_opts="-e"

    case "${level}" in
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

    if [[ $message == *": " ]] && [[ $message =~ \[.*\] ]]; then
        echo_opts="-ne"
    fi

    echo $echo_opts "${color}[${icon}${level}]${RESET} ${message}"
}
