#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_root() {
    rx_load_state
    rx_step "Let's setup the root password..."

    while true; do
        local password
        password=$(gum input --placeholder "Create a root password" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --password --prompt "Password> " --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Root password input failed"
            rx_retry_or_exit "Root password is required" || rx_abort
            return 1
        }
        local password_confirmation
        password_confirmation=$(gum input --placeholder "Confirm root password" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --password --prompt "Confirm> " --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Root password confirmation failed"
            rx_retry_or_exit "Password confirmation is required" || rx_abort
            return 1
        }

        if [[ -n $password && $password == "$password_confirmation" ]]; then
            # shellcheck disable=SC2034
            ROOT_PASSWORD="$password"
            break
        elif [[ -z $password ]]; then
            rx_notice "Password cannot be empty" 1
        else
            rx_notice "Passwords do not match" 1
        fi
    done

    # shellcheck disable=SC2034
    ROOT_PASSWORD_HASH=$(printf '%s' "$password" | openssl passwd -6 -stdin) || {
        rx_step_error "2" "Password hash generation failed"
        rx_retry_or_exit "Cannot proceed without password hash" || rx_abort
        return 1
    }

    rx_save_state
    return 0
}

if ! setup_root; then
    rx_setup_fail "Root"
fi