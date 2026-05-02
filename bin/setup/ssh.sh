#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

# TODO: add rx_clear logo after every step and the step including to fix the white space also display
# ssh in the summary panel at the end

setup_ssh() {
    rx_load_state

    rx_step "Let's setup SSH access..."

    echo
    if ! gum confirm --affirmative "Yes, enable SSH" --negative "No, skip SSH" "SSH Service" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        SSH_ENABLED="false"
        rx_save_state
        return 0
    fi

    SSH_ENABLED="true"

    local ssh_port
    ssh_port=$(gum input --placeholder "SSH port (default: 22)" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --prompt "Port> " --value "22" --padding "$GUM_INPUT_PADDING") || {
        rx_step_error "2" "SSH port input failed"
        rx_retry_or_exit "SSH port is required" || rx_abort
        return 1
    }

    if [[ -z $ssh_port ]]; then
        ssh_port="22"
    fi

    if ! [[ $ssh_port =~ ^[0-9]+$ ]] || [[ $ssh_port -lt 1 ]] || [[ $ssh_port -gt 65535 ]]; then
        rx_notice "Invalid port number, using default 22" 1
        ssh_port="22"
    fi

    SSH_PORT="$ssh_port"

    echo
    if gum confirm --affirmative "Yes, enable password login" --negative "No, disable password" "Password Authentication" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        SSH_PASSWORD_LOGIN="true"
    else
        SSH_PASSWORD_LOGIN="false"
    fi

    echo
    if gum confirm --affirmative "Yes, enable SSH keys" --negative "No, disable keys" "Public Key Authentication" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        SSH_KEY_LOGIN="true"
    else
        SSH_KEY_LOGIN="false"
    fi

    echo
    if gum confirm --affirmative "Yes, allow root login" --negative "No, disable root" "Root Login" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        SSH_ROOT_LOGIN="true"
    else
        SSH_ROOT_LOGIN="false"
    fi

    rx_save_state
    return 0
}

if ! setup_ssh; then
    rx_setup_fail "SSH"
fi
