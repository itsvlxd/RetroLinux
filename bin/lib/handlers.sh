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
    {
        printf 'KEYBOARD=%q\n' "$KEYBOARD"
        printf 'SYS_LANG=%q\n' "$SYS_LANG"
        printf 'SYS_ENC=%q\n' "$SYS_ENC"
        printf 'USER_PASSWORD=%q\n' "$USER_PASSWORD"
        printf 'USER_NAME=%q\n' "$USER_NAME"
        printf 'USER_HOSTNAME=%q\n' "$USER_HOSTNAME"
        printf 'USER_TIMEZONE=%q\n' "$USER_TIMEZONE"
        printf 'DISK_SELECTED=%q\n' "$DISK_SELECTED"
        printf 'NETWORK_TYPE=%q\n' "$NETWORK_TYPE"
        printf 'WIFI_SSID=%q\n' "$WIFI_SSID"
        printf 'WIFI_PASSWORD=%q\n' "$WIFI_PASSWORD"
        printf 'ROOT_PASSWORD=%q\n' "$ROOT_PASSWORD"
        printf 'USER_SUDO=%q\n' "$USER_SUDO"
        printf 'LUKS_ENABLED=%q\n' "$LUKS_ENABLED"
        printf 'LUKS_PASSWORD=%q\n' "$LUKS_PASSWORD"
        printf 'LUKS_ITER_TIME=%q\n' "$LUKS_ITER_TIME"
        printf 'KERNEL_SELECTION=%q\n' "$KERNEL_SELECTION"
        printf 'BLUETOOTH_ENABLED=%q\n' "$BLUETOOTH_ENABLED"
        printf 'PRINT_SERVICE_ENABLED=%q\n' "$PRINT_SERVICE_ENABLED"
        printf 'CUSTOM_MIRRORS=%q\n' "$CUSTOM_MIRRORS"
        printf 'MIRROR_REGIONS=%q\n' "$MIRROR_REGIONS"
        printf 'RX_CURRENT_STEP=%q\n' "$RX_CURRENT_STEP"
        printf 'RX_START_STEP=%q\n' "${RX_START_STEP:-1}"
        printf 'RX_SKIP_STEP=%q\n' "$RX_SKIP_STEP"
        printf 'RX_GO_BACK_TO=%q\n' "$RX_GO_BACK_TO"
        printf 'SSH_ENABLED=%q\n' "$SSH_ENABLED"
        printf 'SSH_PORT=%q\n' "$SSH_PORT"
        printf 'SSH_PASSWORD_LOGIN=%q\n' "$SSH_PASSWORD_LOGIN"
        printf 'SSH_KEY_LOGIN=%q\n' "$SSH_KEY_LOGIN"
        printf 'SSH_ROOT_LOGIN=%q\n' "$SSH_ROOT_LOGIN"
        printf 'GRUB_THEME_CHOICE=%q\n' "$GRUB_THEME_CHOICE"
        printf 'BOOT_VIDEO_GRUB=%q\n' "$BOOT_VIDEO_GRUB"
        printf 'GRUB_OS_PROBER=%q\n' "$GRUB_OS_PROBER"
        printf 'DISPLAY_ASPECT_RATIO=%q\n' "$DISPLAY_ASPECT_RATIO"
        printf 'DISPLAY_RES_X=%q\n' "$DISPLAY_RES_X"
        printf 'DISPLAY_RES_Y=%q\n' "$DISPLAY_RES_Y"
        printf 'AUR_HELPER=%q\n' "$AUR_HELPER"
        printf 'EDITOR_CHOICE=%q\n' "$EDITOR_CHOICE"
        printf 'INSTALL_TYPE=%q\n' "$INSTALL_TYPE"
        printf 'FILEMANAGER_CHOICE=%q\n' "$FILEMANAGER_CHOICE"
        printf 'BROWSER_CHOICE=%q\n' "$BROWSER_CHOICE"
        printf 'WALLPAPER_RES=%q\n' "$WALLPAPER_RES"
        printf 'FINGERPRINT_ENABLED=%q\n' "$FINGERPRINT_ENABLED"
        printf 'FIREWALL_ENGINE=%q\n' "$FIREWALL_ENGINE"
        printf 'RICE_MODE=%q\n' "$RICE_MODE"
        printf 'RETRO_BRANCH=%q\n' "$RETRO_BRANCH"
        printf 'GRUB_SNAPSHOTS_ENABLED=%q\n' "$GRUB_SNAPSHOTS_ENABLED"
        printf 'GRUB_TIMEOUT=%q\n' "$GRUB_TIMEOUT"
        printf 'GRUB_KERNEL=%q\n' "$GRUB_KERNEL"
    } > "$RETRO_STATE"
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