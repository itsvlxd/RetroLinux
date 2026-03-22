#!/bin/bash

is_tui() {
    local cmd="$1"
    [[ $cmd == "yazi" || $cmd == "nvim" || $cmd == "vim" || $cmd == "ranger" ]]
}

get_scripts_path() {
    local mod_path="$1"
    [[ ! -d $mod_path ]] && return 1
    local config_rel=$(rx_get_json "$mod_path/targets.json" "config" "files")
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
        rx_log "info" "Available Applications:"
        local v_apps=$(bash "$var_script" --list 2>/dev/null | grep "RETRO_.*_CMD" | cut -d'=' -f1 | sed 's/RETRO_//;s/_CMD//' | tr '[:upper:]' '[:lower:]')
        local m_apps=$(ls -1 "$RETRO_DIR/modules" 2>/dev/null | grep -v "retro")
        for a in $(echo -e "$v_apps\n$m_apps" | sort -u); do
            local has_var=false
            local has_scripts=false
            [[ -n $(get_var "RETRO_${a^^}_CMD") && $(get_var "RETRO_${a^^}_CMD") != "null" ]] && has_var=true
            local m_path="$RETRO_DIR/modules/$a"
            local s_dir=$(get_scripts_path "$m_path")
            [[ -f "$s_dir/open_${a}.sh" || -f "$s_dir/refresh_${a}.sh" || -f "$s_dir/close_${a}.sh" ]] && has_scripts=true
            ($has_var || $has_scripts) && echo -e "  ${PINK}󰄾${RESET} $a"
        done
        return 0
    fi

    if [[ $app_name == "all" ]]; then
        [[ -z $action ]] && rx_log "error" "An action [open|refresh|close] must be specified for 'all'." && return 1
        rx_log "info" "Executing '${action}' for all valid modules..."
        local all_apps=$(echo -e "$(bash "$var_script" --list 2>/dev/null | grep "RETRO_.*_CMD" | cut -d'=' -f1 | sed 's/RETRO_//;s/_CMD//' | tr '[:upper:]' '[:lower:]')\n$(ls -1 "$RETRO_DIR/modules" 2>/dev/null | grep -v 'retro')" | sort -u)
        for a in $all_apps; do cmd_apps "$a" "$action" $extra_args 2>/dev/null; done
        return 0
    fi

    local var_key="RETRO_${app_name^^}_CMD"
    local target_cmd=$(get_var "$var_key")
    local mod_path="$RETRO_DIR/modules/$app_name"
    local s_dir=$(get_scripts_path "$mod_path")
    local actions=()

    [[ -n $target_cmd && $target_cmd != "null" ]] && actions+=("open")
    [[ -f "$s_dir/open_${app_name}.sh" ]] && [[ ! " ${actions[*]} " =~ " open " ]] && actions+=("open")
    [[ -f "$s_dir/refresh_${app_name}.sh" ]] && actions+=("refresh")
    [[ -f "$s_dir/close_${app_name}.sh" ]] && actions+=("close")

    if [[ -z $action || $action == "list" ]]; then
        [[ ${#actions[@]} -eq 0 ]] && rx_log "error" "No actions available for '${app_name}'." && return 1
        rx_log "info" "Usage: retro -app $app_name [$(
            IFS="|"
            echo "${actions[*]}"
        )]"
        return 0
    fi

    if [[ $action == "open" && -n $target_cmd && $target_cmd != "null" ]]; then
        rx_log "info" "Launching ${app_name^}..."
        if is_tui "$target_cmd"; then
            local term=$(get_var "RETRO_TERMINAL_CMD")
            [[ -z $term || $term == "null" ]] && term="kitty"
            (setsid $term $target_cmd $extra_args >/dev/null 2>&1 &)
        else
            (setsid $target_cmd $extra_args >/dev/null 2>&1 &)
        fi
        return 0
    fi

    if [[ $action == "close" && -n $target_cmd && $target_cmd != "null" ]]; then
        if [[ ! -f "$s_dir/close_${app_name}.sh" ]]; then
            pkill -f "$target_cmd" && rx_log "success" "Stopped ${app_name^}."
            return 0
        fi
    fi

    local custom_script="$s_dir/${action}_${app_name}.sh"
    if [[ -f $custom_script ]]; then
        rx_log "info" "Executing ${action} script for ${app_name^}..."
        (cd "$mod_path" && bash "$custom_script" $extra_args)
        return $?
    fi

    rx_log "error" "The action '${action}' is not supported for ${app_name}."
    return 1
}

register_command "TOOLS" "-app|--application" "Centralized app manager" "cmd_apps"
