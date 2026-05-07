#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_editor() {
    rx_load_state
    rx_clear_logo
    rx_step "Let's select your default text editor..."

    if [[ -n $EDITOR_CHOICE ]]; then
        gum style --foreground 7 "Editor already selected: ${PINK}$EDITOR_CHOICE${RESET}"
        echo
        return 0
    fi

    local editor_options="nvim
vim
vi
nano"

    EDITOR_CHOICE=$(echo "$editor_options" | gum choose --height 4 --header "Select default editor" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "2" "Editor selection failed"
        EDITOR_CHOICE="nano"
        rx_save_state
        return 0
    }

    rx_save_state
    return 0
}

if ! setup_editor; then
    rx_setup_fail "Editor"
fi
