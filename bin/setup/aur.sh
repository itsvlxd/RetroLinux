#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_aur() {
    rx_load_state
    rx_clear_logo
    rx_step "Let's configure your AUR helper..."

    if [[ -n $AUR_HELPER ]]; then
        gum style --foreground 7 "AUR helper already selected: ${PINK}$AUR_HELPER${RESET}"
        echo
        return 0
    fi

    if gum confirm --affirmative "yay" --negative "paru" "Select AUR helper" --padding "$GUM_CONFIRM_PADDING"; then
        AUR_HELPER="yay"
    else
        AUR_HELPER="paru"
    fi

    rx_save_state
    return 0
}

if ! setup_aur; then
    rx_setup_fail "AUR"
fi
