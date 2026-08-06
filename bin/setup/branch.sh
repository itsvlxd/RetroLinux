#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_branch() {
    rx_load_state
    rx_clear_logo
    rx_step "Selecting release branch..."

    gum style --foreground 2 --padding "1 0 0 $PADDING_LEFT" "Rolling (develop)"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Latest development changes, updated continuously. Best for testing."
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "Recommended while Retro Linux is still in development."

    gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Stable (main)"
    gum style --foreground 7 --padding "0 0 0 $PADDING_LEFT" "Tested, stable releases only. Best for everyday use."
    gum style --foreground 7 --padding "0 0 1 $PADDING_LEFT" "Choose this once stable releases are available."

    local branch_options="Rolling (develop)
Stable (main)"
    local branch_choice
    branch_choice=$(echo "$branch_options" | gum choose --header "Select release branch" --height 5 --padding "$GUM_CHOOSE_PADDING") || {
        RETRO_BRANCH="${RETRO_BRANCH:-develop}"
        rx_save_state
        return 0
    }

    case "$branch_choice" in
        "Stable (main)") RETRO_BRANCH="main" ;;
        *) RETRO_BRANCH="develop" ;;
    esac

    rx_save_state
    return 0
}

if ! setup_branch; then
    rx_setup_fail "Branch"
fi
