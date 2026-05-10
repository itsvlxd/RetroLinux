#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/module.sh"

cmd_install() {
    local target="${1}"
    local type_filter=""
    local access_filter=""
    local skip_prompt=""
    local flags=""

    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t | --type)
                type_filter="$2"
                shift 2
                ;;
            -a | --access)
                access_filter="$2"
                shift 2
                ;;
            -h | --help)
                show_install_help
                return 0
                ;;
            -y | --yes)
                skip_prompt="true"
                export SKIP_PROMPT=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    [[ -z $target ]] && show_install_help && return 0

    [[ -n $type_filter ]] && export MODULE_TYPE_FILTER="$type_filter"
    [[ -n $access_filter ]] && export MODULE_ACCESS_FILTER="$access_filter"

    local modules_msg=""
    if [[ $target == "all" || $target == "existing" ]]; then
        local mods=()
        local access_filt=""
        [[ -n $access_filter && $access_filter != "all" ]] && access_filt="$access_filter"

        if [[ $target == "existing" ]]; then
            while IFS= read -r m; do
                [[ -z $m ]] && continue
                filter_module "$m" && mods+=("$m")
            done < <(get_installed_modules "$access_filt")
        else
            for dir in "$RETRO_DIR"/modules/*/; do
                [[ -d $dir ]] || continue
                local m=$(basename "$dir")
                filter_module "$m" && mods+=("$m")
            done
        fi

        if [[ ${#mods[@]} -gt 0 ]]; then
            local first=true
            for m in "${mods[@]}"; do
                if [[ $first == "true" ]]; then
                    modules_msg="${PINK}${m}${RESET}"
                    first=false
                else
                    modules_msg+=", ${PINK}${m}${RESET}"
                fi
            done
        fi
    fi

    if [[ -n $modules_msg ]]; then
        rx_log "info" "Installing: $modules_msg"
    else
        rx_log "info" "Starting installation for: ${PINK}${target}${RESET}"
    fi

    [[ -n $type_filter ]] && rx_log "info" "Filtered by type: ${PINK}$type_filter${RESET}"
    [[ -n $access_filter ]] && rx_log "info" "Filtered by access: ${PINK}$access_filter${RESET}"

    if [[ $access_filter == "root" && $EUID -ne 0 ]]; then
        rx_log "error" "Root access required. Please run the previous command with sudo"
        return 1
    fi

    run_task "install" "$target"
}

show_install_help() {
    rx_help_usage "retro -i <module> [options]"
    rx_help_commands "Install Options"
    rx_help_cmd "-t, --type" "Filter by type (core|extra|all)"
    rx_help_cmd "-a, --access" "Filter by access (root|user|all)"
    rx_help_cmd "-y, --yes" "Skip confirmation"

    rx_help_examples
    rx_help_example "retro -i hyprland -y" "Install single module"
    rx_help_example "retro -i all -y" "Install all modules"
    rx_help_example "retro -i existing -y" "Install only currently installed modules"
    rx_help_example "retro -i all -t core -y" "Install core modules only"
    rx_help_example "retro -i all -t extra -y" "Install extra modules only"
    rx_help_example "retro -i all -a user -y" "Install user-space modules"
    rx_help_example "retro -i all -a root -y" "Install system modules (requires sudo)"
    rx_help_example "retro -i existing -a user -y" "Reinstall only installed user modules"
    rx_help_example "retro -i existing -a root -y" "Reinstall only installed root modules"
    rx_help_spacer
}

register_command "MODULES" "-i|--install" "Link repo files to system (Active Ricing)" "cmd_install"
