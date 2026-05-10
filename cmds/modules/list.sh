#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

rx_module_status() {
    local mod_name="$1"
    local mod_dir="$RETRO_DIR/modules/$mod_name"
    local props_file="$mod_dir/properties.json"

    [[ ! -f $props_file ]] && return 255

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

get_module_info() {
    local mod_name="$1"
    local field="$2"
    local mod_dir="$RETRO_DIR/modules/$mod_name"
    local props_file="$mod_dir/properties.json"

    rx_get_json "$props_file" "$field" "" 2>/dev/null
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

        local mod_type=$(get_module_info "$mod_name" "type")
        local mod_access=$(get_module_info "$mod_name" "access")
        local mod_title=$(get_module_info "$mod_name" "title")

        [[ -z $mod_title ]] && mod_title="$mod_name"

        local type_icon=""
        local type_color=""
        case "$mod_type" in
            core)
                type_icon="󰘽"
                type_color="${ERROR}"
                ;;
            extra)
                type_icon="󰌆"
                type_color="${SUCCESS}"
                ;;
            *)
                type_icon="󰅟"
                type_color="${GRAY}"
                ;;
        esac

        local access_icon=""
        case "$mod_access" in
            root) access_icon="󰌉" ;;
            user) access_icon="󰀇" ;;
        esac

        local lock_icon=""
        if [[ $mod_type == "core" ]]; then
            lock_icon=" 󰏌"
        fi

        local match="${mod_name,,}"
        local icon="󰅟 "
        case "$match" in
            *hypr*) icon=" " ;;
            *retro*) icon="󰊗 " ;;
            *kitty*) icon="󰄛 " ;;
            *rofi*) icon="󰣖 " ;;
            *matugen*) icon="󰏘 " ;;
        esac

        printf " ${PINK}%b${RESET} %b%b%b\n" \
            "$icon" \
            "$mod_title:   " \
            "$status_text" \
            "${GRAY}$lock_icon${RESET}"
    done

    rx_table_separator
    rx_table_spacer
    printf " ${GRAY}%s${RESET}\n" "Legend: 󰘽 core (locked) 󰌆 extra  󰌉 root 󰀇 user"
    rx_table_spacer
}
register_command "MODULES" "-ls|--list" "List all available and installed modules" "cmd_list_modules"

