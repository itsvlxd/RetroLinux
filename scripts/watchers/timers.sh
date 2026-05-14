#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"

check_package_updates() {
    local helper
    helper=$(get_var "PKG_HELPER" "yay")

    local pac_count
    pac_count=$(checkupdates 2>/dev/null | wc -l)
    local aur_count
    aur_count=$($helper -Qu 2>/dev/null | wc -l)
    local total=$((pac_count + aur_count))

    local raw_thresh
    raw_thresh=$(get_var "RETRO_PKG_UPDATE_THRESH" "20")
    local thresh
    thresh=$(echo "$raw_thresh" | tr -dc '0-9')
    [[ -z $thresh ]] && thresh=20

    if [[ $total -gt 0 ]] && [[ $total -ge $thresh ]]; then
        local sample
        sample=$( (checkupdates 2>/dev/null; $helper -Qu 2>/dev/null) | head -n 3 | awk '{print $1}' | xargs | sed 's/ /, /g')

        broadcast_event "on_pkg_updates_available" "$total" "$sample"
    fi
}

check_retro_updates() {
    if [[ ! -d "$RETRO_DIR/.git" ]]; then
        return
    fi

    git -C "$RETRO_DIR" fetch origin 2>/dev/null

    local current_branch
    current_branch=$(git -C "$RETRO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

    local behind
    behind=$(git -C "$RETRO_DIR" rev-list --count HEAD..origin/$current_branch 2>/dev/null)

    if [[ -n $behind && $behind -gt 0 ]]; then
        broadcast_event "on_retro_update_available" "$behind"
    fi
}

start_watcher_timers() {
    local last_pkg_check=0
    local last_retro_check=0

    local pkg_min
    pkg_min=$(get_var "RETRO_PKG_UPDATE_MIN" "60")
    local pkg_interval=$((pkg_min * 60))

    local retro_min
    retro_min=$(get_var "RETRO_UPDATE_CHECK_MIN" "15")
    local retro_interval=$((retro_min * 60))

    while true; do
        local now
        now=$(date +%s)

        if ((now - last_pkg_check > pkg_interval)); then
            check_package_updates
            last_pkg_check=$now
        fi

        if ((now - last_retro_check > retro_interval)); then
            check_retro_updates
            last_retro_check=$now
        fi

        sleep 60
    done
}