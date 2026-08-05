#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/cmds/system/setup/variables.sh"

cmd_var() {
    local var_script="$RETRO_DIR/scripts/variable_core.sh"
    local action="${1,,}"
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
            local var_file="$RETRO_CONFIG/variables.sh"

            if [[ ! -f $var_file ]]; then
                rx_log "error" "Variables cache not found at $var_file" && return 1
            fi

            ${EDITOR:-nano} "$var_file"

            reload_vars

            rx_log "success" "Finished editing variables."
            ;;

        "reset")
            rm -rf "$RETRO_CONFIG/variables.sh"
            rx_vars_defaults "-f"
            reload_vars
            rx_log "success" "Variables reset to defaults."
            ;;

        "reset")
            rm -rf "$RETRO_CONFIG/variables.sh"
            rx_vars_defaults "-f"
            reload_vars
            rx_log "success" "Variables reset to defaults."
            ;;

        "list")
            rx_table_header "" "Cache Location: ${RETRO_CONFIG}"

            local raw_list=$(bash "$var_script" --list 2>/dev/null)

            if [[ -z $raw_list ]]; then
                rx_table_simple "󰋙" "(Everything is empty)" "$GRAY"
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

                    rx_table_row "󰋙" "$k:" "$v" "$val_color" "30"
                done
            fi

            rx_table_separator
            rx_table_spacer
            ;;

        "update")
            local defaults_file="$RETRO_DIR/modules/retro/files/variables.sh"
            [[ ! -f $defaults_file ]] && rx_log "error" "Defaults file not found: $defaults_file" && return 1

            source "$defaults_file"

            local vardir="${RETRO_CONFIG:-$HOME/.config/retro}"
            local varsfile="$vardir/variables.sh"
            [[ ! -d $vardir ]] && mkdir -p "$vardir"

            local added_vars=()
            local skip_patterns="^(KITTY_(WINDOW_ID|PID|INSTALLATION_DIR|LISTEN_ON|PUBLIC_KEY)|NOTIFY_SOCKET|BAT_PATH)"

            for default_var in "${!RETRO_@}" "${!KITTY_@}" "${!ROFI_@}" "${!BAT_@}" "${!PWR_@}" "${!WALL_@}" "${!CLIP_@}" "${!NOTIFY_@}" "${!CAFFEINE_@}"; do
                [[ $default_var != RETRO_* && $default_var != KITTY_* && $default_var != ROFI_* && $default_var != BAT_* && $default_var != PWR_* && $default_var != WALL_* && $default_var != CLIP_* && $default_var != NOTIFY_* && $default_var != CAFFEINE_* ]] && continue

                [[ $default_var == RETRO_DIR || $default_var == RETRO_CONFIG || $default_var == RETRO_CACHE || $default_var == RETRO_STATE ]] && continue

                [[ $default_var =~ $skip_patterns ]] && continue

                local default_val="${!default_var}"

                if ! grep -q "^export $default_var=" "$varsfile" 2>/dev/null; then
                    set_var "$default_var" "$default_val"
                    added_vars+=("$default_var")
                fi
            done

            if [[ ${#added_vars[@]} -gt 0 ]]; then
                rx_log "success" "Added ${#added_vars[@]} variables:"
                for var in "${added_vars[@]}"; do
                    val=$(grep "^export $var=" "$varsfile" | sed 's/.*="\([^"]*\)".*/\1/')
                    rx_log "info" "$var: $PINK$val$RESET"
                done
            else
                rx_log "info" "No new variables to add"
            fi
            ;;

        "prune")
            local defaults_file="$RETRO_DIR/modules/retro/files/variables.sh"
            [[ ! -f $defaults_file ]] && rx_log "error" "Defaults file not found: $defaults_file" && return 1

            source "$defaults_file"

            local default_keys=()
            for default_var in "${!RETRO_@}" "${!KITTY_@}" "${!ROFI_@}" "${!BAT_@}" "${!PWR_@}" "${!WALL_@}" "${!CLIP_@}" "${!NOTIFY_@}" "${!CAFFEINE_@}"; do
                [[ $default_var != RETRO_* && $default_var != KITTY_* && $default_var != ROFI_* && $default_var != BAT_* && $default_var != PWR_* && $default_var != WALL_* && $default_var != CLIP_* && $default_var != NOTIFY_* && $default_var != CAFFEINE_* ]] && continue

                [[ $default_var == RETRO_DIR || $default_var == RETRO_CONFIG || $default_var == RETRO_CACHE || $default_var == RETRO_STATE ]] && continue

                default_keys+=("$default_var")
            done

            local vardir="${RETRO_CONFIG:-$HOME/.config/retro}"
            local varsfile="$vardir/variables.sh"

            if [[ ! -f $varsfile ]]; then
                rx_log "info" "No local variables to prune"
                return 0
            fi

            local removed_vars=()
            local local_vars=$(bash "$var_script" --list 2>/dev/null)

            while IFS='=' read -r key v; do
                [[ -z $key ]] && continue

                local is_default=false
                for dk in "${default_keys[@]}"; do
                    [[ $key == "$dk" ]] && {
                        is_default=true
                        break
                    }
                done

                if [[ $is_default == false ]]; then
                    bash "$var_script" --del "$key"
                    removed_vars+=("$key")
                fi
            done <<<"$local_vars"

            if [[ ${#removed_vars[@]} -gt 0 ]]; then
                rx_log "success" "Removed ${#removed_vars[@]} variables:"
                for var in "${removed_vars[@]}"; do
                    rx_log "info" "  $var"
                done
            else
                rx_log "info" "No obsolete variables to remove"
            fi
            ;;

        *)
            rx_help_usage "retro variable <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "get <key>" "Get a variable value"
            rx_help_cmd "set <k> <v>" "Set a variable value"
            rx_help_cmd "del <key>" "Delete a variable (supports *)"
            rx_help_cmd "toggle <key>" "Toggle boolean variable"
            rx_help_cmd "add <k> <v>" "Append to pipe-delimited value"
            rx_help_cmd "remove <k> <v>" "Remove element from value"
            rx_help_cmd "edit" "Open variables file in editor"
            rx_help_cmd "list" "List all variables"
            rx_help_cmd "reset" "Reset all variables to defaults"
            rx_help_cmd "update" "Add missing default variables"
            rx_help_cmd "prune" "Remove obsolete variables"
            rx_help_examples
            rx_help_example "retro variable get RETRO_WALLPAPER" "Get a variable value"
            rx_help_example 'retro variable set RETRO_THEME "retro"' "Set a variable value"
            rx_help_example "retro variable toggle RETRO_BORDER" "Toggle boolean"
            rx_help_example 'retro variable add RETRO_FONT_NERD "JetBrainsMono Nerd Font"' "Append to value"
            rx_help_example 'retro variable remove RETRO_FONT_MAIN "Inter"' "Remove from value"
            rx_help_example "retro variable del RETRO_*" "Delete with wildcard"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "variable" "Manage global state and persistent variables" "cmd_var"
