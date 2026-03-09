#!/bin/bash

get_scripts_path() {
    local mod_path="$1"
    local config_rel=$(rx_get_json "$mod_path/targets.json" "config" "files")
    local config_dir="${config_rel#./}"
    echo "${mod_path}/${config_dir}/scripts"
}

cmd_apps() {
    local app_name="$1"
    local action="$2"
    shift 2
    local extra_args="$@"

    if [[ $app_name == "list" || -z $app_name ]]; then
        rx_log "info" "Available Applications:"
        for mod_dir in "$RETRO_DIR"/modules/*/; do
            local m=$(basename "$mod_dir")
            [[ $m == "retro" ]] && continue
            local s_dir=$(get_scripts_path "$mod_dir")
            local bin=$(rx_get_json "$mod_dir/targets.json" "bin" "")
            if [[ -d $s_dir || -n $bin ]]; then
                echo -e "  ${PINK}󰄾${RESET} $m"
            fi
        done
        return 0
    fi

    local mod_path="$RETRO_DIR/modules/$app_name"
    if [[ ! -d $mod_path ]]; then
        rx_log "error" "Application module '${app_name}' not found."
        return 1
    fi

    local scripts_dir=$(get_scripts_path "$mod_path")
    local bin_name=$(rx_get_json "$mod_path/targets.json" "bin" "")

    local can_open=false
    [[ -f "$scripts_dir/open_${app_name}.sh" || -n $bin_name ]] && can_open=true
    local can_close=false
    [[ -f "$scripts_dir/close_${app_name}.sh" || -n $bin_name ]] && can_close=true
    local can_refresh=false
    [[ -f "$scripts_dir/refresh_${app_name}.sh" ]] && can_refresh=true

    if [[ $action == "list" || -z $action ]]; then
        local actions=()
        $can_open && actions+=("open")
        $can_refresh && actions+=("refresh")
        $can_close && actions+=("close")

        local joined=$(
            IFS="|"
            echo "${actions[*]}"
        )
        rx_log "info" "Actions for ${PINK}${app_name}${RESET}: [${joined:-NONE}]"
        return 0
    fi

    case "$action" in
        "open") $can_open || {
            rx_log "error" "Cannot open $app_name"
            return 1
        } ;;
        "refresh") $can_refresh || {
            rx_log "error" "Cannot refresh $app_name"
            return 1
        } ;;
        "close") $can_close || {
            rx_log "error" "Cannot close $app_name"
            return 1
        } ;;
        *)
            rx_log "error" "Unknown action '$action'. Use 'list' to see options."
            return 1
            ;;
    esac

    local custom_script="$scripts_dir/${action}_${app_name}.sh"
    if [[ -f $custom_script ]]; then
        rx_log "info" "Executing ${PINK}${action}${RESET} logic..."
        (cd "$mod_path" && bash "$custom_script" $extra_args)
        return $?
    fi

    case "$action" in
        "open") nohup "$bin_name" $extra_args >/dev/null 2>&1 & ;;
        "close") pkill -f "$bin_name" && rx_log "success" "Stopped $bin_name" ;;
    esac
}

register_command "TOOLS" "-app|--application" "Module-based application manager" "cmd_apps"
