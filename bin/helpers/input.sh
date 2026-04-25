#!/bin/bash

KEYBOARD=""

rx_keyboard_form() {
    rx_step "Let's setup your machine..."
    keyboards=$'Azerbaijani|azerty\nBelarusian|by\nBelgian|be-latin1\nBosnian|ba\nBulgarian|bg-cp1251\nCroatian|croat\nCzech|cz\nDanish|dk-latin1\nDutch|nl\nEnglish (UK)|uk\nEnglish (US)|us\nEnglish (US, Dvorak)|dvorak\nEstonian|et\nFinnish|fi\nFrench|fr\nFrench (Canada)|cf\nFrench (Switzerland)|fr_CH\nGeorgian|ge\nGerman|de\nGerman (Switzerland)|de_CH-latin1\nGreek|gr\nHebrew|il\nHungarian|hu\nIcelandic|is-latin1\nIrish|ie\nItalian|it\nJapanese|jp106\nKazakh|kazakh\nKhmer (Cambodia)|khmer\nKyrgyz|kyrgyz\nLao|la-latin1\nLatvian|lv\nLithuanian|lt\nMacedonian|mk-utf\nNorwegian|no-latin1\nPolish|pl\nPortuguese|pt-latin1\nPortuguese (Brazil)|br-abnt2\nRomanian|ro\nRussian|ru\nSerbian|sr-latin\nSlovak|sk-qwertz\nSlovenian|slovene\nSpanish|es\nSpanish (Latin American)|la-latin1\nSwedish|sv-latin1\nTajik|tj_alt-UTF8\nTurkish|trq\nUkrainian|ua'
    local choice
    choice=$(printf '%s\n' "$keyboards" | cut -d'|' -f1 | gum choose --height 10 --selected "English (US)" --header "Keyboard layout" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "1" "Keyboard selection cancelled"
        rx_retry_or_exit "Keyboard selection is required" || rx_abort
        rx_keyboard_form
        return
    }
    KEYBOARD=$(printf '%s\n' "$keyboards" | awk -F'|' -v c="$choice" '$1==c{print $2; exit}')

    if [[ $(tty 2>/dev/null) == "/dev/tty"* ]]; then
        loadkeys "$KEYBOARD" 2>/dev/null || true
    fi
}

USER_PASSWORD_HASH=""
USER_PASSWORD=""
USER_NAME=""
USER_HOSTNAME=""
USER_TIMEZONE=""

rx_user_form() {
    rx_step "Let's setup your user account..."

    while true; do
        local username
        username=$(gum input --placeholder "Pick a username" --prompt.foreground="#ff79c6" --prompt "Username> " --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Username input failed"
            rx_retry_or_exit "Username is required" || rx_abort
        }

        if [[ $username =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
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
        }
        local password_confirmation
        password_confirmation=$(gum input --placeholder "Confirm your password" --prompt.foreground="#ff79c6" --password --prompt "Confirm> " --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Password confirmation failed"
            rx_retry_or_exit "Password confirmation is required" || rx_abort
        }

        if [[ -n $password && $password == "$password_confirmation" ]]; then
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
        return
    }

    while true; do
        local hostname
        hostname=$(gum input --placeholder "retrolinux" --prompt.foreground="#ff79c6" --prompt "Hostname> " --padding "$GUM_INPUT_PADDING") || {
            rx_step_error "2" "Hostname input failed"
            rx_retry_or_exit "Hostname is required" || rx_abort
            continue
        }

        if [[ $hostname =~ ^[A-Za-z_][A-Za-z0-9_-]*\$?$ ]]; then
            USER_HOSTNAME="$hostname"
            break
        elif [[ -z $hostname ]]; then
            USER_HOSTNAME="retrolinux"
            break
        else
            rx_notice "Letters, numbers, dashes/underscores only" 1
        fi
    done

    USER_TIMEZONE=$(timedatectl list-timezones 2>/dev/null | gum filter --height 10 --header "Timezone" --padding "$GUM_FILTER_PADDING") || {
        rx_step_error "2" "Timezone selection failed"
        rx_retry_or_exit "Timezone is required" || rx_abort
        return
    }
}

rx_review_user_config() {
    while true; do
        rx_clear_logo
        gum style --foreground 5 --padding "1 0 1 $PADDING_LEFT" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        gum style --foreground 7 "Username   $USER_NAME"
        gum style --foreground 7 "Password   $(printf "%${#USER_PASSWORD}s" | tr ' ' '•')"
        gum style --foreground 7 "Hostname   $USER_HOSTNAME"
        gum style --foreground 7 "Timezone   $USER_TIMEZONE"
        gum style --foreground 7 "Keyboard   $KEYBOARD"
        gum style --foreground 5 --padding "0 0 1 $PADDING_LEFT" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if gum confirm --negative "No, change it" --affirmative "Yes, looks good" "Does this look right?" --padding "$GUM_CONFIRM_PADDING"; then
            break
        else
            rx_keyboard_form
            rx_user_form
        fi
    done
}