#!/bin/bash

rx_debug() {
    if [[ "${RX_DEBUG:-}" == "1" ]]; then
        local level="${1:-INFO}"
        local message="${2:-}"
        gum style --foreground 7 "[${level}] ${message}"
    fi
}
