#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_install() {
    rx_load_state
    rx_clear_logo
    rx_step "Selecting installation type..."

    if [[ -n $INSTALL_TYPE ]]; then
        if [[ $INSTALL_TYPE == "minimal" ]]; then
            gum style --foreground 2 "Minimal installation (core modules only)"
        else
            gum style --foreground 2 "Complete installation (all modules)"
        fi
        return 0
    fi

    if gum confirm --affirmative "Complete install" --negative "Minimal install" "Select Installation Type" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        INSTALL_TYPE="complete"
    else
        INSTALL_TYPE="minimal"
    fi

    rx_save_state
    return 0
}

if ! setup_install; then
    rx_setup_fail "Install"
fi