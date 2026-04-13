#!/bin/bash

source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/git.sh"

EVENT_DIR="$RETRO_DIR/scripts/events"
WATCHER_DIR="$RETRO_DIR/scripts/watchers"

broadcast_event() {
    local event_name="$1"
    shift

    for hook_file in "$EVENT_DIR"/*.sh; do
        [[ -f $hook_file ]] || continue
        (
            source "$hook_file"
            if declare -f "$event_name" >/dev/null 2>&1; then
                "$event_name" "$@"
            fi
        )
    done
}

for watcher_file in "$WATCHER_DIR"/*.sh; do
    [[ -f $watcher_file ]] && source "$watcher_file"
done

run_event_loop() {
    broadcast_event "on_event_loop_start"

    declare -a WATCHER_PIDS
    local watchers
    watchers=$(declare -F | awk '{print $3}' | grep "^start_watcher_" | sort)

    if [[ -z "$watchers" ]]; then
        exit 0
    fi

    for watcher in $watchers; do
        "$watcher" &
        WATCHER_PIDS+=($!)
    done

    trap 'kill "${WATCHER_PIDS[@]}" 2>/dev/null; exit' INT TERM

    wait
}

case "$1" in
    "--loop") run_event_loop ;;
    "--trigger") broadcast_event "$2" "${@:3}" ;;
esac