#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_fingerprint() {
    rx_load_state
    rx_clear_logo
    rx_step "Configuring fingerprint authentication..."

    if [[ -n $FINGERPRINT_ENABLED ]]; then
        if [[ $FINGERPRINT_ENABLED == "true" ]]; then
            gum style --foreground 2 "Fingerprint authentication already enabled"
        else
            gum style --foreground 7 "Fingerprint authentication already disabled"
        fi
        return 0
    fi

    if gum confirm --affirmative "Yes, enable fingerprint" --negative "No, skip fingerprint" "Fingerprint Authentication" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        FINGERPRINT_ENABLED="true"
    else
        FINGERPRINT_ENABLED="false"
    fi

    rx_save_state
    return 0
}

if ! setup_fingerprint; then
    rx_setup_fail "Fingerprint"
fi

