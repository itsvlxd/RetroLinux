#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_install() {
    rx_load_state
    rx_clear_logo
    rx_step "Selecting installation type..."

    gum style --foreground 2 --padding "1 0 0 $PADDING_LEFT" "Complete Install"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Installs all available modules: desktop tools, utilities, themes,"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "wallpapers, and full system integration. Best for new setups."

    gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Minimal Install"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Installs only core system modules: essential services, package"
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "management, and basic desktop functionality. Lightweight setup."

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