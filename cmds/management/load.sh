#!/bin/bash

cmd_load() {
    local action="$1"

    local startup_tasks=(
        "retro --wallpaper restore|Applying last used wallpaper"
        "retro --power restore|Restoring hardware power profiles"
        "retro --event restart|Initializing event loop and custom hooks"
    )

    case "$action" in
        "list")
            echo -e "\n ${PINK}󱗼 Startup Sequence List:${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            for task in "${startup_tasks[@]}"; do
                IFS='|' read -r cmd desc <<<"$task"
                printf " ${PINK}󰄾${RESET} %-25s ${GRAY} - ${RESET}%s\n" "$cmd" "$desc"
            done
            echo ""
            ;;

        "all" | "")
            rx_log "info" "Initiating modular startup sequence..."

            for task in "${startup_tasks[@]}"; do
                IFS='|' read -r cmd desc <<<"$task"

                rx_log "info" "$desc..."

                nohup bash -c "$cmd" >/dev/null 2>&1 &
            done

            rx_log "success" "Startup sequence completed."
            ;;

        *)
            rx_log "info" "Usage: retro --load [all|list]"
            ;;
    esac
}

register_command "SYSTEM" "-l|--load" "Execute or list the system startup sequence" "cmd_load"
