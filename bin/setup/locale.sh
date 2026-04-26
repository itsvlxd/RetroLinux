#!/bin/bash

setup_locale() {
    rx_load_state
    rx_step "Let's setup your system language..."

    local current_display="English"
    if [[ -n "$SYS_LANG" && "$SYS_LANG" != "en_US.UTF-8" ]]; then
        current_display=$(rx_locale_to_lang_name "$SYS_LANG")
    fi

    local lang_list=""
    for code in "${!LOCALE_LANG_NAMES[@]}"; do
        lang_list="$lang_list${LOCALE_LANG_NAMES[$code]}"$'\n'
    done
    lang_list=$(echo "$lang_list" | sort | uniq)

    local choice
    choice=$(echo "$lang_list" | gum choose --height "$GUM_CHOOSE_HEIGHT" --selected "$current_display" --header "Select system language" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "1" "Language selection cancelled"
        rx_retry_or_exit "Language selection is required" || rx_abort
        return 1
    }

    local lang_code
    for code in "${!LOCALE_LANG_NAMES[@]}"; do
        if [[ "${LOCALE_LANG_NAMES[$code]}" == "$choice" ]]; then
            lang_code="$code"
            break
        fi
    done

    if [[ -z $lang_code ]]; then
        lang_code=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
    fi

    SYS_LANG="${lang_code}.UTF-8"
    rx_save_state
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

setup_locale