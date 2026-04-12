#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

source "$RETRO_DIR/cmds/tools/fingerprint.sh"

rx_setup_fingerprint() {
    local hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "Arch-Machine")

    if ! command -v fprintd-list &>/dev/null; then
        return 0
    fi

    sudo systemctl start fprintd &>/dev/null

    local dev_check=$(sudo fprintd-list "$USER" 2>&1)

    if [[ $dev_check != *"found"* ]]; then
        rx_log "info" "No fingerprint hardware detected on this machine."
        return 0
    fi

    local has_pam=false
    [[ -f /etc/pam.d/sudo ]] && grep -q "pam_fprintd.so" /etc/pam.d/sudo && has_pam=true

    local has_fingers=false
    [[ $dev_check == *"finger-"* || $dev_check == *"#0:"* ]] && has_fingers=true

    if [[ $has_pam == "true" && $has_fingers == "true" ]]; then
        return 0
    fi

    rx_log "info" "I noticed a fingerprint sensor on your ${PINK}${hostname}${RESET}."

    #if [[ $has_fingers == "false" ]]; then
    #    rx_log "warn" "Hardware is active but no fingerprints are registered!"
    #fi

    rx_log "info" "Would you like to configure biometric authentication? ${PINK}[y/N]${RESET}: "
    read -r allow

    if [[ ! $allow =~ ^[Yy]$ ]]; then
        rx_log "info" "Fingerprint setup skipped."
        return 0
    fi

    cmd_fingerprint "setup"
}
