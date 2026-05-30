#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_firewall() {
    rx_load_state
    rx_clear_logo
    rx_step "Select your firewall engine..."

    local engines=("nftables" "ufw" "firewalld" "iptables")
    local engine_choice
    engine_choice=$(gum choose --header "Firewall Engine" --padding "$GUM_CHOOSE_PADDING" "${engines[@]}")

    if [[ -z "$engine_choice" ]]; then
        gum style --foreground 3 --padding "1 0 1 $PADDING_LEFT" "No engine selected, defaulting to nftables"
        engine_choice="nftables"
    fi

    FIREWALL_ENGINE="$engine_choice"
    rx_save_state
    return 0
}

setup_firewall
