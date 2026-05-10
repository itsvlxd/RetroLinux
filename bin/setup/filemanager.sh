#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_filemanager() {
    rx_load_state
    rx_clear_logo
    rx_step "Let's select your default file manager..."
    
    if [[ -n $FILEMANAGER_CHOICE ]]; then
        gum style --foreground 7 "File manager already selected: ${PINK}$FILEMANAGER_CHOICE${RESET}"
        echo
        return 0
    fi
    
    local fm_options="thunar
nemo
nautilus
yazi"
    
    FILEMANAGER_CHOICE=$(echo "$fm_options" | gum choose --height 4 --header "Select default file manager" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "2" "File manager selection failed"
        FILEMANAGER_CHOICE="thunar"
        rx_save_state
        return 0
    }
    
    rx_save_state
    return 0
}

if ! setup_filemanager; then
    rx_setup_fail "File Manager"
fi
