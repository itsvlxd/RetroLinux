#!/bin/bash

source "$RETRO_INSTALL/lib/display.sh"
source "$RETRO_INSTALL/lib/errors.sh"
source "$RETRO_INSTALL/lib/gum.sh"
source "$RETRO_INSTALL/lib/wifi.sh"
source "$RETRO_INSTALL/lib/qr.sh"
source "$RETRO_INSTALL/lib/locale.sh"
source "$RETRO_INSTALL/lib/timezone.sh"
source "$RETRO_INSTALL/lib/handlers.sh"
source "$RETRO_INSTALL/lib/output.sh"
source "$RETRO_INSTALL/lib/debug.sh"
source "$RETRO_INSTALL/lib/progress.sh"
source "$RETRO_INSTALL/lib/disk.sh"
source "$RETRO_INSTALL/lib/crypto.sh"

rx_set_retro_colors

rx_setup_fail() {
    local step_name="${1:-Setup}"
    rx_clear_logo
    echo
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "${step_name} failed"
    echo
    gum style "Would you like to retry or exit?"
    echo
    if gum confirm --negative "Exit" --affirmative "Retry" "${step_name}" --padding "$GUM_CONFIRM_PADDING"; then
        exec /opt/retrolinux/bin/retroinstall
    fi
    gum style "Run 'retroinstall' to try again"
    exit 1
}