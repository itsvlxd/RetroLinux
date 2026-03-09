#!/bin/bash

show_usage() {
    rx_logo

    echo -e "${PINK}  USAGE:${RESET} retro <command> [module/sub-command] [options]\n"

    local priority=("SYSTEM" "MANAGEMENT" "TOOLS")

    local raw_groups=$(for entry in "${CMDS_HELP[@]}"; do echo "${entry%%|*}"; done | sort -u)

    local final_groups=()
    for p in "${priority[@]}"; do
        if echo "$raw_groups" | grep -q "^$p$"; then
            final_groups+=("$p")
        fi
    done

    while read -r rg; do
        [[ -z $rg ]] && continue
        local skip=false
        for pg in "${final_groups[@]}"; do
            [[ $rg == "$pg" ]] && skip=true && break
        done
        [[ $skip == "false" ]] && final_groups+=("$rg")
    done <<<"$raw_groups"

    for group in "${final_groups[@]}"; do
        echo -e " ${PINK}󰄾 ${RESET}${group}${GRAY}:"

        for entry in "${CMDS_HELP[@]}"; do
            local g="${entry%%|*}"
            [[ $g != "$group" ]] && continue

            local remainder="${entry#*|}"
            local aliases="${remainder%|*}"
            local desc="${remainder##*|}"

            local display_aliases=$(echo "$aliases" | sed 's/|/, /g')
            printf "    ${PINK}%-22s ${GRAY}-${RESET} %s\n" "$display_aliases" "$desc"
        done
        echo ""
    done
}

register_command "SYSTEM" "-h|--help" "Show this interface" "show_usage"
