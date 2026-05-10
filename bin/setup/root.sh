#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_root() {
    rx_load_state
    rx_step "Let's setup the root password..."

    local use_same_password="false"

    if [[ -n $USER_PASSWORD ]]; then
        if gum confirm --affirmative "Yes, use same password" --negative "No, enter different password" "Would you like to configure root with the same password used for ${USER_NAME}?" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
            ROOT_PASSWORD="$USER_PASSWORD"
            use_same_password="true"
            rx_save_state
            return 0
        fi
    fi

    if [[ $use_same_password != "true" ]]; then
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
                ROOT_PASSWORD="$password"
                break
            elif [[ -z $password ]]; then
                rx_notice "Password cannot be empty" 1
            else
                rx_notice "Passwords do not match" 1
            fi
        done
    fi

    rx_save_state
    return 0
}

if ! setup_root; then
    rx_setup_fail "Root"
fi

