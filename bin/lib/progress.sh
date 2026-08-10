#!/bin/bash

rx_step() {
    local message="$1"
    rx_clear_logo
    gum style --padding "1 0 1 $PADDING_LEFT" "$message"
    return 0
}
