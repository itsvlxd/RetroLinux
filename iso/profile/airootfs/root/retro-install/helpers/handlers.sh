ERROR_HANDLING=false

# INFO: QRCode generated using qren:
# rencode -t ANSIUTF8 "https://github.com/itsvlxd/RetroLinux/issues/new"

QR_CODE='
█████████████████████████████████████
█████████████████████████████████████
████ ▄▄▄▄▄ █▀█ █▄▄▄▀ ▀█▄ █ ▄▄▄▄▄ ████
████ █   █ █▀▀▀█ ▀█  ▀▄▄▀█ █   █ ████
████ █▄▄▄█ █▀ █▀▀ ▀▀▄▄▄▄▄█ █▄▄▄█ ████
████▄▄▄▄▄▄▄█▄▀ ▀▄█ █ █ █ █▄▄▄▄▄▄▄████
████▄▄▄▄▄█▄  ▄▀▄  ▄█▀ █▀ ▄▀ ▀▄█▄▀████
████ ▀ ██ ▄▀██▄▀██▀ ▄█ █▄███▄▀█▀█████
████ ▄▀  ▀▄█▀ ▄▀█▄ █▀▄▀ ▀▀▀▀▀▄▄█▀████
████▄▀▄█ █▄▀▄ ███▄▀ ▀█▀▀  ▀▀ ▄▄▀█████
████ ▄▀▀ ▄▄ █▀▀▀▄▄ ▀▀   █ ▀ ▀▄ █▀████
████ █  █▄▄ ▄▀ ▀▄▄▀▄ ▄██ ▀ ▄▄█▄▀█████
████▄██▄▄▄▄▄▀██ ▄▄ █▀██▄ ▄▄▄ ▀   ████
████ ▄▄▄▄▄ █▄▀█▀██ ▄█▄   █▄█ ▄▄▀█████
████ █   █ █ ▀   ▄▄▄ ▄▀▀ ▄▄▄▄▀ ▄▀████
████ █▄▄▄█ █ █▀▀▀█  ▀██▄  ▄ ▄ ▄ █████
████▄▄▄▄▄▄▄█▄█▄██▄▄▄▄▄█▄██▄▄▄█▄██████
█████████████████████████████████████
█████████████████████████████████████
'

show_cursor() {
    printf "\033[?25h"
}

show_log_tail() {
    if [[ -f $RETRO_INSTALL_LOG_FILE ]]; then
        local log_lines=$((TERM_HEIGHT - LOGO_HEIGHT - 40))
        local max_line_width=$((LOGO_WIDTH - 4))

        tail -n $log_lines "$RETRO_INSTALL_LOG_FILE" | while IFS= read -r line; do
            if ((${#line} > max_line_width)); then
                local truncated_line="${line:0:max_line_width}..."
            else
                local truncated_line="$line"
            fi
            gum style --foreground 244 "$truncated_line"
        done
        echo
    fi
}

show_failed_script_or_command() {
    if [[ -n ${CURRENT_SCRIPT:-} ]]; then
        gum style --foreground 5 "Failed: $CURRENT_SCRIPT"
    else
        local cmd="$BASH_COMMAND"
        local max_cmd_width=$((LOGO_WIDTH - 4))
        if ((${#cmd} > max_cmd_width)); then
            cmd="${cmd:0:max_cmd_width}..."
        fi
        gum style --foreground 5 "$cmd"
    fi
}

save_original_outputs() {
    exec 3>&1 4>&2
}

restore_outputs() {
    if [[ -e /proc/self/fd/3 ]] && [[ -e /proc/self/fd/4 ]]; then
        exec 1>&3 2>&4
    fi
}

catch_errors() {
    if [[ $ERROR_HANDLING == "true" ]]; then
        return
    else
        ERROR_HANDLING=true
    fi

    local exit_code=$?

    stop_log_output
    restore_outputs

    clear_logo
    show_cursor

    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "RetroLinux installation halted!"
    show_log_tail

    gum style --foreground 255 "Exit code: $exit_code"
    show_failed_script_or_command

    echo
    gum style --foreground 5 "$QR_CODE"
    echo
    gum style --foreground 255 "Scan QR or visit: https://github.com/itsvlxd/RetroLinux/issues"

    while true; do
        options=()

        options+=("Re-run installer")
        options+=("View full log")
        options+=("Exit")

        choice=$(gum choose "${options[@]}" --header "What would you like to do?" --height 6 --padding "1 $PADDING_LEFT")

        case "$choice" in
            "Re-run installer")
                exec /root/retroinstall
                ;;
            "View full log")
                if command -v less &>/dev/null; then
                    less "$RETRO_INSTALL_LOG_FILE"
                else
                    tail "$RETRO_INSTALL_LOG_FILE"
                fi
                ;;
            "Exit" | "")
                exit 1
                ;;
        esac
    done
}

exit_handler() {
    local exit_code=$?

    if ((exit_code != 0)) && [[ $ERROR_HANDLING != "true" ]]; then
        catch_errors
    else
        stop_log_output
        show_cursor
    fi
}

trap catch_errors ERR INT TERM
trap exit_handler EXIT

save_original_outputs

