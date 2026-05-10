#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_hostname() {
    rx_load_state
    rx_step "Let's setup your hostname..."

    while true; do
        local hostname
        hostname=$(gum input --placeholder "Please set the hostname for your computer" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --prompt "Hostname> " --value "retrolinux" --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Hostname input failed"
            rx_retry_or_exit "Hostname is required" || rx_abort
            return 1
        }

        if [[ $hostname =~ ^[A-Za-z_][A-Za-z0-9_-]*\$?$ ]]; then
            # shellcheck disable=SC2034
            USER_HOSTNAME="$hostname"
            break
        elif [[ -z "$hostname" ]]; then
            # shellcheck disable=SC2034
            USER_HOSTNAME="retrolinux"
            break
        else
            rx_notice "Letters, numbers, dashes/underscores only" 1
        fi
    done

    rx_save_state
    return 0
}

if ! setup_hostname; then
    rx_setup_fail "Hostname"
fi