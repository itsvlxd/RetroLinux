#!/bin/bash

rx_vars_defaults() {
    local force_flag="$1"
    local var_script="$RETRO_DIR/scripts/var_core.sh"

    rx_log "info" "Checking vars..."

    local defaults=(
        "BAT_SAVER_THRESHOLD|50"
        "BAT_NOTIFY_THRESHOLD|30"
        "BAT_NOTIFY_CRITICAL_THRESHOLD|15"

        "BAT_SAVER_ACTIVE|false"
        "BAT_SAVER_FORCED|false"
    )

    local count=0
    for entry in "${defaults[@]}"; do
        IFS='|' read -r key val <<<"$entry"

        if [[ "$force_flag" == "-f" || "$force_flag" == "--force" ]]; then
            bash "$var_script" set "$key" "$val"
            ((count++))
        elif [[ -z $(bash "$var_script" get "$key") ]]; then
            bash "$var_script" set "$key" "$val"
            ((count++))
        fi
    done

    if [[ "$force_flag" == "-f" || "$force_flag" == "--force" ]]; then
        rx_log "success" "Vars reset: $count values forced to defaults."
    elif [[ "$count" -gt 0 ]]; then
        rx_log "success" "Vars updated: $count missing values added."
    else
        rx_log "success" "Vars preserved: Existing values kept."
    fi
}
