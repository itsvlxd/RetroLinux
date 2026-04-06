#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

# TODO: Add also boot time metric and change from list to status

cmd_load() {
    local action="$1"

    local startup_tasks=(
        "retro power restore|Restoring hardware power profiles"
        "retro event start|Initializing event loop and custom hooks"
        "retro wallpaper restore|Applying last used wallpaper"

        "retro benchmark hud load|Loads mangohud and benchmark variables"

        "wl-paste --type text --watch cliphist store -ignore-secrets|Starting cliphist text store watcher"
        "wl-paste --type image --watch cliphist store -ignore-secrets|Starting cliphist image store watcher"

        "rbw config set sync_interval $(get_var 'CLIP_WARDEN_SYNC')|Synchronizing vault refresh interval with global security policy"
        "rbw config set lock_timeout $(get_var 'CLIP_WARDEN_TIMEOUT')|Enforcing automated vault hibernation and session locking"
    )

    local auto_load=$(get_var "RETRO_SESSION_AUTOLOAD")
    if [[ $auto_load == "true" ]]; then
        startup_tasks+=("retro window restore|Restoring the last Hyprland window snapshot")
    fi

    local custom_tasks=()
    local custom_raw=$(get_var "RETRO_CUSTOM_LOAD")

    if [[ -n $custom_raw && $custom_raw != "null" ]]; then
        IFS='|' read -ra custom_parts <<<"$custom_raw"
        for c_cmd in "${custom_parts[@]}"; do
            local clean_cmd=$(echo "$c_cmd" | xargs)
            [[ -n $clean_cmd ]] && custom_tasks+=("$clean_cmd")
        done
    fi

    local final_tasks=("${startup_tasks[@]}")
    for c in "${custom_tasks[@]}"; do final_tasks+=("$c|Starting Custom User Tasks"); done

    case "$action" in
        "list")
            echo -e "\n ${PINK}󱗼 Startup Sequence${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            for task in "${startup_tasks[@]}"; do
                IFS='|' read -r cmd desc <<<"$task"
                printf " ${PINK}󰄾${RESET} %-35s ${MUTE}\n   ${GRAY}%s\n" "$cmd" "$desc"
            done

            if [[ ${#custom_tasks[@]} -gt 0 ]]; then
                echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
                for task in "${custom_tasks[@]}"; do
                    IFS='|' read -r cmd desc <<<"$task"
                    [[ -n $cmd ]] && printf " ${PINK}󰄾${RESET} %-35s\n" "$cmd"
                done
            fi

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "all" | "")
            rx_log "info" "Syncing startup state..."

            for task in "${final_tasks[@]}"; do
                IFS='|' read -r cmd desc <<<"$task"

                local bin_name=$(echo "$cmd" | awk '{print $1}')
                local needs_kill=false
                local pkill_cmd=""

                if [[ $bin_name == "retro" ]]; then
                    local sub_arg=$(echo "$cmd" | awk '{print $2}')
                    if pgrep -f "retro $sub_arg" >/dev/null 2>&1; then
                        needs_kill=true
                        pkill_cmd="pkill -f \"retro $sub_arg\""
                    fi
                else
                    if pgrep -f "^$cmd" >/dev/null 2>&1; then
                        needs_kill=true
                        pkill_cmd="pkill -f \"^$cmd\""
                    fi
                fi

                if [[ $needs_kill == "true" ]]; then
                    rx_log "info" "Refreshing: ${PINK}$bin_name${RESET}"
                    eval "$pkill_cmd" >/dev/null 2>&1
                    sleep 0.2
                fi

                rx_log "info" "$desc..."
                nohup bash -c "$cmd" >/dev/null 2>&1 &
                disown
            done

            rx_log "success" "Startup sequence synchronized."
            ;;
        *)
            rx_log "info" "Usage: retro --load [all|list]"
            ;;
    esac
}

register_command "SYSTEM" "-l|--load" "Execute or list the system startup sequence" "cmd_load"
