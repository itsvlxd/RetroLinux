#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/help.sh"

cmd_load() {
    local action="$1"

    local setup_mode=false
    [[ -f $HOME/.retro_install ]] && setup_mode=true

    if $setup_mode; then
        startup_tasks+=("retro --setup|Running first boot system setup")
    else
        startup_tasks+=("retro shell start|Initializing RetroLinux quick shell")
    fi

    startup_tasks+=(
        "retro xdg portal inject|Injecting session env into XDG portal daemon"
        "retro firewall on|Enabling nftables firewall"

        "retro bluetooth restore|Initializing bluetooth radio cards"
        "retro audio easyeffects start|Initializing audio drivers"
        "retro daemon start|Initializing retro daemon engine and watchers"
        "retro polkit start|Starting auth agent and keyring daemon"
        "retro power restore|Restoring hardware power profiles"
        "retro wallpaper restore|Applying last used wallpaper"
        "retro xdg dirs reset|Ensuring XDG user directories exist"
        "retro xdg portal screenshare|Starting XWayland video bridge for screen sharing"
        "retro xdg flatpak|Bridging host MIME defaults into Flatpak sandbox"

        "retro benchmark hud load|Loads mangohud and benchmark variables"

        "retro display scale --from-dpi|Applying display scaling to XWayland DPI"

        # NOTE: Deprected bitwarden integration
        "rbw config set sync_interval $(get_var 'CLIP_WARDEN_SYNC')|Synchronizing vault refresh interval with global security policy"
        "rbw config set lock_timeout $(get_var 'CLIP_WARDEN_TIMEOUT')|Enforcing automated vault hibernation and session locking"
    )

    [[ $(get_var "HYPRIDLE_ENABLE" "true") == "true" ]] && startup_tasks+=("retro shell idle|Starting Hyprland idle daemon")

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
            rx_table_header "󱗼" "Startup Sequence"

            for task in "${startup_tasks[@]}"; do
                IFS='|' read -r cmd desc <<<"$task"
                rx_table_simple "󰄾" "$cmd" "$MUTE"
                rx_help_wrap "$desc" 50
            done

            if [[ ${#custom_tasks[@]} -gt 0 ]]; then
                rx_table_separator
                for task in "${custom_tasks[@]}"; do
                    IFS='|' read -r cmd desc <<<"$task"
                    [[ -n $cmd ]] && rx_table_simple "󰄾" "$cmd" "$GRAY"
                done
            fi

            rx_table_separator
            rx_table_spacer
            ;;

        "list-raw")
            for task in "${startup_tasks[@]}"; do
                echo "$task"
            done
            ;;

        "status")
            rx_table_header "󱗼" "Startup Status"

            local boot_time=$(uptime -s 2>/dev/null)
            local uptime_secs=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
            local uptime_disp="Just now"
            [[ -n $uptime_secs ]] && uptime_disp=$(rx_format_uptime "$uptime_secs")
            local an_total=""
            if command -v systemd-analyze >/dev/null 2>&1; then
                an_total=$(systemd-analyze 2>/dev/null | head -1)
            fi

            rx_table_row "󰧠" "Boot time:" "$boot_time" "$GRAY" "20"
            rx_table_row "󰕭" "Uptime:" "$uptime_disp" "$GRAY" "20"
            [[ -n $an_total ]] && rx_table_row "󰦐" "Startup:" "${an_total:0:60}" "$PINK" "20"

            rx_table_separator
            for task in "${final_tasks[@]}"; do
                IFS='|' read -r cmd desc <<<"$task"

                local bin_name=$(echo "$cmd" | awk '{print $1}')
                local running=false
                if [[ $bin_name == "retro" ]]; then
                    local sub_arg=$(echo "$cmd" | awk '{print $2}')
                    if pgrep -f "retro $sub_arg" >/dev/null 2>&1; then
                        running=true
                    fi
                else
                    if pgrep -f "^$cmd" >/dev/null 2>&1; then
                        running=true
                    fi
                fi

                if $running; then
                    rx_table_simple "󰄴" "$cmd" "$SUCCESS"
                else
                    rx_table_simple "󰄾" "$cmd" "$MUTE"
                fi
                rx_help_wrap "$desc" 50
            done

            rx_table_separator
            rx_table_spacer
            ;;

        "all" | "")
            if $setup_mode; then
                rx_log "info" "First boot detected — running post-install setup only."
                if pgrep -f "run_postinstall" >/dev/null 2>&1; then
                    rx_log "info" "Post-install setup already running, skipping duplicate launch."
                    return 0
                fi

                local terminal=""
                if command -v kitty >/dev/null 2>&1; then
                    terminal="kitty"
                elif [[ -n ${TERMINAL:-} ]] && command -v "$TERMINAL" >/dev/null 2>&1; then
                    terminal="$TERMINAL"
                fi

                if [[ -n $terminal ]]; then
                    exec "$terminal" -e bash -c "/opt/retrolinux/retro.sh --setup"
                else
                    rx_log "warn" "No graphical terminal found, running setup in the background"
                    nohup /opt/retrolinux/retro.sh --setup >/dev/null 2>&1 &
                    disown
                fi
                return 0
            fi

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
            rx_log "info" "Usage: retro --load [all|list|status]"
            ;;
    esac
}

register_command "SYSTEM" "-l|--load" "Execute or list the system startup sequence" "cmd_load"

if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    cmd_load "$@"
fi
