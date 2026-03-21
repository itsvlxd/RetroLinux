#!/bin/bash

cmd_open() {
    local app_name="$1"
    local shift_args="${@:2}"
    local var_script="$RETRO_DIR/scripts/variable_core.sh"

    if [[ -z $app_name || $app_name == "-h" || $app_name == "--help" ]]; then
        local raw_list=$(bash "$var_script" --list 2>/dev/null)
        local apps=$(echo "$raw_list" | grep "RETRO_.*_CMD" | cut -d'=' -f1 | sed 's/RETRO_//;s/_CMD//' | tr '[:upper:]' '[:lower:]' | paste -sd "|" -)

        if [[ -z $apps ]]; then
            rx_log "info" "No preconfigured apps have been found. The setup process must be completed to link applications."
            return 0
        fi

        rx_log "info" "Usage: retro -o [$apps] [args]"
        return 0
    fi

    local var_key="RETRO_$(echo "$app_name" | tr '[:lower:]' '[:upper:]')_CMD"
    local target_cmd=$(get_var "$var_key")

    if [[ -n $target_cmd && $target_cmd != "null" ]]; then
        rx_log "info" "Launching ${app_name^}..."

        if [[ $target_cmd == "yazi" || $target_cmd == "nvim" || $target_cmd == "vim" ]]; then
            local term=$(get_var "RETRO_TERMINAL_CMD")
            [[ -z $term || $term == "null" ]] && term="kitty"

            ($term $target_cmd $shift_args >/dev/null 2>&1 &)
        else
            ($target_cmd $shift_args >/dev/null 2>&1 &)
        fi
    else
        rx_log "error" "The app '$app_name' has not been configured in the system variables."
    fi
}

register_command "SYSTEM" "-o|--open" "Launch preconfigured applications saved during setup" "cmd_open"
