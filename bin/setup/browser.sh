#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_setup_browser() {
    rx_step "Selecting browser..."

    local display_options=("Firefox" "Zen" "Chromium" "None (skip browser)")
    local pkg_options=("firefox" "zen-browser-bin" "chromium" "none")
    local selection=$(gum choose --header "Select browser to install:" --padding "$GUM_CHOOSE_PADDING" "${display_options[@]}")

    if [[ -z "$selection" ]]; then
        gum style --foreground 3 "No browser selected, skipping"
        BROWSER_CHOICE="none"
        rx_save_state
        return 0
    fi

    BROWSER_CHOICE=""
    for i in "${!display_options[@]}"; do
        if [[ ${display_options[$i]} == "$selection" ]]; then
            BROWSER_CHOICE="${pkg_options[$i]}"
            break
        fi
    done

    if [[ -z $BROWSER_CHOICE ]]; then
        gum style --foreground 3 "No browser selected, skipping"
        BROWSER_CHOICE="none"
        rx_save_state
        return 0
    fi

    if [[ $BROWSER_CHOICE == "none" ]]; then
        gum style --foreground 3 "No browser will be installed."
    else
        gum style --foreground 5 "Browser selected: ${PINK}$selection${RESET}"
    fi
    echo
    rx_save_state
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rx_setup_browser "$@"
fi