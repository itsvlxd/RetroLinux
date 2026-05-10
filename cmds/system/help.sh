#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

show_usage() {
    rx_logo

    echo -e "${PINK}  USAGE:${RESET} retro <command> [module/sub-command] [options]\n"

    get_group_icon() {
        case "$1" in
            "SYSTEM") echo "󰒓" ;;
            "MODULES") echo " " ;;
            "TOOLS") echo " " ;;
            *) echo "󰄾" ;;
        esac
    }

    local priority=("SYSTEM" "MODULES" "TOOLS")
    local raw_groups=$(for entry in "${CMDS_HELP[@]}"; do echo "${entry%%|*}"; done | sort -u)

    local final_groups=()
    for p in "${priority[@]}"; do
        if echo "$raw_groups" | grep -q "^$p$"; then final_groups+=("$p"); fi
    done

    while read -r rg; do
        [[ -z $rg ]] && continue
        local skip=false
        for pg in "${final_groups[@]}"; do [[ $rg == "$pg" ]] && skip=true && break; done
        [[ $skip == "false" ]] && final_groups+=("$rg")
    done <<<"$raw_groups"

    for group in "${final_groups[@]}"; do
        local group_icon=$(get_group_icon "$group")
        rx_help_section "$group_icon" "$group"

        local sorted_entries=$(for entry in "${CMDS_HELP[@]}"; do
            [[ ${entry%%|*} == "$group" ]] && echo "$entry"
        done | sort -t'|' -k2)

        while read -r entry; do
            [[ -z $entry ]] && continue

            local rem="${entry#*|}"
            local desc="${rem##*|}"
            local aliases="${rem%|*}"

            local display_aliases=$(echo "$aliases" | sed 's/|/, /g')

            printf "    ${PINK}%-16s ${GRAY}-${RESET} %s\n" "$display_aliases" "$desc"
        done <<<"$sorted_entries"

        echo ""
    done
}

register_command "SYSTEM" "-h|--help" "Show this interface" "show_usage"
