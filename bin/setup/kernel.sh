#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_kernel() {
    rx_load_state
    rx_step "Let's select your kernel..."

    local kernels='linux
linux-lts
linux-zen
linux-hardened'

    local current_kernel="linux"
    case "$KERNEL_SELECTION" in
        linux-lts) current_kernel="linux-lts" ;;
        linux-zen) current_kernel="linux-zen" ;;
        linux-hardened) current_kernel="linux-hardened" ;;
    esac

    local choice
    choice=$(echo "$kernels" | gum choose --height "$GUM_CHOOSE_HEIGHT" --selected "$current_kernel" --header "Select your kernel" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "3" "Kernel selection cancelled"
        rx_retry_or_exit "Kernel selection is required" || rx_abort
        return 1
    }

    # shellcheck disable=SC2034
    KERNEL_SELECTION="$choice"

    rx_save_state
    return 0
}

if ! setup_kernel; then
    rx_setup_fail "Kernel"
fi