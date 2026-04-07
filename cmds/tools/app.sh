#!/bin/bash

is_tui() {
    local cmd="$1"
    [[ $cmd == "yazi" || $cmd == "nvim" || $cmd == "vim" || $cmd == "ranger" || $cmd == "btop" || $cmd == "cava" ]]
}

get_scripts_path() {
    local mod_path="$1"
    [[ ! -d $mod_path ]] && return 1
    local config_rel=$(grep -o '"files"\s*:\s*"[^"]*"' "$mod_path/targets.json" 2>/dev/null | cut -d'"' -f4)
    [[ -z $config_rel ]] && config_rel=$(rx_get_json "$mod_path/targets.json" "config" "files" 2>/dev/null)
    local config_dir="${config_rel#./}"
    echo "${mod_path}/${config_dir}/scripts"
}

cmd_apps() {
    local app_name="$1"
    local action="$2"
    shift 2
    local extra_args="$@"
    local var_script="$RETRO_DIR/scripts/variable_core.sh"

    if [[ $app_name == "list" || -z $app_name ]]; then
        if [[ -z $app_name ]]; then
            rx_log "info" "Usage: retro app <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List all available applications"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "<app> open" "Launch an application"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "<app> close" "Close an application"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "<app> refresh" "Refresh an application"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "<app> list" "Show actions for an app"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "all <action>" "Run action for all apps"
            echo ""
        fi

        rx_log "info" "Available Applications:"

        local raw_vars=$(bash "$var_script" --list 2>/dev/null)
        local v_apps=$(echo "$raw_vars" | awk -F'=' '/RETRO_.*_CMD/ {gsub(/^RETRO_|_CMD$/, "", $1); print tolower($1)}')
        local suppression_list=$(echo "$raw_vars" | awk -F'"' '/RETRO_.*_CMD/ {print tolower($2)}')
        local m_apps=$(ls -1 "$RETRO_DIR/modules" 2>/dev/null | grep -v "^retro$")

        local sup_flat=" ${suppression_list//$'\n'/ } "
        local term_val=$(get_var "RETRO_TERMINAL_CMD" "kitty")

        for a in $(echo -e "$v_apps\n$m_apps" | sort -u); do
            if [[ ! " $v_apps " =~ " $a " ]] && [[ $sup_flat =~ " $a " ]]; then
                continue
            fi

            local has_var=false
            local has_scripts=false
            [[ $raw_vars == *"RETRO_${a^^}_CMD="* ]] && has_var=true

            local mod_to_check="$a"
            [[ $a == "terminal" ]] && mod_to_check="$term_val"

            local m_path="$RETRO_DIR/modules/$mod_to_check"
            local s_dir=$(get_scripts_path "$m_path")
            [[ -f "$s_dir/open_${mod_to_check}.sh" || -f "$s_dir/refresh_${mod_to_check}.sh" || -f "$s_dir/close_${mod_to_check}.sh" ]] && has_scripts=true

            ($has_var || $has_scripts) && echo -e "  ${PINK}󰄾${RESET} $a"
        done
        return 0
    fi

    if [[ $app_name == "all" ]]; then
        [[ -z $action ]] && rx_log "error" "An action [open|refresh|close] must be specified for 'all'." && return 1
        rx_log "info" "Executing '${action}' for all valid modules..."
        local all_apps=$(echo -e "$(bash "$var_script" --list 2>/dev/null | awk -F'=' '/RETRO_.*_CMD/ {gsub(/^RETRO_|_CMD$/, "", $1); print tolower($1)}')\n$(ls -1 "$RETRO_DIR/modules" 2>/dev/null | grep -v '^retro$')" | sort -u)
        for a in $all_apps; do cmd_apps "$a" "$action" $extra_args 2>/dev/null; done
        return 0
    fi

    local var_key="RETRO_${app_name^^}_CMD"
    local target_cmd=$(get_var "$var_key")
    local term=$(get_var "RETRO_TERMINAL_CMD" "kitty")

    local mod_name="$app_name"
    [[ $app_name == "terminal" ]] && mod_name="$term"

    local mod_path="$RETRO_DIR/modules/$mod_name"
    local s_dir=$(get_scripts_path "$mod_path")
    local actions=()

    [[ -n $target_cmd && $target_cmd != "null" ]] && actions+=("open")
    [[ -f "$s_dir/open_${mod_name}.sh" ]] && [[ ! " ${actions[*]} " =~ " open " ]] && actions+=("open")
    [[ -f "$s_dir/refresh_${mod_name}.sh" ]] && actions+=("refresh")
    [[ -f "$s_dir/close_${mod_name}.sh" ]] && actions+=("close")
    [[ ${#actions[@]} -eq 0 ]] && command -v "$app_name" &>/dev/null && actions+=("open")

    if [[ -z $action || $action == "list" ]]; then
        [[ ${#actions[@]} -eq 0 ]] && rx_log "error" "No actions available for '${app_name}'." && return 1
        rx_log "info" "Usage: retro app $app_name [$(
            IFS="|"
            echo "${actions[*]}"
        )]"
        return 0
    fi

    if [[ $action == "open" ]]; then
        local custom_open="$s_dir/open_${mod_name}.sh"
        if [[ -f $custom_open ]]; then
            rx_log "info" "Executing custom open script for ${mod_name^}..."
            (cd "$mod_path" && setsid bash "$custom_open" $extra_args >/dev/null 2>&1 &)
            return 0
        fi

        if [[ $app_name == "terminal" ]]; then
            local open_term_script="$RETRO_DIR/modules/kitty/files/scripts/open_kitty.sh"
            if [[ -n $extra_args ]]; then
                (setsid bash "$open_term_script" -- bash -c "$extra_args; exec bash" >/dev/null 2>&1 &)
            else
                (setsid bash "$open_term_script" >/dev/null 2>&1 &)
            fi
            return 0
        fi

        if is_tui "$target_cmd"; then
            (setsid $term bash -c "$target_cmd $extra_args; exec bash" >/dev/null 2>&1 &)
            return 0
        fi

        if [[ -n $target_cmd && $target_cmd != "null" ]]; then
            (setsid $target_cmd $extra_args >/dev/null 2>&1 &)
            return 0
        fi

        if command -v "$app_name" &>/dev/null; then
            (setsid $app_name $extra_args >/dev/null 2>&1 &)
            return 0
        fi
    fi

    if [[ $action == "close" ]]; then
        local custom_close="$s_dir/close_${mod_name}.sh"
        if [[ -f $custom_close ]]; then
            (cd "$mod_path" && bash "$custom_close" $extra_args)
            return $?
        elif [[ -n $target_cmd && $target_cmd != "null" ]]; then
            pkill -f "$target_cmd" && rx_log "success" "Stopped ${app_name^}."
            return 0
        fi
    fi

    local action_script="$s_dir/${action}_${mod_name}.sh"
    if [[ -f $action_script ]]; then
        rx_log "info" "Executing ${action} script for ${mod_name^}..."
        (cd "$mod_path" && bash "$action_script" $extra_args)
        return $?
    fi

    rx_log "error" "Action '${action}' not supported for ${app_name}."
    return 1
}

register_command "TOOLS" "app" "Centralized app manager" "cmd_apps"
