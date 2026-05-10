#!/bin/bash

rx_menu() {
    local icon="$1"
    local question="$2"
    shift 2
    local options=("$@")
    local num_options=${#options[@]}

    echo "" >&2
    echo -e " ${PINK}${icon}  ${RESET}${question}" >&2
    echo "" >&2

    for i in "${!options[@]}"; do
        local num=$((i + 1))
        echo -e "  ${PINK}${num})${RESET} ${options[$i]}" >&2
    done

    echo "" >&2
    while true; do
        echo -ne " ${PINK}󰄾${RESET} Select ${MUTE}[1-${num_options}]${RESET}: " >&2
        read -r choice
        if [[ $choice =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $num_options ]]; then
            echo "${options[$((choice - 1))]}"
            return 0
        fi
        rx_log "warn" "Invalid selection" >&2
    done
}

rx_tools_menu() {
    local icon="$1"
    local question="$2"
    shift 2
    local options=("$@")
    local num_options=${#options[@]}
    local selected_indices=()

    _rx_tools_print() {
        for i in "${!options[@]}"; do
            local num=$((i + 1))
            local checked="[ ]"
            for idx in "${selected_indices[@]}"; do
                [[ $idx == "$i" ]] && checked="[x]" && break
            done
            echo -e "  ${checked} ${PINK}${num})${RESET} ${options[$i]}" >&2
        done
        echo "" >&2
        echo -ne " ${PINK}󰄾${RESET} Toggle or press Enter to confirm: " >&2
    }

    echo "" >&2
    echo -e " ${PINK}${icon}  ${RESET}${question}" >&2
    echo "" >&2
    _rx_tools_print

    while true; do
        read -r -n 1 key
        echo "" >&2

        if [[ -z $key ]]; then
            if [[ ${#selected_indices[@]} -gt 0 ]]; then
                for idx in "${selected_indices[@]}"; do
                    echo "${options[$idx]}"
                done
            fi
            return 0
        fi

        if [[ $key =~ ^[0-9]$ ]] && [[ $key -ge 1 ]] && [[ $key -le $num_options ]]; then
            local idx=$((key - 1))
            local found=0
            local new_indices=()
            for existing_idx in "${selected_indices[@]}"; do
                [[ $existing_idx == "$idx" ]] && found=1 || new_indices+=("$existing_idx")
            done
            [[ $found == "0" ]] && new_indices+=("$idx")
            selected_indices=("${new_indices[@]}")

            printf "\033[2J" >&2
            printf "\033[H" >&2
            echo "" >&2
            echo -e " ${PINK}${icon}  ${RESET}${question}" >&2
            echo "" >&2
            _rx_tools_print
        fi
    done
}

rx_check_root() {
    if [[ $EUID -ne 0 ]]; then
        rx_log "error" "This script needs ${PINK}root${RESET} privileges"
        return 1
    fi
    return 0
}
