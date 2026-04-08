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
                else
                    rx_log "error" "No variables found matching: ${PINK}$key${RESET}"
                fi
            else
                if bash "$var_script" --del "$key"; then
                    rx_log "success" "Removed ${PINK}$key${RESET} from the cache."
                else
                    rx_log "error" "Key ${PINK}$key${RESET} doesn't exist in the cache."
                fi
            fi
            ;;

        "toggle")
            [[ -z $key ]] && rx_log "error" "Which key are we toggling?" && return 1

            local old_val=$(bash "$var_script" --get "$key")
            local new_val=$(bash "$var_script" --toggle "$key")

            rx_log "success" "Toggled ${PINK}$key${RESET}: ${GRAY}$old_val${RESET} -> ${PINK}$new_val${RESET}"
            ;;

        "add")
            [[ -z $key || -z $value ]] && rx_log "error" "I need both a key and a value to append." && return 1

            local current=$(bash "$var_script" --get "$key")

            if [[ -z $current || $current == "null" ]]; then
                bash "$var_script" --set "$key" "$value"
                rx_log "success" "Created ${PINK}$key${RESET} with: $value"
            else
                if [[ "|${current}|" == *"|${value}|"* ]]; then
                    rx_log "info" "The value '${value}' is already in ${PINK}$key${RESET}."
                    return 0
                fi

                local new_val="${current}|${value}"
                bash "$var_script" --set "$key" "$new_val"
                rx_log "success" "Appended to ${PINK}$key${RESET}. New value: ${INFO}$new_val${RESET}"
            fi
            ;;

        "remove")
            [[ -z $key || -z $value ]] && rx_log "error" "I need a key and the specific element to remove." && return 1

            local current=$(bash "$var_script" --get "$key")

            if [[ -z $current || $current == "null" ]]; then
                rx_log "error" "Key ${PINK}$key${RESET} is empty or doesn't exist." && return 1
            fi

            if [[ "|${current}|" != *"|${value}|"* ]]; then
                rx_log "error" "Could not find '${value}' inside ${PINK}$key${RESET}." && return 1
            fi

            local temp="|${current}|"
            temp="${temp//|${value}|/|}"

            temp="${temp#|}"
            temp="${temp%|}"

            [[ -z $temp ]] && temp="null"

            if bash "$var_script" --set "$key" "$temp"; then
                rx_log "success" "Removed '${value}' from ${PINK}$key${RESET}. New value: ${INFO}$temp${RESET}"
            fi
            ;;

        "edit")
            local var_file="$HOME/.cache/retro/variables.sh"

            if [[ ! -f $var_file ]]; then
                rx_log "error" "Variables cache not found at $var_file" && return 1
            fi

            ${EDITOR:-nano} "$var_file"

            rx_log "success" "Finished editing variables."
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
            rx_log "info" "Usage: retro variable <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "get <key>" "Get a variable value"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "set <k> <v>" "Set a variable value"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "del <key>" "Delete a variable (supports *)"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "toggle <key>" "Toggle boolean variable"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "add <k> <v>" "Append to pipe-delimited value"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "remove <k> <v>" "Remove element from value"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "edit" "Open variables file in editor"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List all variables"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "reset" "Reset all variables to defaults"
            echo ""
            echo -e " ${PINK}  ${RESET}Examples${GRAY}:${RESET}"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro variable get RETRO_WALLPAPER" "Get a variable value"
            printf " ${GRAY}%-35s${RESET} %s\n" 'retro variable set RETRO_THEME "retro"' "Set a variable value"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro variable toggle RETRO_BORDER" "Toggle boolean"
            printf " ${GRAY}%-35s${RESET} %s\n" 'retro variable add RETRO_FONT_NERD "JetBrainsMono Nerd Font"' "Append to value"
            printf " ${GRAY}%-35s${RESET} %s\n" 'retro variable remove RETRO_FONT_MAIN "Inter"' "Remove from value"
            printf " ${GRAY}%-35s${RESET} %s\n" "retro variable del RETRO_*" "Delete with wildcard"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "variable" "Manage global state and persistent variables" "cmd_var"
