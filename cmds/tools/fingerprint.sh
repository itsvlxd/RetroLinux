#!/bin/bash

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
    local action="$1"
    local target_user="$USER"

    local has_fprintd=$(command -v fprintd-enroll)
    local dev_check=$(fprintd-list "$target_user" 2>&1)

    case "$action" in
        "setup" | "enroll")
            [[ -z $has_fprintd ]] && rx_log "error" "fprintd is not installed." && return 1

            sudo pkill -f fprintd

            echo -e "\n ${PINK}󰟀 Choose a finger to enroll:${RESET}"
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
                    rx_log "info" "Enable biometric auth for sudo/login? ${PINK}[y/N]${RESET}: "
                    read -r auth_choice
                    [[ $auth_choice =~ ^[Yy]$ ]] && setup_pam_auth
                fi
            else
                rx_log "error" "Enrollment failed."
            fi
            ;;

        "uninstall")
            rx_log "info" "Disable biometric auth and wipe all hardware prints? ${PINK}[y/N]${RESET}: "
            read -r confirm
            [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Uninstall cancelled." && return 0

            remove_pam_auth

            rx_log "info" "Clearing hardware chip..."
            sudo pkill -f fprintd >/dev/null 2>&1
            sudo fprintd-delete "$target_user" >/dev/null 2>&1

            rx_log "success" "Retro fingerprint module has been fully uninstalled."
            ;;

        "list")
            local raw_data=$(sudo fprintd-list "$target_user" 2>&1)

            echo -e "\n ${PINK}󰟀 Hardware Registry ($target_user)${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            if echo "$raw_data" | grep -qE "finger-|#"; then
                echo "$raw_data" | grep -E "finger-|#" | while read -r line; do
                    local clean_name=$(echo "$line" | sed -E 's/.*: //; s/finger-//g; s/-/ /g' | xargs)

                    printf " ${PINK}󰄾${RESET} %-20s ${SUCCESS}(VERIFIED)${RESET}\n" "${clean_name^}"
                done
            elif echo "$raw_data" | grep -q "no devices"; then
                rx_log "error" "No fingerprint hardware detected."
            else
                rx_log "warn" "No fingerprints found in the chip."
            fi

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;
        "status")
            local active_service=$(systemctl is-active fprintd)
            echo -e "\n ${PINK}󰟀 Hardware Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            printf " ${PINK}󰍛${RESET} %-14s %s\n" "Hardware:" "$([[ $dev_check == *"found"* ]] && echo "Detected" || echo "Not Found")"
            printf " ${PINK}󰌪${RESET} %-14s %s\n" "Service:" "$active_service"
            printf " ${PINK}󱔗${RESET} %-14s %s\n" "Auth Mode:" "$([[ -f /etc/pam.d/sudo && $(grep "pam_fprintd.so" /etc/pam.d/sudo) ]] && echo "Biometric + Pass" || echo "Pass Only")"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "clear")
            rx_log "warn" "Wiping biometric data for $target_user..."
            sudo pkill -f fprintd
            sudo fprintd-delete "$target_user" && rx_log "success" "Fingerprints have been cleared."
            ;;

        *)
            rx_log "info" "Usage: retro fingerprint <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "setup" "Enroll a new fingerprint"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List enrolled fingerprints"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show hardware and auth status"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "clear" "Wipe all biometric data"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "uninstall" "Remove PAM auth and fingerprints"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "fingerprint" "Biometric security management" "cmd_fingerprint"
