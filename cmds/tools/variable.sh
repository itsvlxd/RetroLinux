#!/bin/bash

source "$RETRO_DIR/cmds/system/setup/variables.sh"

cmd_var() {
    local var_script="$RETRO_DIR/scripts/variable_core.sh"
    local action="$1"
    local key="$2"
    local value="$3"

    case "$action" in
        "get")
            [[ -z $key ]] && rx_log "error" "I need a key name to look that up." && return 1
            bash "$var_script" --get "$key"
            ;;

        "set")
            [[ -z $key || -z $value ]] && rx_log "error" "I need both a key and a value to set that." && return 1

            if bash "$var_script" --set "$key" "$value"; then
                rx_log "success" "Updated ${PINK}$key${RESET} to: $value"
            fi
            ;;

        "del")
            [[ -z $key ]] && rx_log "error" "Which key do you want to delete?" && return 1

            if [[ $key == *"*"* ]]; then
                if bash "$var_script" --del "$key"; then
                    rx_log "success" "Bulk deleted all variables matching: ${PINK}$key${RESET}"
                fi
            else
                if bash "$var_script" --del "$key"; then
                    rx_log "success" "Removed ${PINK}$key${RESET} from the cache."
                fi
            fi
            ;;

        "toggle")
            [[ -z $key ]] && rx_log "error" "Which key are we toggling?" && return 1

            local old_val=$(bash "$var_script" --get "$key")
            local new_val=$(bash "$var_script" --toggle "$key")

            rx_log "success" "Toggled ${PINK}$key${RESET}: ${GRAY}$old_val${RESET} -> ${PINK}$new_val${RESET}"
            ;;

        "reset")
            rm -rf "$HOME/.cache/retro/variables.sh"
            rx_vars_defaults "-f"
            rx_log "success" "Variables reset to defaults."
            ;;

        "list")
            echo -e "\n ${PINK} Cache Location: ${RESET}${RETRO_CACHE}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            local raw_list=$(bash "$var_script" --list 2>/dev/null)

            if [[ -z $raw_list ]]; then
                echo -e " ${GRAY}  (Everything is empty)${RESET}"
            else
                local first_order=("RETRO_" "BAT_" "PWR_")
                local processed_keys=""
                local final_output=""

                for prefix in "${first_order[@]}"; do
                    local tier=$(echo "$raw_list" | grep "^$prefix" | sort)
                    if [[ -n $tier ]]; then
                        final_output+="${tier}\n"
                        processed_keys+="$(echo "$tier" | cut -d'=' -f1 | tr '\n' '|') "
                    fi
                done

                local exclude_regex=$(echo "$processed_keys" | sed 's/|/\\|/g; s/ $//')
                local remainder=$(echo "$raw_list" | grep -v "^\(${exclude_regex}\)=" | sort)

                final_output+="${remainder}"

                echo -e "$final_output" | sed '/^$/d' | while IFS='=' read -r k v; do
                    [[ -z $k ]] && continue

                    v="${v%\"}"
                    v="${v#\"}"

                    local val_color="$GRAY"
                    if [[ $v =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                        val_color="$INFO"
                    elif [[ $v == "true" ]]; then
                        val_color="$SUCCESS"
                    elif [[ $v == "false" ]]; then
                        val_color="$ERROR"
                    fi

                    printf " ${PINK}󰋙${RESET} %-30s ${val_color}%s${RESET}\n" "$k:" "$v"
                done
            fi

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        *)
            rx_log "info" "Usage: retro --variable [get|set|del|toggle|list|reset]"
            ;;
    esac
}

register_command "TOOLS" "-var|--variable" "Manage global state and persistent variables" "cmd_var"
