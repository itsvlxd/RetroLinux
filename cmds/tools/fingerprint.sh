#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

# TODO: Find a way in the future if we can implement it inside SDDM

setup_pam_auth() {
    rx_log "info" "Configuring PAM for biometric authentication..."

    if ! grep -q "pam_fprintd.so" /etc/pam.d/sudo; then
        sudo sed -i '1i auth      sufficient  pam_fprintd.so' /etc/pam.d/sudo
        rx_log "success" "Sudo fingerprint auth enabled."
    else
        rx_log "info" "Sudo auth already configured."
    fi

    if ! grep -q "pam_fprintd.so" /etc/pam.d/system-local-login; then
        sudo sed -i '1i auth      sufficient  pam_fprintd.so' /etc/pam.d/system-local-login
        rx_log "success" "System login auth enabled."
    else
        rx_log "info" "System login already configured."
    fi
}

remove_pam_auth() {
    rx_log "info" "Deactivating biometric authentication..."

    if grep -q "pam_fprintd.so" /etc/pam.d/sudo; then
        sudo sed -i '/pam_fprintd.so/d' /etc/pam.d/sudo
        rx_log "success" "Sudo fingerprint auth removed."
    else
        rx_log "info" "Sudo auth was already clean."
    fi

    if grep -q "pam_fprintd.so" /etc/pam.d/system-local-login; then
        sudo sed -i '/pam_fprintd.so/d' /etc/pam.d/system-local-login
        rx_log "success" "System login auth removed."
    else
        rx_log "info" "System login auth was already clean."
    fi
}

cmd_fingerprint() {
    local action="${1,,}"
    local target_user="$USER"

    local has_fprintd=$(command -v fprintd-enroll)
    local dev_check=$(fprintd-list "$target_user" 2>&1)

    case "$action" in
        "setup" | "enroll")
            [[ -z $has_fprintd ]] && rx_log "error" "fprintd is not installed." && return 1

            sudo pkill -f fprintd

            rx_help_header "󰟀" "Choose a finger to enroll"
            local fingers=("left-thumb" "left-index-finger" "left-middle-finger" "left-ring-finger" "left-little-finger" "right-thumb" "right-index-finger" "right-middle-finger" "right-ring-finger" "right-little-finger")

            for i in "${!fingers[@]}"; do
                printf " ${PINK}%2d)${RESET} %s\n" $((i + 1)) "${fingers[$i]//-/ }"
            done

            echo -ne "\n ${PINK}󰄾 Select (1-10): ${RESET}"
            read -r choice
            local selected_finger="${fingers[$((choice - 1))]}"

            [[ -z $selected_finger ]] && rx_log "error" "Invalid selection." && return 1

            rx_log "info" "Starting enrollment for ${PINK}$selected_finger${RESET}..."
            rx_log "warn" "Place your finger on the sensor when it blinks."

            if sudo fprintd-enroll -f "$selected_finger" "$target_user"; then
                rx_log "success" "Fingerprint registered!"

                if ! grep -q "pam_fprintd.so" /etc/pam.d/sudo; then
                    rx_yesno "Enable biometric auth for sudo/login?" || return 0
                    setup_pam_auth
                fi
            else
                rx_log "error" "Enrollment failed."
            fi
            ;;

        "uninstall")
            rx_confirm "Disable biometric auth and wipe all hardware prints?" "N" || {
                rx_log "info" "Uninstall cancelled."
                return 0
            }

            remove_pam_auth

            rx_log "info" "Clearing hardware chip..."
            sudo pkill -f fprintd >/dev/null 2>&1
            sudo fprintd-delete "$target_user" >/dev/null 2>&1

            rx_log "success" "Retro fingerprint module has been fully uninstalled."
            ;;

        "list")
            local raw_data=$(sudo fprintd-list "$target_user" 2>&1)

            rx_table_header "󰟀" "Hardware Registry ($target_user)"

            if echo "$raw_data" | grep -qE "finger-|#"; then
                echo "$raw_data" | grep -E "finger-|#" | while read -r line; do
                    local clean_name=$(echo "$line" | sed -E 's/.*: //; s/finger-//g; s/-/ /g' | xargs)
                    rx_table_simple "󰄾" "${clean_name^} (VERIFIED)" "$SUCCESS"
                done
            elif echo "$raw_data" | grep -q "no devices"; then
                rx_log "error" "No fingerprint hardware detected."
            else
                rx_log "warn" "No fingerprints found in the chip."
            fi

            rx_table_separator
            rx_table_spacer
            ;;
        "status")
            local active_service=$(systemctl is-active fprintd)
            rx_table_header "󰟀" "Hardware Status"
            rx_table_row "󰍛" "Hardware:" "$([[ $dev_check == *"found"* ]] && echo "Detected" || echo "Not Found")" "$PINK" "14"
            rx_table_row "󰌪" "Service:" "$active_service" "$PINK" "14"
            rx_table_row "󱔗" "Auth Mode:" "$([[ -f /etc/pam.d/sudo && $(grep "pam_fprintd.so" /etc/pam.d/sudo) ]] && echo "Biometric + Pass" || echo "Pass Only")" "$PINK" "14"
            rx_table_separator
            rx_table_spacer
            ;;

        "clear")
            rx_log "warn" "Wiping biometric data for $target_user..."
            sudo pkill -f fprintd
            sudo fprintd-delete "$target_user" && rx_log "success" "Fingerprints have been cleared."
            ;;

        *)
            rx_help_usage "retro fingerprint <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "setup" "Enroll a new fingerprint"
            rx_help_cmd "list" "List enrolled fingerprints"
            rx_help_cmd "status" "Show hardware and auth status"
            rx_help_cmd "clear" "Wipe all biometric data"
            rx_help_cmd "uninstall" "Remove PAM auth and fingerprints"
            rx_help_examples
            rx_help_example "retro fingerprint setup" "Enroll a new fingerprint"
            rx_help_example "retro fingerprint status" "Check hardware and auth status"
            rx_help_example "retro fingerprint list" "Show enrolled fingerprints"
            rx_help_spacer
            ;;
    esac
}

has_fingerprint_hw=$(fprintd-list "$USER" 2>&1 | grep -q "found" && echo "yes" || echo "no")

if [[ $has_fingerprint_hw == "yes" ]]; then
    register_command "TOOLS" "fingerprint" "Biometric security management" "cmd_fingerprint"
fi
