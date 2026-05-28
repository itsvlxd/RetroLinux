#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_firewall() {
    rx_load_state
    rx_clear_logo
    rx_step "Select your firewall engine..."

    local engines=("nftables" "ufw" "firewalld" "iptables")
    local engine_choice
    engine_choice=$(gum choose --header "Firewall Engine" --cursor.foreground "#ff79c6" --selected.foreground "#ff79c6" --unselected.foreground "#6272a4" "${engines[@]}") || {
        rx_step_error "Firewall engine selection failed"
        rx_retry_or_exit "Firewall engine is required" || rx_abort
        return 1
    }

    FIREWALL_ENGINE="$engine_choice"
    rx_save_state
    return 0
}

if ! setup_firewall; then
    rx_setup_fail "Firewall"
fi
