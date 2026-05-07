#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_setup_browser() {
    rx_step "Selecting browser..."

    local options=("zen-browser-bin" "chromium" "firefox" "floorp" "thorium" "nyxt")
    local browser=$(gum choose --header "Select browser to install:" --padding "$GUM_CHOOSE_PADDING" "${options[@]}")

    if [[ -z "$browser" ]]; then
        gum style --foreground 3 "No browser selected, skipping"
        return 0
    fi

    BROWSER_CHOICE="$browser"

    gum style --foreground 5 "Browser selected: ${PINK}$browser${RESET}"
    echo
    rx_save_state
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rx_setup_browser "$@"
fi