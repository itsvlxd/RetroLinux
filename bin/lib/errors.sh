#!/bin/bash

rx_retry_or_exit() {
    local message="${1:-Something went wrong.}"
    rx_clear_logo
    echo
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "$message"
    echo
    if gum confirm --negative "Exit" --affirmative "Retry" "Retry?" --padding "$GUM_CONFIRM_PADDING"; then
        return 0
    fi
    return 1
}

rx_step_error() {
    local step_num=$1
    local step_name=$2
    rx_clear_logo
    echo
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error in step $step_num: $step_name"
    echo
}

rx_abort() {
    rx_clear_logo
    echo
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "${1:-Installation aborted}"
    echo
    gum style "Run 'retroinstall' to try again"
    echo
    exit 1
}