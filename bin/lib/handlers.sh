#!/bin/bash

ERROR_HANDLING=false

rx_show_cursor() {
    printf "\033[?25h"
}

rx_show_log_tail() {
    if [[ -f $RETRO_INSTALL_LOG_FILE ]]; then
        local log_lines=$((TERM_HEIGHT - LOGO_HEIGHT - 35))
        (( log_lines < 5 )) && log_lines=5
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
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Exit code: $exit_code"

    echo
    rx_generate_error_qr "$exit_code"
    echo
    gum style "Scan the QR code above to report this issue"

    echo
    gum style "This command halted:"
    rx_show_failed_script_or_command

    echo
    gum style "Last output from the failing process:"
    rx_show_log_tail

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
        rx_stop_install_log
    fi
}

rx_show_signal_info() {
    local sig_name="$1"
    rx_save_state
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

# Global state - always load on module source

rx_save_state() {
    cat <<EOF > "$RETRO_STATE"
KEYBOARD="$KEYBOARD"
SYS_LANG="$SYS_LANG"
SYS_ENC="$SYS_ENC"
USER_PASSWORD="$USER_PASSWORD"
USER_NAME="$USER_NAME"
USER_HOSTNAME="$USER_HOSTNAME"
USER_TIMEZONE="$USER_TIMEZONE"
DISK_SELECTED="$DISK_SELECTED"
NETWORK_TYPE="$NETWORK_TYPE"
WIFI_SSID="$WIFI_SSID"
WIFI_PASSWORD="$WIFI_PASSWORD"
ROOT_PASSWORD="$ROOT_PASSWORD"
USER_SUDO="$USER_SUDO"
LUKS_ENABLED="$LUKS_ENABLED"
LUKS_PASSWORD="$LUKS_PASSWORD"
LUKS_ITER_TIME="$LUKS_ITER_TIME"
KERNEL_SELECTION="$KERNEL_SELECTION"
BLUETOOTH_ENABLED="$BLUETOOTH_ENABLED"
PRINT_SERVICE_ENABLED="$PRINT_SERVICE_ENABLED"
CUSTOM_MIRRORS="$CUSTOM_MIRRORS"
MIRROR_REGIONS="$MIRROR_REGIONS"
RX_CURRENT_STEP="$RX_CURRENT_STEP"
RX_START_STEP="${RX_START_STEP:-1}"
RX_SKIP_STEP="$RX_SKIP_STEP"
RX_GO_BACK_TO="$RX_GO_BACK_TO"
SSH_ENABLED="$SSH_ENABLED"
SSH_PORT="$SSH_PORT"
SSH_PASSWORD_LOGIN="$SSH_PASSWORD_LOGIN"
SSH_KEY_LOGIN="$SSH_KEY_LOGIN"
SSH_ROOT_LOGIN="$SSH_ROOT_LOGIN"
GRUB_THEME_CHOICE="$GRUB_THEME_CHOICE"
BOOT_VIDEO_GRUB="$BOOT_VIDEO_GRUB"
GRUB_OS_PROBER="$GRUB_OS_PROBER"
DISPLAY_ASPECT_RATIO="$DISPLAY_ASPECT_RATIO"
DISPLAY_RES_X="$DISPLAY_RES_X"
DISPLAY_RES_Y="$DISPLAY_RES_Y"
AUR_HELPER="$AUR_HELPER"
EDITOR_CHOICE="$EDITOR_CHOICE"
INSTALL_TYPE="$INSTALL_TYPE"
FILEMANAGER_CHOICE="$FILEMANAGER_CHOICE"
BROWSER_CHOICE="$BROWSER_CHOICE"
WALLPAPER_RES="$WALLPAPER_RES"
FINGERPRINT_ENABLED="$FINGERPRINT_ENABLED"
FIREWALL_ENGINE="$FIREWALL_ENGINE"
RICE_MODE="$RICE_MODE"
RETRO_BRANCH="$RETRO_BRANCH"
GRUB_SNAPSHOTS_ENABLED="$GRUB_SNAPSHOTS_ENABLED"
GRUB_TIMEOUT="$GRUB_TIMEOUT"
GRUB_KERNEL="$GRUB_KERNEL"
EOF
}

rx_load_state() {
    if [[ -f "$RETRO_STATE" ]]; then
        source "$RETRO_STATE"
    fi
}

# Global state - always load on module source
rx_load_state

rx_restore_disk_selection() {
    rx_clear_logo
    RX_CURRENT_STEP="disk"
    rx_step "Selecting install disk..."
    
    local available_disks
    available_disks=$(rx_get_available_disks) || return 1
    
    [[ -z $available_disks ]] && return 1
    
    local disk_options=""
    while IFS= read -r device; do
        if [[ -n $device ]]; then
            local disk_info
            disk_info=$(rx_get_disk_info "$device")
            disk_options="$disk_options$disk_info"$'\n'
        fi
    done <<<"$available_disks"
    
    local selected_display
    selected_display=$(echo "$disk_options" | gum choose --header "Select install disk" --height 15 --padding "$GUM_CHOOSE_PADDING") || return 1
    
    DISK_SELECTED=$(echo "$selected_display" | awk '{print $1}')
    
    [[ -z $DISK_SELECTED ]] && return 1
    
    rx_save_state
    return 0
}