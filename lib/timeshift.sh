#!/bin/bash

rx_timeshift_limit_by_description() {
    local prefix="${1:-}"
    local max="${2:-3}"

    if [[ -z $prefix ]]; then
        return 1
    fi

    if ! command -v timeshift &>/dev/null; then
        return 0
    fi

    local output
    output=$(sudo -n timeshift --list 2>&1) || return 0

    if echo "$output" | grep -qi "auth\|password\|no snapshots found"; then
        return 0
    fi

    local snapshots=()
    while IFS= read -r snap; do
        [[ -n $snap ]] && snapshots+=("$snap")
    done < <(echo "$output" | grep -F "$prefix" | awk '{print $3}')

    local count=${#snapshots[@]}
    if [[ $count -le $max ]]; then
        return 0
    fi

    local delete_count=$((count - max))
    for ((i=0; i<delete_count; i++)); do
        sudo -n timeshift --delete --snapshot "${snapshots[$i]}" >/dev/null 2>&1 || true
    done

    return 0
}
