#!/bin/bash

setup_timezone() {
    rx_load_state
    rx_step "Let's setup your timezone..."

    local current_tz
    current_tz=$(rx_get_current_timezone)

    # shellcheck disable=SC2034
    USER_TIMEZONE=$(timedatectl list-timezones 2>/dev/null | gum filter --height "$GUM_FILTER_HEIGHT" --header "Timezone" --selected "$current_tz" --padding "$GUM_FILTER_PADDING") || {
        rx_step_error "1" "Timezone selection failed"
        rx_retry_or_exit "Timezone is required" || rx_abort
        return 1
    }
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

setup_timezone