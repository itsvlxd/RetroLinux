#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"

check_slideshow() {
    local slideshow_active
    slideshow_active=$(get_var "WALL_SLIDESHOW_ACTIVE" "false")

    if [[ $slideshow_active != "true" ]]; then
        return
    fi

    local interval
    interval=$(get_var "WALL_SLIDESHOW_INTERVAL" "300")
    local target_ticks=$interval

    if [[ $interval == "random" ]]; then
        if ((current_rand_target == 0)); then
            current_rand_target=$((RANDOM % 900 + 300))
        fi
        target_ticks=$current_rand_target
    fi

    if ((slideshow_tick >= target_ticks)); then
        broadcast_event "on_slideshow_tick"
        slideshow_tick=0
        current_rand_target=0
    fi

    ((slideshow_tick++))
}

start_watcher_slideshow() {
    slideshow_tick=0
    current_rand_target=0

    while true; do
        check_slideshow
        sleep 1
    done
}