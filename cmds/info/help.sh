#!/bin/bash

show_usage() {
    rx_logo
    local PINK='\e[38;5;201m'
    local GRAY='\e[38;5;244m'
    local RESET='\e[0m'

    echo -e "${PINK}  USAGE:${RESET} retro [option] [module] [-y]\n"

    local current_group=""

    for entry in "${CMDS_HELP[@]}"; do
        local group="${entry%%|*}"
        local remainder="${entry#*|}"
        local aliases="${remainder%|*}"
        local desc="${remainder##*|}"

        if [[ "$group" != "$current_group" ]]; then
            if [[ -n "$current_group" ]]; then
                echo ""
            fi

            echo -e " ${PINK}󰄾 ${RESET}${group}${GRAY}:"
            current_group="$group"
        fi

        local display_aliases=$(echo "$aliases" | sed 's/|/, /g')
        printf "    ${PINK}%-16s ${GRAY}-${RESET} %s\n" "$display_aliases" "$desc"
    done

    echo ""
}

register_command "INFO" "-h|--help" "Show this interface" "show_usage"
