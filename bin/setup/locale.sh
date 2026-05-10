#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_locale() {
    rx_load_state
    rx_step "Let's setup your system language..."

    local lang_list=""
    for code in "${!LOCALE_LANG_NAMES[@]}"; do
        lang_list="$lang_list${LOCALE_LANG_NAMES[$code]}"$'\n'
    done
    lang_list=$(echo "$lang_list" | sort | uniq)

    local choice
    choice=$(echo "$lang_list" | gum filter --height "$GUM_FILTER_HEIGHT" "${GUM_FILTER_STYLE[@]}" --prompt "Language> " --placeholder "Please select your system language" --padding "$GUM_FILTER_PADDING") || {
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
    return 0
}

if ! setup_locale; then
    rx_setup_fail "Language"
fi