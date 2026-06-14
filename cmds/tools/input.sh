#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/menu.sh"
source "$RETRO_DIR/lib/setup.sh"

_INPUT_CORE="$RETRO_DIR/scripts/input_core.sh"

_input_call() {
    bash "$_INPUT_CORE" "$@"
}

_input_set() {
    local key="$1"
    local value="$2"
    if _input_call "--set" "$key" "$value"; then
        rx_log "success" "${PINK}$key${RESET} set to ${PINK}$value${RESET}"
    else
        rx_log "error" "Failed to set ${PINK}$key${RESET}"
        return 1
    fi
}

cmd_input() {
    local action="${1,,}"
    shift

    case "$action" in
        "status")
            _status_line() {
                local icon="$1" label="$2" value="$3"
                printf " ${PINK}%s${RESET} %-22s ${PINK}%s${RESET}\n" "$icon" "$label" "$value"
            }

            local layout variant repeat_rate repeat_delay
            local sensitivity accel_profile
            local natural_scroll tap_to_click
            local gesture_fingers gesture_direction gesture_action
            local device_name device_sensitivity

            layout=$(get_var "INPUT_KB_LAYOUT" "us")
            variant=$(get_var "INPUT_KB_VARIANT" "")
            repeat_rate=$(get_var "INPUT_REPEAT_RATE" "50")
            repeat_delay=$(get_var "INPUT_REPEAT_DELAY" "300")
            sensitivity=$(get_var "INPUT_MOUSE_SENSITIVITY" "0")
            accel_profile=$(get_var "INPUT_MOUSE_ACCEL_PROFILE" "flat")
            natural_scroll=$(get_var "INPUT_TOUCHPAD_NATURAL_SCROLL" "true")
            tap_to_click=$(get_var "INPUT_TOUCHPAD_TAP_TO_CLICK" "true")
            gesture_fingers=$(get_var "INPUT_GESTURE_FINGERS" "3")
            gesture_direction=$(get_var "INPUT_GESTURE_DIRECTION" "horizontal")
            gesture_action=$(get_var "INPUT_GESTURE_ACTION" "workspace")
            device_name=$(get_var "INPUT_DEVICE_NAME" "")
            device_sensitivity=$(get_var "INPUT_DEVICE_SENSITIVITY" "0")

            echo -e "\n ${PINK}󰌌 Input Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────${RESET}"

            local variant_display=""
            [[ -n $variant ]] && variant_display=" / variant: $variant"
            _status_line "󰌌" "Keyboard:" "${layout}${variant_display}  ${repeat_rate}rps/${repeat_delay}ms"

            _status_line "󰈟" "Mouse:" "${sensitivity} sens / ${accel_profile}"

            local scroll_icon tap_icon
            [[ $natural_scroll == "true" ]] && scroll_icon="${SUCCESS}✓" || scroll_icon="${MUTE}○"
            [[ $tap_to_click == "true" ]] && tap_icon="${SUCCESS}✓" || tap_icon="${MUTE}○"
            _status_line "󰒋" "Touchpad:" "natural scroll ${scroll_icon} / tap-to-click ${tap_icon}"

            if [[ -n $gesture_fingers && $gesture_fingers != "0" ]]; then
                _status_line "󰋜" "Gestures:" "${gesture_fingers}-finger ${gesture_direction} → ${gesture_action}"
            fi

            if [[ -n $device_name ]]; then
                _status_line "󰄾" "Per-Device:" "${device_name} (sens: ${device_sensitivity})"
            fi

            local keybinds_file
            keybinds_file=$(_input_call "--keybinds-path")
            if [[ -f $keybinds_file ]]; then
                local bind_count
                bind_count=$(grep -c 'hl.bind(' "$keybinds_file" 2>/dev/null || echo 0)
                _status_line "󰐧" "Keybinds:" "${bind_count} active (edit: ${PINK}retro input keybinds edit${RESET})"
            fi

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────${RESET}"
            ;;

        "layout")
            local new_layout="${1:-}"
            local new_variant="${2:-}"
            local new_model="${3:-}"
            local new_options="${4:-}"
            local new_rules="${5:-}"

            if [[ -z $new_layout ]]; then
                rx_log "error" "Usage: retro input layout <layout> [variant] [model] [options] [rules]"
                rx_log "info" "Example: retro input layout us"
                rx_log "info" "Example: retro input layout de nodeadkeys"
                return 1
            fi

            _input_call "--set-layout" "$new_layout" "$new_variant" "$new_model" "$new_options" "$new_rules"
            rx_log "success" "Keyboard layout set to ${PINK}$new_layout${RESET}"
            ;;

        "repeat")
            local new_rate="${1:-}"
            local new_delay="${2:-}"

            if [[ -z $new_rate ]]; then
                rx_log "error" "Usage: retro input repeat <rate> [delay]"
                rx_log "info" "Example: retro input repeat 50 300"
                return 1
            fi

            _input_call "--set-repeat" "$new_rate" "$new_delay"
            rx_log "success" "Repeat rate set to ${PINK}$new_rate${RESET} keys/sec, delay ${PINK}${new_delay:-300}${RESET}ms"
            ;;

        "mouse")
            local new_sensitivity="${1:-}"
            local new_profile="${2:-}"

            if [[ -z $new_sensitivity ]]; then
                rx_log "error" "Usage: retro input mouse <sensitivity> [accel_profile]"
                rx_log "info" "Example: retro input mouse 0.5 flat"
                rx_log "info" "sensitivity: -1.0 to 1.0, accel_profile: flat|adaptive"
                return 1
            fi

            _input_call "--set-mouse" "$new_sensitivity" "$new_profile"
            rx_log "success" "Mouse sensitivity set to ${PINK}$new_sensitivity${RESET}, accel ${PINK}${new_profile:-flat}${RESET}"
            ;;

        "touchpad")
            local new_natural="${1:-}"
            local new_tap="${2:-}"

            if [[ -z $new_natural ]]; then
                rx_log "error" "Usage: retro input touchpad <natural_scroll> [tap_to_click]"
                rx_log "info" "Example: retro input touchpad true true"
                rx_log "info" "Values: true|false"
                return 1
            fi

            _input_call "--set-touchpad" "$new_natural" "$new_tap"
            rx_log "success" "Touchpad: natural_scroll=${PINK}$new_natural${RESET}, tap_to_click=${PINK}${new_tap:-true}${RESET}"
            ;;

        "gesture")
            local new_fingers="${1:-}"
            local new_direction="${2:-}"
            local new_action="${3:-}"

            if [[ -z $new_fingers ]]; then
                rx_log "error" "Usage: retro input gesture <fingers> <direction> <action>"
                rx_log "info" "Example: retro input gesture 3 horizontal workspace"
                rx_log "info" "Directions: horizontal, vertical"
                rx_log "info" "Actions: workspace, exec:<command>"
                return 1
            fi

            case "$new_direction" in
                horizontal|vertical) ;;
                "")
                    rx_log "error" "Direction is required (horizontal or vertical)"
                    return 1
                    ;;
                *)
                    rx_log "error" "Invalid direction '${PINK}$new_direction${RESET}' — must be horizontal or vertical"
                    return 1
                    ;;
            esac

            case "$new_action" in
                workspace) ;;
                exec:*) ;;
                "")
                    rx_log "error" "Action is required (workspace or exec:<command>)"
                    return 1
                    ;;
                *)
                    rx_log "error" "Invalid action '${PINK}$new_action${RESET}' — must be 'workspace' or 'exec:<command>'"
                    return 1
                    ;;
            esac

            _input_call "--set-gesture" "$new_fingers" "$new_direction" "$new_action"
            rx_log "success" "Gesture: ${PINK}$new_fingers${RESET}-finger ${PINK}$new_direction${RESET} → ${PINK}$new_action${RESET}"
            ;;

        "device")
            local subcmd="${1:-}"
            shift

            case "$subcmd" in
                "list")
                    rx_log "info" "Detected input devices not available in offline mode"
                    rx_log "info" "Set per-device config with: retro input device <name> [sensitivity] [accel]"
                    ;;
                *)
                    if [[ -z $subcmd ]]; then
                        rx_log "error" "Usage: retro input device <name> [sensitivity] [accel_profile]"
                        rx_log "error" "       retro input device list"
                        return 1
                    fi
                    local dev_sens="${1:-0}"
                    local dev_accel="${2:-flat}"
                    _input_call "--set-device" "$subcmd" "$dev_sens" "$dev_accel"
                    rx_log "success" "Device ${PINK}$subcmd${RESET}: sensitivity=${PINK}$dev_sens${RESET}, accel=${PINK}$dev_accel${RESET}"
                    ;;
            esac
            ;;

        "keybinds")
            local keybinds_cmd="${1,,}"
            shift 2>/dev/null || true

            case "$keybinds_cmd" in
                "list")
                    local keybinds_file
                    keybinds_file=$(_input_call "--keybinds-path")
                    if [[ ! -f $keybinds_file ]]; then
                        rx_log "warn" "No keybinds config found. Run ${PINK}retro input keybinds reset${RESET} first"
                        return 1
                    fi
                    rx_log "info" "Keybinds file: ${PINK}$keybinds_file${RESET}"
                    if command -v bat >/dev/null 2>&1; then
                        bat -l lua "$keybinds_file"
                    else
                        cat "$keybinds_file"
                    fi
                    ;;
                "edit")
                    local keybinds_file
                    keybinds_file=$(_input_call "--keybinds-path")
                    if [[ ! -f $keybinds_file ]]; then
                        rx_log "warn" "No keybinds config yet. Run ${PINK}retro input keybinds reset${RESET} first"
                        return 1
                    fi
                    local editor="${EDITOR:-nvim}"
                    rx_log "info" "Opening ${PINK}$keybinds_file${RESET} with ${PINK}$editor${RESET}"
                    $editor "$keybinds_file"
                    ;;
                "reset")
                    if _input_call "--keybinds-reset"; then
                        rx_log "success" "Keybinds reset to module defaults"
                    else
                        rx_log "error" "Failed to reset keybinds — module template not found"
                    fi
                    ;;
                *)
                    rx_log "error" "Usage: retro input keybinds {list|edit|reset}"
                    return 1
                    ;;
            esac
            ;;

        "setup")
            rx_setup_parse "$@"

            local input_exists=false
            [[ $(get_var "INPUT_KB_LAYOUT" "") != "" ]] && input_exists=true
            rx_setup_check_needed "$input_exists" && return 0

            if [[ $RX_SETUP_YES == "true" || $SKIP_PROMPT == "true" ]]; then
                local def_layout def_variant def_rate def_delay def_sens def_profile
                local def_natural def_tap def_fingers def_direction def_action
                def_layout=$(get_var "INPUT_KB_LAYOUT" "us")
                def_variant=$(get_var "INPUT_KB_VARIANT" "")
                def_rate=$(get_var "INPUT_REPEAT_RATE" "50")
                def_delay=$(get_var "INPUT_REPEAT_DELAY" "300")
                def_sens=$(get_var "INPUT_MOUSE_SENSITIVITY" "0")
                def_profile=$(get_var "INPUT_MOUSE_ACCEL_PROFILE" "flat")
                def_natural=$(get_var "INPUT_TOUCHPAD_NATURAL_SCROLL" "true")
                def_tap=$(get_var "INPUT_TOUCHPAD_TAP_TO_CLICK" "true")
                def_fingers=$(get_var "INPUT_GESTURE_FINGERS" "3")
                def_direction=$(get_var "INPUT_GESTURE_DIRECTION" "horizontal")
                def_action=$(get_var "INPUT_GESTURE_ACTION" "workspace")

                _input_call "--set-layout" "$def_layout" "$def_variant"
                _input_call "--set-repeat" "$def_rate" "$def_delay"
                _input_call "--set-mouse" "$def_sens" "$def_profile"
                _input_call "--set-touchpad" "$def_natural" "$def_tap"
                _input_call "--set-gesture" "$def_fingers" "$def_direction" "$def_action"
                rx_log "success" "Input configuration applied with current defaults"
                return 0
            fi

            local new_layout new_variant new_rate new_delay
            local new_sens new_profile new_natural new_tap
            local new_fingers new_direction new_action

            new_layout=$(rx_input "Keyboard layout" "$(get_var "INPUT_KB_LAYOUT" "us")" \
                '^[a-z][a-z0-9_-]*$' "Must be a layout code (e.g. us, de, fr)")
            new_variant=$(rx_input "Keyboard variant (optional)" "$(get_var "INPUT_KB_VARIANT" "")")

            new_rate=$(rx_input_numeric "Repeat rate (keys/sec)" "$(get_var "INPUT_REPEAT_RATE" "50")" 10 200)
            new_delay=$(rx_input_numeric "Repeat delay (ms)" "$(get_var "INPUT_REPEAT_DELAY" "300")" 100 1000)

            new_sens=$(rx_input "Mouse sensitivity (-1.0 to 1.0)" "$(get_var "INPUT_MOUSE_SENSITIVITY" "0")" \
                '^-?[0-9]+(\.[0-9]+)?$' "Must be a number between -1.0 and 1.0")
            new_profile=$(rx_input "Accel profile (flat|adaptive)" "$(get_var "INPUT_MOUSE_ACCEL_PROFILE" "flat")" \
                '^(flat|adaptive)$' "Must be flat or adaptive")

            [[ $(get_var "INPUT_TOUCHPAD_NATURAL_SCROLL" "true") == "true" ]] && ns_default="yes" || ns_default="no"
            rx_confirm "Enable natural scroll?" "$ns_default" && new_natural="true" || new_natural="false"

            [[ $(get_var "INPUT_TOUCHPAD_TAP_TO_CLICK" "true") == "true" ]] && tt_default="yes" || tt_default="no"
            rx_confirm "Enable tap-to-click?" "$tt_default" && new_tap="true" || new_tap="false"

            rx_confirm "Configure trackpad gestures?" "N"
            if [[ $? -eq 0 ]]; then
                new_fingers=$(rx_input_numeric "Gesture finger count" "$(get_var "INPUT_GESTURE_FINGERS" "3")" 2 4)
                new_direction=$(rx_input "Gesture direction (horizontal|vertical)" "$(get_var "INPUT_GESTURE_DIRECTION" "horizontal")" \
                    '^(horizontal|vertical)$' "Must be horizontal or vertical")
                new_action=$(rx_input "Gesture action (workspace or exec:<cmd>)" "$(get_var "INPUT_GESTURE_ACTION" "workspace")")
            else
                new_fingers="0"
                new_direction=""
                new_action=""
            fi

            rx_setup_summary "󰌌" "Input Configuration Summary" \
                "Keyboard Layout" "$new_layout${new_variant:+ ($new_variant)}" \
                "Repeat Rate/Delay" "${new_rate}rps / ${new_delay}ms" \
                "Mouse" "${new_sens} sens / ${new_profile}" \
                "Touchpad" "natural: $new_natural / tap: $new_tap" \
                "Gestures" "${new_fingers}-finger ${new_direction} → ${new_action}"

            rx_setup_confirm || return 0

            _input_call "--set-layout" "$new_layout" "$new_variant"
            _input_call "--set-repeat" "$new_rate" "$new_delay"
            _input_call "--set-mouse" "$new_sens" "$new_profile"
            _input_call "--set-touchpad" "$new_natural" "$new_tap"
            if [[ $new_fingers != "0" ]]; then
                _input_call "--set-gesture" "$new_fingers" "$new_direction" "$new_action"
            fi

            rx_setup_success "󰌌" "Input Configured" \
                "Keyboard Layout" "$new_layout${new_variant:+ ($new_variant)}" \
                "Repeat Rate/Delay" "${new_rate}rps / ${new_delay}ms" \
                "Mouse" "${new_sens} sens / ${new_profile}" \
                "Touchpad" "natural: $new_natural / tap: $new_tap"
            ;;

        "binds")
            local binds_cmd="${1,,}"
            shift 2>/dev/null || true

            case "$binds_cmd" in
                "list")
                    local data
                    data=$(_input_call "--binds-list" 2>/dev/null)
                    if [[ -z $data ]]; then
                        rx_log "warn" "No keybinds file found. Run ${PINK}retro input keybinds reset${RESET} first"
                        return 1
                    fi

                    local count=0
                    echo -e "\n ${PINK}󰐧 Keybinds${RESET}"
                    echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────────────────────────────────────${RESET}"

                    while IFS='|' read -r line key type value flags; do
                        [[ -z $line ]] && continue
                        count=$((count + 1))

                        local action_icon="󰇝"
                        case "$type" in
                            exec)   action_icon="󰄧" ;;
                            function) action_icon="󰊕" ;;
                            dispatch) action_icon="󰄾" ;;
                        esac

                        local display_value="$value"
                        if [[ ${#display_value} -gt 50 ]]; then
                            display_value="${display_value:0:47}..."
                        fi

                        printf " ${PINK}%s${RESET} %-20s ${PINK}%-10s${RESET} %s\n" \
                            "$action_icon" "$key" "$type" "$display_value"
                    done <<< "$data"

                    echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────────────────────────────────────${RESET}"
                    echo -e " ${PINK}󰐧${RESET} ${PINK}${count}${RESET} keybinds total"
                    ;;

                "add")
                    local new_key="${1:-}"
                    local new_action="${2:-}"

                    if [[ -z $new_key || -z $new_action ]]; then
                        rx_log "error" "Usage: retro input binds add <key> <action_type>:<action_value>"
                        rx_log "info" "Examples:"
                        rx_log "info" "  retro input binds add \"SUPER + B\" exec:firefox"
                        rx_log "info" "  retro input binds add \"SUPER + SHIFT + Q\" dispatch:window.close"
                        rx_log "info" "  retro input binds add \"SUPER + SPACE\" func:open_terminal"
                        return 1
                    fi

                    if [[ $new_action != *:* ]]; then
                        rx_log "error" "Action must be in format ${PINK}type:value${RESET}"
                        rx_log "info" "Types: exec:, dispatch:, func:"
                        return 1
                    fi

                    local result
                    result=$(_input_call "--binds-add" "$new_key" "$new_action")
                    local status=$?

                    if [[ $status -eq 0 ]]; then
                        rx_log "success" "Keybind added: ${PINK}$new_key${RESET} → ${PINK}$new_action${RESET}"
                    elif echo "$result" | grep -q "^DUPLICATE"; then
                        local existing_info
                        existing_info=$(echo "$result" | cut -d'|' -f3-)
                        rx_log "error" "Duplicate key: ${PINK}$new_key${RESET} already bound to:"
                        rx_log "info" "  ${PINK}$existing_info${RESET}"
                    else
                        rx_log "error" "Failed to add keybind"
                    fi
                    ;;

                "remove")
                    local target_key="${1:-}"

                    if [[ -z $target_key ]]; then
                        rx_log "error" "Usage: retro input binds remove <key>"
                        rx_log "info" "Example: retro input binds remove \"SUPER + Z\""
                        return 1
                    fi

                    local result
                    result=$(_input_call "--binds-remove" "$target_key")
                    local status=$?

                    if [[ $status -eq 0 ]]; then
                        local removed_count
                        removed_count=$(echo "$result" | grep -oP 'removed=\K\d+')
                        rx_log "success" "Removed ${PINK}$removed_count${RESET} bind(s) for ${PINK}$target_key${RESET}"
                    elif echo "$result" | grep -q "^NOT_FOUND"; then
                        rx_log "error" "Keybind not found: ${PINK}$target_key${RESET}"
                    else
                        rx_log "error" "Failed to remove keybind"
                    fi
                    ;;

                "find")
                    local term="${1:-}"
                    if [[ -z $term ]]; then
                        rx_log "error" "Usage: retro input binds find <term>"
                        return 1
                    fi

                    local data
                    data=$(_input_call "--binds-list" 2>/dev/null)
                    if [[ -z $data ]]; then
                        rx_log "warn" "No keybinds file found"
                        return 1
                    fi

                    local matches=0
                    while IFS='|' read -r line key type value flags; do
                        [[ -z $line ]] && continue
                        if echo "$key|$type|$value" | grep -qi "$term"; then
                            matches=$((matches + 1))
                            [[ $matches -eq 1 ]] && echo -e "\n ${PINK}󰐧 Find: ${term}${RESET}"
                            printf "  ${PINK}%-22s${RESET} ${MUTE}%-12s${RESET} %s\n" "$key" "$type" "$value"
                        fi
                    done <<< "$data"

                    if [[ $matches -eq 0 ]]; then
                        rx_log "info" "No binds matching ${PINK}$term${RESET}"
                    else
                        echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────${RESET}"
                    fi
                    ;;

                "export")
                    local data
                    data=$(_input_call "--binds-list" 2>/dev/null)
                    if [[ -z $data ]]; then
                        rx_log "error" "No keybinds file found"
                        return 1
                    fi
                    echo "$data"
                    ;;

                *)
                    rx_log "error" "Usage: retro input binds {list|add|remove|find|export}"
                    return 1
                    ;;
            esac
            ;;

        *)
            rx_help_usage "retro input <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show current input configuration"
            rx_help_cmd "setup [--yes|-y]" "Interactive input setup wizard"
            rx_help_cmd "layout <layout> [variant]" "Set keyboard layout"
            rx_help_cmd "repeat <rate> [delay]" "Set repeat rate (keys/sec) and delay (ms)"
            rx_help_cmd "mouse <sensitivity> [profile]" "Set mouse sensitivity (-1.0 to 1.0) and accel profile"
            rx_help_cmd "touchpad <natural> [tap]" "Set touchpad natural scroll and tap-to-click"
            rx_help_cmd "gesture <f> <dir> <action>" "Set trackpad gesture binding"
            rx_help_cmd "device <name> [sens] [accel]" "Set per-device input config"
            rx_help_cmd "keybinds {list|edit|reset}" "Manage keybinds config file"
            rx_help_cmd "binds {list|add|remove|find|export}" "Manage individual keybinds"
            rx_help_examples
            rx_help_example "retro input status" "Show current input settings"
            rx_help_example "retro input layout de" "Set keyboard to German layout"
            rx_help_example "retro input repeat 50 300" "Set repeat rate 50rps, delay 300ms"
            rx_help_example "retro input mouse 0.5 adaptive" "Set mouse sensitivity"
            rx_help_example "retro input gesture 3 horizontal workspace" "3-finger swipe to switch workspaces"
            rx_help_example "retro input binds list" "List all keybinds"
            rx_help_example "retro input binds add \"SUPER + B\" exec:firefox" "Add a keybind"
            rx_help_example "retro input binds remove \"SUPER + Z\"" "Remove a keybind"
            rx_help_example "retro input binds find SUPER" "Search keybinds"
            rx_help_example "retro input keybinds edit" "Edit keybinds in \$EDITOR"
            rx_help_example "retro input keybinds reset" "Reset keybinds to defaults"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "input|i" "Manage input devices, keybinds, and gestures" "cmd_input"
