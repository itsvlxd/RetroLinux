#!/bin/bash

rx_log() {
    local level="${1^^}"
    local message="$2"
    local icon=""
    local color=""

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

    local stripped_msg
    stripped_msg="$(echo "$message" | sed 's/'$'\033''\[[0-9;]*m//g')"

    if [[ $stripped_msg =~ \[[[:space:]]*[Yy]/[Nn][[:space:]]*\]:[[:space:]]*$ ]] ||
        [[ $stripped_msg =~ \[[[:space:]]*[Yy]/[Nn][[:space:]]*\]$ ]] ||
        [[ $stripped_msg =~ \[Default: ]] ||
        [[ $stripped_msg =~ \[.*\]:[[:space:]]*$ ]]; then
        printf "${color}[${icon}${level}]${RESET} %s" "$message" >&2
    else
        printf "${color}[${icon}${level}]${RESET} %s\n" "$message" >&2
    fi
}
