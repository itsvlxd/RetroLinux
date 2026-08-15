#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_keyboard() {
    rx_load_state
    rx_step "Let's setup your machine..."

    local keyboards='Azerbaijani
Belarusian
Belgian
Bosnian
Bulgarian
Croatian
Czech
Danish
Dutch
English (UK)
English (US)
English (US, Dvorak)
Estonian
Finnish
French
French (Canada)
French (Switzerland)
Georgian
German
German (Switzerland)
Greek
Hebrew
Hungarian
Icelandic
Irish
Italian
Japanese
Kazakh
Khmer
Kyrgyz
Lao
Latvian
Lithuanian
Macedonian
Norwegian
Polish
Portuguese
Portuguese (Brazil)
Romanian
Russian
Serbian
Slovak
Slovenian
Spanish
Spanish (Latin American)
Swedish
Tajik
Turkish
Ukrainian'

    local choice
    choice=$(printf '%s\n' "$keyboards" | gum filter --height "$GUM_FILTER_HEIGHT" "${GUM_FILTER_STYLE[@]}" --value "$(rx_keyboard_display_name "$KEYBOARD")" --prompt "Keyboard> " --placeholder "Please select your keyboard layout" --padding "$GUM_FILTER_PADDING") || {
        rx_step_error "1" "Keyboard selection cancelled"
        rx_retry_or_exit "Keyboard selection is required" || rx_abort
        return 1
    }

    case "$choice" in
        "English (US)") KEYBOARD="us" ;;
        "English (UK)") KEYBOARD="uk" ;;
        "English (US, Dvorak)") KEYBOARD="dvorak" ;;
        "Azerbaijani") KEYBOARD="azerty" ;;
        "Belarusian") KEYBOARD="by" ;;
        "Belgian") KEYBOARD="be-latin1" ;;
        "Bosnian") KEYBOARD="ba" ;;
        "Bulgarian") KEYBOARD="bg-cp1251" ;;
        "Croatian") KEYBOARD="croat" ;;
        "Czech") KEYBOARD="cz" ;;
        "Danish") KEYBOARD="dk-latin1" ;;
        "Dutch") KEYBOARD="nl" ;;
        "Estonian") KEYBOARD="et" ;;
        "Finnish") KEYBOARD="fi" ;;
        "French") KEYBOARD="fr" ;;
        "French (Canada)") KEYBOARD="cf" ;;
        "French (Switzerland)") KEYBOARD="fr_CH" ;;
        "Georgian") KEYBOARD="ge" ;;
        "German") KEYBOARD="de" ;;
        "German (Switzerland)") KEYBOARD="de_CH-latin1" ;;
        "Greek") KEYBOARD="gr" ;;
        "Hebrew") KEYBOARD="il" ;;
        "Hungarian") KEYBOARD="hu" ;;
        "Icelandic") KEYBOARD="is-latin1" ;;
        "Irish") KEYBOARD="ie" ;;
        "Italian") KEYBOARD="it" ;;
        "Japanese") KEYBOARD="jp106" ;;
        "Kazakh") KEYBOARD="kazakh" ;;
        "Khmer") KEYBOARD="khmer" ;;
        "Kyrgyz") KEYBOARD="kyrgyz" ;;
        "Lao") KEYBOARD="la-latin1" ;;
        "Latvian") KEYBOARD="lv" ;;
        "Lithuanian") KEYBOARD="lt" ;;
        "Macedonian") KEYBOARD="mk-utf" ;;
        "Norwegian") KEYBOARD="no-latin1" ;;
        "Polish") KEYBOARD="pl" ;;
        "Portuguese") KEYBOARD="pt-latin1" ;;
        "Portuguese (Brazil)") KEYBOARD="br-abnt2" ;;
        "Romanian") KEYBOARD="ro" ;;
        "Russian") KEYBOARD="ru" ;;
        "Serbian") KEYBOARD="sr-latin" ;;
        "Slovak") KEYBOARD="sk-qwertz" ;;
        "Slovenian") KEYBOARD="slovene" ;;
        "Spanish") KEYBOARD="es" ;;
        "Spanish (Latin American)") KEYBOARD="la-latin1" ;;
        "Swedish") KEYBOARD="sv-latin1" ;;
        "Tajik") KEYBOARD="tj_alt-UTF8" ;;
        "Turkish") KEYBOARD="trq" ;;
        "Ukrainian") KEYBOARD="ua" ;;
        *) KEYBOARD="us" ;;
    esac

    rx_set_keyboard_layout "$KEYBOARD"
    rx_save_state
    return 0
}

if ! setup_keyboard; then
    rx_setup_fail "Keyboard"
fi