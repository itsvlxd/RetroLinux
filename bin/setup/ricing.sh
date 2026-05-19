#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_ricing() {
    rx_load_state
    rx_clear_logo
    rx_step "Selecting ricing mode..."

    echo
    gum style --foreground 2 --padding "1 0 0 $PADDING_LEFT" "Stable Mode (Recommended)"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Uses pre-configured files managed via retro CLI and the settings app."
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "This is the most stable and recommended approach."
    echo
    gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Advanced Mode"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Rewrites all configuration files during installation."
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "Note: retro CLI and settings app ricing is more stable and recommended."
    echo

    if gum confirm --affirmative "Stable (recommended)" --negative "Advanced (rewrite configs)" "Ricing Mode" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
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
