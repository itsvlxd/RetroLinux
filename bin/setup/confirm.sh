#!/bin/bash

setup_confirm() {
    rx_load_state

    if [[ $RX_DEBUG == 1 ]]; then
        gum style --foreground 3 --padding "1 0 1 $PADDING_LEFT" "[DEBUG] DISK_SELECTED='$DISK_SELECTED'"
        sleep 2
    fi

    rx_clear_logo
    echo
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Warning: This will erase ALL data on $DISK_SELECTED"
    gum style --padding "0 0 0 $PADDING_LEFT" "There is no going back from this point."
    echo

    if gum confirm --affirmative "Yes, wipe disk" --negative "No, go back" "Confirm disk wipe" --padding "$GUM_CONFIRM_PADDING" --selected.background 5 --selected.foreground 7 --unselected.background 240 --unselected.foreground 7; then
        return 0
    else
        return 1
    fi
}

if [[ ${RETRO_SETUP_SOURCED:-} != "1" ]]; then
    export RETRO_SETUP_SOURCED=1
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
    rx_set_retro_colors
fi

setup_confirm

