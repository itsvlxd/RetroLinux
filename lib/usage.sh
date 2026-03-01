#!/bin/bash

CMDS=(
    "#|SYSTEM CORE"
    "-s|--setup|Install dependencies and retro cli"
    "-u|--update|Pull latest changes and refresh modules"

    "#|MANAGEMENT"
    "-i|--install|Link repo files (Active ricing mode)"
    "-m|--mirror|Hard copy files (Stability mode)"
    "-p|--pull|Capture system changes back to repo"

    "#|INFO"
    "-v|--version|Display current version and branch"
    "-h|--help|Show this interface"
)

show_usage() {
    rx_logo
    local PINK='\e[38;5;201m'
    local GRAY='\e[38;5;244m'
    local RESET='\e[0m'

    echo -e " ${PINK}  USAGE:${RESET} retro [option] [module|all]"

    for entry in "${CMDS[@]}"; do
        IFS="|" read -r a b c <<<"$entry"

        if [[ "$a" == "#" ]]; then
            echo -e "\n ${PINK}󰄾 ${RESET}${b}${GRAY}:"
        else
            printf "    ${PINK}%s, %s ${GRAY}-${RESET} %s\n" \
                "$a" "$b" "$c"
        fi
    done
    echo ""
}
