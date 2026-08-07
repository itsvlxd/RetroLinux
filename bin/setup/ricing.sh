#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_ricing() {
    rx_load_state
    rx_clear_logo
    rx_step "Selecting ricing mode..."

    gum style --foreground 2 --padding "1 0 0 $PADDING_LEFT" "Managed Mode (Recommended)"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Installs configurations as symlinks to the RetroLinux repository."
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Rice your system using retro CLI variables and the settings app."
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "Note: Updates will propagate to symlinked configs."

    gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Manual Mode"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Copies configuration files directly to your system."
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Edit configs freely — updates will never overwrite your changes."
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "Note: You manage your own customizations after installation."

    if gum confirm --affirmative "Managed (recommended)" --negative "Manual (copy configs)" "Ricing Mode" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        RICE_MODE="stable"
    else
        RICE_MODE="advanced"
    fi

    rx_save_state
    return 0
}

if ! setup_ricing; then
    rx_setup_fail "Ricing"
fi
