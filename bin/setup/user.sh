#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_user() {
    rx_load_state
    rx_step "Let's setup your user account..."

    while true; do
        local username
        username=$(gum input --placeholder "Pick a username" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --prompt "Username> " --value "$USER_NAME" --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Username input failed"
            rx_retry_or_exit "Username is required" || rx_abort
            return 1
        }

        if [[ $username =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
            # shellcheck disable=SC2034
            USER_NAME="$username"
            break
        else
            rx_notice "Letters, numbers, underscores only" 1
        fi
    done

    while true; do
        local password
        password=$(gum input --placeholder "Create a password" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --password --prompt "Password> " --value "$USER_PASSWORD" --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Password input failed"
            rx_retry_or_exit "Password is required" || rx_abort
            return 1
        }
        local password_confirmation
        password_confirmation=$(gum input --placeholder "Confirm your password" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --password --prompt "Confirm> " --value "$USER_PASSWORD" --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Password confirmation failed"
            rx_retry_or_exit "Password confirmation is required" || rx_abort
            return 1
        }

        if [[ -n $password && $password == "$password_confirmation" ]]; then
            # shellcheck disable=SC2034
            USER_PASSWORD="$password"
            break
        elif [[ -z $password ]]; then
            rx_notice "Password cannot be empty" 1
        else
            rx_notice "Passwords do not match" 1
        fi
    done

    if gum confirm --affirmative "Yes, enable sudo" --negative "No, skip sudo" "User sudo access" --default="${USER_SUDO:-true}" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        # shellcheck disable=SC2034
        USER_SUDO="true"
    else
        # shellcheck disable=SC2034
        USER_SUDO="false"
    fi

    rx_save_state
    return 0
}

if ! setup_user; then
    rx_setup_fail "User"
fi

