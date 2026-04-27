#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_timezone() {
    rx_load_state
    rx_step "Let's setup your timezone..."

    local current_tz
    current_tz=$(rx_get_current_timezone)

    # shellcheck disable=SC2034
    USER_TIMEZONE=$(timedatectl list-timezones | gum filter --height "$GUM_FILTER_HEIGHT" "${GUM_FILTER_STYLE[@]}" --prompt "Timezone> " --placeholder "Please select your timezone" --padding "$GUM_FILTER_PADDING") || {
        rx_step_error "1" "Timezone selection failed"
        rx_retry_or_exit "Timezone is required" || rx_abort
        return 1
    }
    rx_save_state
    return 0
}

if ! setup_timezone; then
    rx_setup_fail "Timezone"
fi