#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

handle_kitty_padding() {
    local pid="$1"
    local is_fullscreen="$2"
    local rule=$(get_var "KITTY_SHRINK_PADDING_FULLSCREEN")
    local default_pd=$(get_var "KITTY_PADDING")

    if [[ $rule == "true" ]]; then
        if [[ $is_fullscreen == "0" || $is_fullscreen == "false" ]]; then
            kitty @ --to="unix:/tmp/kitty-$pid" set-spacing \
                padding-top=1 padding-bottom=1 padding-left=1 padding-right=1 2>/dev/null
        else
            kitty @ --to="unix:/tmp/kitty-$pid" set-spacing \
                padding-top="$default_pd" padding-bottom="$default_pd" \
                padding-left="$default_pd" padding-right="$default_pd" 2>/dev/null
        fi
    fi
}

cmd_wm() {
    local window_core="$RETRO_DIR/scripts/window_core.sh"
    local action="${1,,}"
    local arg1="$2"
    local arg2="$3"

    case "$action" in
        "fullscreen")
            local active=$(hyprctl activewindow -j)
            local class=$(echo "$active" | jq -r '.class')
            local pid=$(echo "$active" | jq -r '.pid')
            local fs_state=$(echo "$active" | jq -r '.fullscreen | tostring')

            if [[ ${class,,} == "kitty" ]]; then
                handle_kitty_padding "$pid" "$fs_state"
            fi
            hyprctl dispatch fullscreen 0
            ;;

        "list")
            local raw_rules=$(bash "$window_core" --list)

            if [[ $raw_rules == "NONE" ]]; then
                rx_table_header "󰨇" "Window Rules"
                rx_table_simple "󰄪" "No custom rules defined" "$PINK"
                rx_table_separator
                rx_table_spacer
                return 0
            fi

            rx_table_header "󰨇" "Custom Window Rules"

            while IFS='|' read -r rtype rname; do
                [[ -z $rtype && -z $rname ]] && continue

                if [[ $rtype == "window" ]]; then
                    rx_table_simple "󰍱" "$rname" "$PINK"
                elif [[ $rtype == "layer" ]]; then
                    rx_table_simple "󰨎" "$rname" "$PINK"
                fi
            done <<<"$raw_rules"

            rx_table_separator
            rx_table_spacer
            ;;

        "add")
            local name="$arg1"
            local rule="$arg2"

            [[ -z $name ]] && rx_log "error" "Usage: retro window add <name> <rule>" && return 1
            [[ -z $rule ]] && rx_log "error" "Usage: retro window add <name> <rule>" && return 1

            local result=$(bash "$window_core" --add "$name" "$rule")

            if [[ $result == "ERROR:blacklisted" ]]; then
                rx_log "error" "This application is blacklisted. Check RETRO_WINDOW_BLACKLIST variable."
                return 1
            elif [[ $result == "ERROR:exists" ]]; then
                rx_log "error" "Rule '${PINK}$name${RESET}' already exists."
                return 1
            elif [[ $result == "APPLIED" ]]; then
                rx_log "success" "Window rule '${PINK}$name${RESET}' added and applied."
            else
                rx_log "error" "Failed to add window rule."
                return 1
            fi
            ;;

        "add-anon")
            local rule="$arg1"

            [[ -z $rule ]] && rx_log "error" "Usage: retro window add-anon <rule>" && return 1

            local result=$(bash "$window_core" --add-anon "window" "$rule")

            if [[ $result == "APPLIED" ]]; then
                rx_log "success" "Anonymous window rule added and applied."
            else
                rx_log "error" "Failed to add anonymous window rule."
                return 1
            fi
            ;;

        "add-layer")
            local name="$arg1"
            local rule="$arg2"

            [[ -z $name ]] && rx_log "error" "Usage: retro window add-layer <name> <rule>" && return 1
            [[ -z $rule ]] && rx_log "error" "Usage: retro window add-layer <name> <rule>" && return 1

            local result=$(bash "$window_core" --add-layer "$name" "$rule")

            if [[ $result == "ERROR:exists" ]]; then
                rx_log "error" "Layer rule '${PINK}$name${RESET}' already exists."
                return 1
            elif [[ $result == "APPLIED" ]]; then
                rx_log "success" "Layer rule '${PINK}$name${RESET}' added and applied."
            else
                rx_log "error" "Failed to add layer rule."
                return 1
            fi
            ;;

        "add-layer-anon")
            local rule="$arg1"

            [[ -z $rule ]] && rx_log "error" "Usage: retro window add-layer-anon <rule>" && return 1

            local result=$(bash "$window_core" --add-anon "layer" "$rule")

            if [[ $result == "APPLIED" ]]; then
                rx_log "success" "Anonymous layer rule added and applied."
            else
                rx_log "error" "Failed to add anonymous layer rule."
                return 1
            fi
            ;;

        "remove")
            local name="$arg1"

            [[ -z $name ]] && rx_log "error" "Usage: retro window remove <name>" && return 1

            local result=$(bash "$window_core" --remove "$name")

            if [[ $result == "ERROR:not_found" ]]; then
                rx_log "error" "Rule '${PINK}$name${RESET}' not found."
                return 1
            elif [[ $result == "APPLIED" ]]; then
                rx_log "success" "Rule '${PINK}$name${RESET}' removed and applied."
            else
                rx_log "error" "Failed to remove rule."
                return 1
            fi
            ;;

        "apply")
            bash "$window_core" --apply
            rx_log "success" "Window rules reloaded."
            ;;

        "show")
            local name="$arg1"

            [[ -z $name ]] && rx_log "error" "Usage: retro window show <name>" && return 1

            local content=$(bash "$window_core" --get "$name")

            if [[ -z $content ]]; then
                rx_log "error" "Rule '${PINK}$name${RESET}' not found."
                return 1
            fi

            rx_table_header "󰨇" "Rule: $name"
            echo -e "${GRAY}$content${RESET}"
            rx_table_separator
            rx_table_spacer
            ;;

        "blacklist")
            local blacklist=$(get_var "RETRO_WINDOW_BLACKLIST")

            : ${blacklist:="(none)"}

            rx_table_header "󰞵" "Blacklisted Classes"
            rx_table_row "󰍱" "Apps:" "$blacklist" "$PINK" "30"
            rx_table_separator
            rx_table_spacer

            rx_log "info" 'Manage with: retro variable set RETRO_WINDOW_BLACKLIST "app1|app2"'
            ;;

        "edit")
            local rules_file="$RETRO_CACHE/themes/windowrules.conf"
            local editor="${EDITOR:-${RETRO_EDITOR:-nano}}"

            if [[ ! -f $rules_file ]]; then
                rx_log "error" "Rules file not found at $rules_file"
                return 1
            fi

            $editor "$rules_file"

            rx_log "info" "Reloading window rules..."
            bash "$window_core" --apply
            rx_log "success" "Window rules updated and applied."
            ;;

        *)
            rx_help_usage "retro window <command>"
            rx_help_commands "Window Commands"
            rx_help_cmd "fullscreen" "Toggle fullscreen on active window"
            rx_help_cmd "list" "Show all custom window/layer rules"
            rx_help_cmd "add <name> <rule>" "Add named windowrule"
            rx_help_cmd "add-anon <rule>" "Add anonymous windowrule"
            rx_help_cmd "add-layer <name> <rule>" "Add named layerrule"
            rx_help_cmd "add-layer-anon <rule>" "Add anonymous layerrule"
            rx_help_cmd "remove <name>" "Remove rule by name"
            rx_help_cmd "show <name>" "Show rule details"
            rx_help_cmd "apply" "Reload rules without adding"
            rx_help_cmd "edit" "Edit rules file in editor"
            rx_help_cmd "blacklist" "Show blacklisted app classes"
            rx_help_examples
            rx_help_example "retro window add zen-opacity 'match:class = zen, opacity = 1.0 0.8'" "Named windowrule"
            rx_help_example "retro window add-anon 'no_blur on, match:class firefox'" "Anonymous windowrule"
            rx_help_example "retro window add-layer mylayer 'match:namespace = mylayer, blur = on'" "Named layerrule"
            rx_help_example "retro window add-layer-anon 'blur on, match:namespace waybar'" "Anonymous layerrule"
            rx_help_example "retro window edit" 'Edit rules in $EDITOR'
            rx_help_example "retro window fullscreen" "Toggle fullscreen"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "window" "Manage window rules and layer rules" "cmd_wm"
