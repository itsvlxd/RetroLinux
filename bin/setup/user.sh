#!/bin/bash

setup_user() {
    rx_load_state
    rx_step "Let's setup your user account..."

    while true; do
        local username
        username=$(gum input --placeholder "Pick a username" --prompt.foreground="#ff79c6" --prompt "Username> " --padding "$GUM_INPUT_PADDING") || {
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
        password=$(gum input --placeholder "Create a password" --prompt.foreground="#ff79c6" --password --prompt "Password> " --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Password input failed"
            rx_retry_or_exit "Password is required" || rx_abort
            return 1
        }
        local password_confirmation
        password_confirmation=$(gum input --placeholder "Confirm your password" --prompt.foreground="#ff79c6" --password --prompt "Confirm> " --padding "$GUM_INPUT_PADDING") || {
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

    # shellcheck disable=SC2034
    USER_PASSWORD_HASH=$(printf '%s' "$password" | openssl passwd -6 -stdin) || {
        rx_step_error "2" "Password hash generation failed"
        rx_retry_or_exit "Cannot proceed without password hash" || rx_abort
        return 1
    }

    while true; do
        local hostname
        hostname=$(gum input --placeholder "retrolinux" --prompt.foreground="#ff79c6" --prompt "Hostname> " --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Hostname input failed"
            rx_retry_or_exit "Hostname is required" || rx_abort
            return 1
        }

        if [[ $hostname =~ ^[A-Za-z_][A-Za-z0-9_-]*\$?$ ]]; then
            # shellcheck disable=SC2034
            USER_HOSTNAME="$hostname"
            break
        elif [[ -z $hostname ]]; then
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

if [[ "${RETRO_SETUP_SOURCED:-}" != "1" ]]; then
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

setup_user