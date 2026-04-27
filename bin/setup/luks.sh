#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_luks() {
    rx_load_state
    rx_step "Let's setup disk encryption..."

    if gum confirm --affirmative "Yes, enable encryption" --negative "No, skip encryption" "LUKS Encryption" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        # shellcheck disable=SC2034
        LUKS_ENABLED="true"

        while true; do
            local password
            password=$(gum input --placeholder "Create a LUKS encryption password" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --password --prompt "LUKS Password> " --padding "$GUM_INPUT_PADDING") || {
                rx_step_error "2" "LUKS password input failed"
                rx_retry_or_exit "LUKS password is required" || rx_abort
                return 1
            }
            local password_confirmation
            password_confirmation=$(gum input --placeholder "Confirm LUKS password" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --password --prompt "Confirm> " --padding "$GUM_INPUT_PADDING") || {
                rx_step_error "2" "LUKS password confirmation failed"
                rx_retry_or_exit "Password confirmation is required" || rx_abort
                return 1
            }

            if [[ -n $password && $password == "$password_confirmation" ]]; then
                # shellcheck disable=SC2034
                LUKS_PASSWORD="$password"
                break
            elif [[ -z $password ]]; then
                rx_notice "Password cannot be empty" 1
            else
                rx_notice "Passwords do not match" 1
            fi
        done

        echo
        gum style --padding "0 0 0 $PADDING_LEFT" "Select LUKS key derivation iteration time:"
        gum style --padding "0 0 0 $PADDING_LEFT" "Higher values = more security but slower boot"
        echo

        local iter_time_options='1000 ms (fastest)
2000 ms
3000 ms
4000 ms
5000 ms (balanced)
7500 ms
10000 ms
15000 ms
30000 ms
60000 ms (most secure)'

        local current_iter="5000 ms (balanced)"
        case "$LUKS_ITER_TIME" in
            1000) current_iter="1000 ms (fastest)" ;;
            2000) current_iter="2000 ms" ;;
            3000) current_iter="3000 ms" ;;
            4000) current_iter="4000 ms" ;;
            5000) current_iter="5000 ms (balanced)" ;;
            7500) current_iter="7500 ms" ;;
            10000) current_iter="10000 ms" ;;
            15000) current_iter="15000 ms" ;;
            30000) current_iter="30000 ms" ;;
            60000) current_iter="60000 ms (most secure)" ;;
        esac

        local iter_choice
        iter_choice=$(echo "$iter_time_options" | gum filter --height "$GUM_FILTER_HEIGHT" "${GUM_FILTER_STYLE[@]}" --prompt "Iteration> " --placeholder "Select iteration time" --padding "$GUM_FILTER_PADDING") || {
            rx_step_error "2" "Iteration time selection cancelled"
            rx_retry_or_exit "Iteration time is required" || rx_abort
            return 1
        }

        case "$iter_choice" in
            "1000 ms (fastest)") LUKS_ITER_TIME=1000 ;;
            "2000 ms") LUKS_ITER_TIME=2000 ;;
            "3000 ms") LUKS_ITER_TIME=3000 ;;
            "4000 ms") LUKS_ITER_TIME=4000 ;;
            "5000 ms (balanced)") LUKS_ITER_TIME=5000 ;;
            "7500 ms") LUKS_ITER_TIME=7500 ;;
            "10000 ms") LUKS_ITER_TIME=10000 ;;
            "15000 ms") LUKS_ITER_TIME=15000 ;;
            "30000 ms") LUKS_ITER_TIME=30000 ;;
            "60000 ms (most secure)") LUKS_ITER_TIME=60000 ;;
            *) LUKS_ITER_TIME=5000 ;;
        esac
    else
        # shellcheck disable=SC2034
        LUKS_ENABLED="false"
        # shellcheck disable=SC2034
        LUKS_PASSWORD=""
        # shellcheck disable=SC2034
        LUKS_ITER_TIME=""
    fi

    rx_save_state
    return 0
}

if ! setup_luks; then
    rx_setup_fail "LUKS"
fi

