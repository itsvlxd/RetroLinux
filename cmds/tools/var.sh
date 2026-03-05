#!/bin/bash

source "$RETRO_DIR/lib/setup/vars.sh"

cmd_var() {
    local var_script="$RETRO_DIR/scripts/variable_core.sh"
    local action="$1"
    local key="$2"
    local value="$3"

    case "$action" in
        "get")
            [[ -z $key ]] && rx_log "error" "Provide a KEY to fetch." && return 1
            bash "$var_script" get "$key"
            ;;

        "set")
            [[ -z $key || -z $value ]] && rx_log "error" "Provide both KEY and VALUE." && return 1

            if bash "$var_script" set "$key" "$value"; then
                rx_log "success" "Variable Manifested: ${PINK}$key${RESET} -> $value"
            fi
            ;;

        "del")
            [[ -z $key ]] && rx_log "error" "Provide a KEY to delete." && return 1

            local old_val=$(bash "$var_script" get "$key")

            if bash "$var_script" del "$key"; then
                rx_log "success" "Variable Purged: ${PINK}$key${RESET} removed from cache"
            fi
            ;;

        "toggle")
            [[ -z $key ]] && rx_log "error" "Provide a KEY to toggle." && return 1
            local new_val=$(bash "$var_script" toggle "$key")
            echo -e " ${PINK}󰔡 $key:${RESET} $new_val"
            ;;

        "reset")
            rm -rf "$HOME/.cache/retro/variables.sh"

            rx_vars_defaults "-f"
            ;;

        "list")
            echo -e "\n ${PINK} Cache Storage: ${RESET}${RETRO_CACHE}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            local raw_list=$(bash "$var_script" list 2>/dev/null)

            if [[ -z $raw_list ]]; then
                echo -e " ${GRAY}  (No variables defined)${RESET}"
            else
                while IFS='=' read -r k v; do
                    [[ -z $k ]] && continue
                    v="${v%\"}"
                    v="${v#\"}"

                    local val_color="$GRAY"
                    if [[ $v =~ ^[0-9]+$ ]]; then
                        val_color="$INFO"
                    elif [[ $v == "true" ]]; then
                        val_color="$SUCCESS"
                    elif [[ $v == "false" ]]; then
                        val_color="$ERROR"
                    fi

                    printf " ${PINK}󰋙${RESET} %-30s ${val_color}%s${RESET}\n" "$k:" "$v"
                done <<<"$raw_list"
            fi

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;
        *)
            rx_log "info" "Usage: retro --variable [get|set|del|toggle|list|reset]"
            ;;
    esac
}

register_command "TOOLS" "-var|--variable" "Manage global state and persistent variables" "cmd_var"
