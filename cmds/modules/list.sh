#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

rx_module_status() {
    local mod_name="$1"
    local mod_dir="$RETRO_DIR/modules/$mod_name"
    local targets_file="$mod_dir/targets.json"

    [[ ! -f $targets_file ]] && return 255

    IFS='|' read -r repo_src system_dest <<<"$(get_module_paths "$mod_name")"

    if [[ -L $system_dest ]]; then
        local current_link=$(readlink -f "$system_dest")
        local actual_repo_src=$(readlink -f "$repo_src")

        if [[ $current_link == "$actual_repo_src" ]]; then
            return 0
        else
            return 1
        fi

    elif [[ -e $system_dest ]]; then
        if diff -rq "$repo_src" "$system_dest" &>/dev/null; then
            return 0
        else
            return 1
        fi
    fi

    return 2
}

cmd_list_modules() {
    local modules_dir="$RETRO_DIR/modules"

    rx_table_header "󰯉" "Retro Repository Modules"

    for mod_path in "$modules_dir"/*; do
        [[ ! -d $mod_path ]] && continue
        local mod_name=$(basename "$mod_path")

        rx_module_status "$mod_name"
        local status_code=$?

        [[ $status_code -eq 255 ]] && continue

        local status_text=""
        case $status_code in
            0) status_text="${SUCCESS}󰄬 Installed${RESET}" ;;
            1) status_text="${WARN}󰰠 Outdated${RESET} " ;;
            2) status_text="${GRAY}󰄱 Available${RESET}" ;;
        esac

        local mod_bytes=$(du -sb "$mod_path" | awk '{print $1}')
        local mod_size=$(rx_format_size "$mod_bytes")

        local match="${mod_name,,}"
        local icon="󰅟 "
        case "$match" in
            *hypr*) icon=" " ;;
            *retro*) icon="󰊗 " ;;
            *kitty*) icon="󰄛 " ;;
            *rofi*) icon="󰣖 " ;;
            *matugen*) icon="󰏘 " ;;
        esac

        printf " ${PINK}%b ${RESET}%-12s %b ${GRAY}%+12s${RESET}\n" "$icon" "$mod_name:" "$status_text" "$mod_size"
    done

    rx_table_separator
    rx_table_spacer
}
register_command "MODULES" "-ls|--list" "List all available and installed modules" "cmd_list_modules"
