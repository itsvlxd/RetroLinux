#!/bin/bash

ERROR_HANDLING=false

rx_show_cursor() {
    printf "\033[?25h"
}

rx_show_log_tail() {
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

rx_show_failed_script_or_command() {
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

rx_save_original_outputs() {
    exec 3>&1 4>&2
}

rx_restore_outputs() {
    if [[ -e /proc/self/fd/3 ]] && [[ -e /proc/self/fd/4 ]]; then
        exec 1>&3 2>&4
    fi
}

rx_catch_errors() {
    ERROR_HANDLING=false

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        return
    fi

    plymouth quit 2>/dev/null || true
    rx_stop_log_output
    rx_restore_outputs

    rx_clear_logo
    rx_show_cursor

    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "RetroLinux installation stopped!"
    rx_show_log_tail

    gum style "This command halted with exit code $exit_code:"
    rx_show_failed_script_or_command

    echo
    rx_generate_error_qr "$exit_code"
    echo
    gum style "Get help from the community via QR code or at https://github.com/itsvlxd/RetroLinux/issues"

    ERROR_HANDLING=true
    while true; do
        local options=()

        options+=("Retry installation")
        options+=("View full log")
        options+=("Exit")

        local choice
        choice=$(gum choose "${options[@]}" --header "What would you like to do?" --height 6 --padding "$GUM_CHOOSE_PADDING") || break

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

rx_exit_handler() {
    local exit_code=$?

    if ((exit_code != 0)) && [[ $ERROR_HANDLING != "true" ]]; then
        rx_catch_errors
    else
        rx_stop_log_output
        rx_show_cursor
    fi
}

rx_show_signal_info() {
    local sig_name="$1"
    rx_show_cursor
    rx_clear_logo
    echo
    gum style --foreground 3 --padding "0 0 0 $PADDING_LEFT" "Installation interrupted"
    gum style "Signal received: $sig_name"
    echo
    gum style "Your configuration has been saved."
    gum style "Run 'retroinstall' to resume anytime."
    echo
    exit 128
}

rx_setup_traps() {
    trap rx_catch_errors ERR
    trap 'rx_show_signal_info "SIGINT"' INT
    trap 'rx_show_signal_info "SIGTERM"' TERM
    trap rx_exit_handler EXIT
    rx_save_original_outputs
}

rx_save_state() {
    cat <<EOF > "$RETRO_STATE"
KEYBOARD="$KEYBOARD"
SYS_LANG="$SYS_LANG"
SYS_ENC="$SYS_ENC"
USER_PASSWORD_HASH="$USER_PASSWORD_HASH"
USER_PASSWORD="$USER_PASSWORD"
USER_NAME="$USER_NAME"
USER_HOSTNAME="$USER_HOSTNAME"
USER_TIMEZONE="$USER_TIMEZONE"
DISK_SELECTED="$DISK_SELECTED"
NETWORK_TYPE="$NETWORK_TYPE"
WIFI_SSID="$WIFI_SSID"
RX_CURRENT_STEP="$RX_CURRENT_STEP"
RX_START_STEP="${RX_START_STEP:-1}"
RX_SKIP_STEP="$RX_SKIP_STEP"
RX_GO_BACK_TO="$RX_GO_BACK_TO"
EOF
}

rx_load_state() {
    if [[ -f "$RETRO_STATE" ]]; then
        source "$RETRO_STATE"
    fi
}