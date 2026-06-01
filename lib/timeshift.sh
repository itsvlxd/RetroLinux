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

    local snapshots=()
    while IFS= read -r snap; do
        [[ -n $snap ]] && snapshots+=("$snap")
    done < <(sudo timeshift --list-snapshots 2>/dev/null | grep -F "$prefix" | awk '{print $3}')

    local count=${#snapshots[@]}
    if [[ $count -le $max ]]; then
        return 0
    fi

    local delete_count=$((count - max))
    for ((i=0; i<delete_count; i++)); do
        sudo timeshift --delete --snapshot "${snapshots[$i]}" >/dev/null 2>&1 || true
    done

    return 0
}
