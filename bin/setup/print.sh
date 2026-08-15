#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_print() {
    rx_load_state
    rx_step "Let's setup printing service..."

    if gum confirm --affirmative "Yes, enable printing" --negative "No, skip printing" "CUPS Print Service" --default="${PRINT_SERVICE_ENABLED:-true}" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        # shellcheck disable=SC2034
        PRINT_SERVICE_ENABLED="true"
    else
        # shellcheck disable=SC2034
        PRINT_SERVICE_ENABLED="false"
    fi

    rx_save_state
    return 0
}

if ! setup_print; then
    rx_setup_fail "Print"
fi

