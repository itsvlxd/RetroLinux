#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_branch() {
    rx_load_state
    rx_clear_logo
    rx_step "Selecting release branch..."

    gum style --foreground 2 --padding "1 0 0 $PADDING_LEFT" "Stable (main)"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Tested, stable releases only. Best for everyday use."
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "Choose this once stable releases are available."

    gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Rolling (develop)"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Latest development changes, updated continuously. Best for testing."
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "Recommended while Retro Linux is still in development."

    if gum confirm --affirmative "Stable (main)" --negative "Rolling (develop)" "Select release branch" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        RETRO_BRANCH="main"
    else
        RETRO_BRANCH="develop"
    fi

    rx_save_state
    return 0
}

if ! setup_branch; then
    rx_setup_fail "Branch"
fi
