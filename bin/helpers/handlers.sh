ERROR_HANDLING=false

show_cursor() {
    printf "\033[?25h"
}

show_log_tail() {
    if [[ -f $RETRO_INSTALL_LOG_FILE ]]; then
        local log_lines=$((TERM_HEIGHT - LOGO_HEIGHT - 35))
        local max_line_width=$((LOGO_WIDTH - 4))

        tail -n $log_lines "$RETRO_INSTALL_LOG_FILE" | while IFS= read -r line; do
            if ((${#line} > max_line_width)); then
                local truncated_line="${line:0:max_line_width}..."
            else
                local truncated_line="$line"
            fi

            gum style "$truncated_line"
        done

        echo
    fi
}

show_failed_script_or_command() {
    if [[ -n ${CURRENT_SCRIPT:-} ]]; then
        gum style "Failed script: $CURRENT_SCRIPT"
    else
        local cmd="$BASH_COMMAND"
        local max_cmd_width=$((LOGO_WIDTH - 4))

        if ((${#cmd} > max_cmd_width)); then
            cmd="${cmd:0:max_cmd_width}..."
        fi

        gum style "$cmd"
    fi
}

save_original_outputs() {
    exec 3>&1 4>&2
}

restore_outputs() {
    if [[ -e /proc/self/fd/3 ]] && [[ -e /proc/self/fd/4 ]]; then
        exec 1>&3 2>&4
    fi
}

gather_system_info() {
    local info=""

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        info+="OS: $PRETTY_NAME\n"
    else
        info+="OS: RetroLinux (unknown version)\n"
    fi

    if command -v lscpu &>/dev/null; then
        local cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
        [[ -z $cpu_model ]] && cpu_model=$(lscpu | grep "Model:" | cut -d: -f2 | xargs)
        info+="CPU: $cpu_model\n"
    fi

    if [[ -f /proc/meminfo ]]; then
        local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local mem_gb=$((mem_kb / 1024 / 1024))
        info+="RAM: ${mem_gb}GB\n"
    fi

    if command -v lsblk &>/dev/null; then
        local storage=$(lsblk -dno NAME,SIZE,TYPE | grep disk | awk '{print $1 " (" $2 ")"}' | tr '\n' ', ')
        storage="${storage%,}"
        [[ -n $storage ]] && info+="Storage: $storage\n"
    fi

    local wifi_driver wifi_card eth_driver eth_card

    wifi_card=$(ip link show 2>/dev/null | grep -E "^[0-9]+: wlan[0-9]+" | awk -F': ' '{print $2}' | head -n1)
    if [[ -n $wifi_card ]]; then
        wifi_driver=$(ethtool -i "$wifi_card" 2>/dev/null | grep driver | cut -d: -f2 | xargs)
        [[ -z $wifi_driver ]] && wifi_driver="unknown"
        info+="WiFi: $wifi_card (driver: $wifi_driver)\n"
    fi

    eth_card=$(ip link show 2>/dev/null | grep -E "^[0-9]+: (eth|en)" | awk -F': ' '{print $2}' | head -n1)
    if [[ -n $eth_card ]]; then
        eth_driver=$(ethtool -i "$eth_card" 2>/dev/null | grep driver | cut -d: -f2 | xargs)
        [[ -z $eth_driver ]] && eth_driver="unknown"
        info+="Ethernet: $eth_card (driver: $eth_driver)\n"
    fi

    echo -e "$info"
}

generate_error_qr() {
    local exit_code=$1

    local repo_url="github.com/itsvlxd/RetroLinux/issues/new"
    local issue_title="Installation Halt - Exit Code $exit_code"
    local system_specs

    system_specs=$(gather_system_info)

    local log_content=""
    if [[ -f $RETRO_INSTALL_LOG_FILE ]]; then
        log_content=$(tail -c 6000 "$RETRO_INSTALL_LOG_FILE" 2>/dev/null | tr '\n' '.' | sed 's/^\.+//;s/\.\+/ /g')
    fi

    local issue_body="Installer failed during RetroLinux setup.

=== SYSTEM SPECS ===
$system_specs
=== ERROR LOG ===
$log_content

Please describe what happened below:"

    local full_url="https://${repo_url}?title=${issue_title// /+}&body=${issue_body// /+}"
    qrencode -t ANSIUTF8 "$full_url"
}

    qrencode -t ANSIUTF8 "$full_url"
}

catch_errors() {
    if [[ $ERROR_HANDLING == "true" ]]; then
        return
    else
        ERROR_HANDLING=true
    fi

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        return
    fi

    plymouth quit 2>/dev/null || true
    stop_log_output
    restore_outputs

    clear_logo
    show_cursor

    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "RetroLinux installation stopped!"
    show_log_tail

    gum style "This command halted with exit code $exit_code:"
    show_failed_script_or_command

    echo
    generate_error_qr "$exit_code"
    echo
    gum style "Get help from the community via QR code or at https://github.com/itsvlxd/RetroLinux/issues"

    while true; do
        options=()

        options+=("Retry installation")
        options+=("View full log")
        options+=("Exit")

        choice=$(gum choose "${options[@]}" --header "What would you like to do?" --height 6 --padding "$GUM_CHOOSE_PADDING")

        case "$choice" in
            "Retry installation")
                exec /opt/retrolinux/bin/retroinstall
                ;;
            "View full log")
                if command -v less &>/dev/null; then
                    less "$RETRO_INSTALL_LOG_FILE"
                else
                    tail "$RETRO_INSTALL_LOG_FILE"
                fi
                ;;
            "Exit" | "")
                exit 1
                ;;
        esac
    done
}

exit_handler() {
    local exit_code=$?

    if ((exit_code != 0)) && [[ $ERROR_HANDLING != "true" ]]; then
        catch_errors
    else
        stop_log_output
        show_cursor
    fi
}

show_signal_info() {
    local sig_name="$1"
    show_cursor
    clear_logo
    echo
    gum style --foreground 3 --padding "0 0 0 $PADDING_LEFT" "Installation interrupted"
    gum style "Signal received: $sig_name"
    echo
    gum style "Your configuration has been saved."
    gum style "Run 'retroinstall' to resume anytime."
    echo
    exit 128
}

trap catch_errors ERR
trap 'show_signal_info "SIGINT"' INT
trap 'show_signal_info "SIGTERM"' TERM
trap exit_handler EXIT

save_original_outputs
