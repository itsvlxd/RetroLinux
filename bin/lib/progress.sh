#!/bin/bash

rx_step() {
    local message="$1"
    rx_clear_logo
    gum style --padding "1 0 1 $PADDING_LEFT" "$message"
    return 0
}

rx_step_error() {
    local step_num=$1
    local step_name=$2
    rx_clear_logo
    echo
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error in step $step_num: $step_name"
    echo
    return 0
}
