#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "input"

_rx_input_var_name() {
    local key="$1"
    case "$key" in
        layout)           echo "INPUT_KB_LAYOUT" ;;
        variant)          echo "INPUT_KB_VARIANT" ;;
        model)            echo "INPUT_KB_MODEL" ;;
        options)          echo "INPUT_KB_OPTIONS" ;;
        rules)            echo "INPUT_KB_RULES" ;;
        repeat_rate)      echo "INPUT_REPEAT_RATE" ;;
        repeat_delay)     echo "INPUT_REPEAT_DELAY" ;;
        sensitivity)      echo "INPUT_MOUSE_SENSITIVITY" ;;
        accel_profile)    echo "INPUT_MOUSE_ACCEL_PROFILE" ;;
        natural_scroll)   echo "INPUT_TOUCHPAD_NATURAL_SCROLL" ;;
        tap_to_click)     echo "INPUT_TOUCHPAD_TAP_TO_CLICK" ;;
        gesture_fingers)  echo "INPUT_GESTURE_FINGERS" ;;
        gesture_direction) echo "INPUT_GESTURE_DIRECTION" ;;
        gesture_action)   echo "INPUT_GESTURE_ACTION" ;;
        device_name)      echo "INPUT_DEVICE_NAME" ;;
        device_sensitivity) echo "INPUT_DEVICE_SENSITIVITY" ;;
        device_accel)     echo "INPUT_DEVICE_ACCEL_PROFILE" ;;
        *)                echo "" ;;
    esac
}

rx_input_set() {
    local key="$1"
    local value="$2"
    local var_name
    var_name=$(_rx_input_var_name "$key")
    if [[ -z $var_name ]]; then
        return 1
    fi
    set_var "$var_name" "$value"
    rx_input_apply
}

rx_input_set_layout() {
    set_var "INPUT_KB_LAYOUT" "${1:-us}"
    set_var "INPUT_KB_VARIANT" "${2:-}"
    set_var "INPUT_KB_MODEL" "${3:-}"
    set_var "INPUT_KB_OPTIONS" "${4:-}"
    set_var "INPUT_KB_RULES" "${5:-}"
    rx_input_apply
}

rx_input_set_repeat() {
    set_var "INPUT_REPEAT_RATE" "${1:-50}"
    set_var "INPUT_REPEAT_DELAY" "${2:-300}"
    rx_input_apply
}

rx_input_set_mouse() {
    set_var "INPUT_MOUSE_SENSITIVITY" "${1:-0}"
    set_var "INPUT_MOUSE_ACCEL_PROFILE" "${2:-flat}"
    rx_input_apply
}

rx_input_set_touchpad() {
    set_var "INPUT_TOUCHPAD_NATURAL_SCROLL" "${1:-true}"
    set_var "INPUT_TOUCHPAD_TAP_TO_CLICK" "${2:-true}"
    rx_input_apply
}

rx_input_set_gesture() {
    set_var "INPUT_GESTURE_FINGERS" "${1:-3}"
    set_var "INPUT_GESTURE_DIRECTION" "${2:-horizontal}"
    set_var "INPUT_GESTURE_ACTION" "${3:-workspace}"
    rx_input_apply
}

rx_input_set_device() {
    set_var "INPUT_DEVICE_NAME" "${1:-}"
    set_var "INPUT_DEVICE_SENSITIVITY" "${2:-0}"
    set_var "INPUT_DEVICE_ACCEL_PROFILE" "${3:-flat}"
    rx_input_apply
}

rx_input_apply() {
    local helper="$RETRO_DIR/lib/python/input_config.py"
    if [[ ! -f $helper ]]; then
        rx_log_file "error" "Missing input helper: $helper"
        return 1
    fi
    PYTHONPATH="$RETRO_DIR/cmds/tools:$RETRO_DIR/scripts:$RETRO_DIR:$PYTHONPATH" \
        python "$helper" --apply
}

rx_input_status() {
    echo "layout|$(get_var "INPUT_KB_LAYOUT" "us")"
    echo "variant|$(get_var "INPUT_KB_VARIANT" "")"
    echo "model|$(get_var "INPUT_KB_MODEL" "")"
    echo "options|$(get_var "INPUT_KB_OPTIONS" "")"
    echo "rules|$(get_var "INPUT_KB_RULES" "")"
    echo "repeat_rate|$(get_var "INPUT_REPEAT_RATE" "50")"
    echo "repeat_delay|$(get_var "INPUT_REPEAT_DELAY" "300")"
    echo "sensitivity|$(get_var "INPUT_MOUSE_SENSITIVITY" "0")"
    echo "accel_profile|$(get_var "INPUT_MOUSE_ACCEL_PROFILE" "flat")"
    echo "natural_scroll|$(get_var "INPUT_TOUCHPAD_NATURAL_SCROLL" "true")"
    echo "tap_to_click|$(get_var "INPUT_TOUCHPAD_TAP_TO_CLICK" "true")"
    echo "gesture_fingers|$(get_var "INPUT_GESTURE_FINGERS" "3")"
    echo "gesture_direction|$(get_var "INPUT_GESTURE_DIRECTION" "horizontal")"
    echo "gesture_action|$(get_var "INPUT_GESTURE_ACTION" "workspace")"
    echo "device_name|$(get_var "INPUT_DEVICE_NAME" "")"
    echo "device_sensitivity|$(get_var "INPUT_DEVICE_SENSITIVITY" "0")"
    echo "device_accel|$(get_var "INPUT_DEVICE_ACCEL_PROFILE" "flat")"
}

rx_input_get_setup_values() {
    echo "layout=$(get_var "INPUT_KB_LAYOUT" "us")"
    echo "variant=$(get_var "INPUT_KB_VARIANT" "")"
    echo "repeat_rate=$(get_var "INPUT_REPEAT_RATE" "50")"
    echo "repeat_delay=$(get_var "INPUT_REPEAT_DELAY" "300")"
    echo "sensitivity=$(get_var "INPUT_MOUSE_SENSITIVITY" "0")"
    echo "accel_profile=$(get_var "INPUT_MOUSE_ACCEL_PROFILE" "flat")"
    echo "natural_scroll=$(get_var "INPUT_TOUCHPAD_NATURAL_SCROLL" "true")"
    echo "tap_to_click=$(get_var "INPUT_TOUCHPAD_TAP_TO_CLICK" "true")"
    echo "gesture_fingers=$(get_var "INPUT_GESTURE_FINGERS" "3")"
    echo "gesture_direction=$(get_var "INPUT_GESTURE_DIRECTION" "horizontal")"
    echo "gesture_action=$(get_var "INPUT_GESTURE_ACTION" "workspace")"
}

rx_input_keybinds_path() {
    echo "${RETRO_CONFIG:-$HOME/.config/retro}/keybinds.lua"
}

_BINDS_PARSER="$RETRO_DIR/lib/lua/binds_parser.lua"

rx_input_binds_list() {
    local kb_file
    kb_file=$(rx_input_keybinds_path)
    if [[ ! -f $kb_file ]]; then
        return 0
    fi
    lua "$_BINDS_PARSER" "$kb_file"
}

rx_input_binds_check() {
    local target_key="$1"
    local kb_file
    kb_file=$(rx_input_keybinds_path)
    if [[ ! -f $kb_file ]]; then
        return 1
    fi
    lua "$_BINDS_PARSER" "$kb_file" | while IFS='|' read -r line key type value flags; do
        [[ -z $line ]] && continue
        if [[ $key == "$target_key" ]]; then
            echo "$line|$key|$type|$value|$flags"
            return 0
        fi
    done
}

rx_input_binds_check_any() {
    local target_key="$1"
    local result
    result=$(rx_input_binds_check "$target_key")
    if [[ -n $result ]]; then
        echo "$result"
        return 0
    fi
    # Also check settings.lua for existing keybinds
    local settings_file="${RETRO_CONFIG:-$HOME/.config/retro}/settings.lua"
    if [[ -f $settings_file ]]; then
        local found
        found=$(lua "$_BINDS_PARSER" "$settings_file" 2>/dev/null | while IFS='|' read -r line key type value flags; do
            [[ -z $line ]] && continue
            if [[ $key == "$target_key" ]]; then
                echo "$line|$key|$type|$value|$flags"
                return 0
            fi
        done)
        if [[ -n $found ]]; then
            echo "$found"
            return 0
        fi
    fi
    return 1
}

rx_input_binds_add() {
    local key="$1"
    local action_spec="$2"
    local kb_file
    kb_file=$(rx_input_keybinds_path)
    mkdir -p "$(dirname "$kb_file")"

    if [[ ! -f $kb_file ]]; then
        cat > "$kb_file" << 'KBEOF'
-- Generated by Retro Settings

-- Keybinds
KBEOF
    fi

    local existing
    existing=$(rx_input_binds_check_any "$key")

    local action_type="${action_spec%%:*}"
    local action_value="${action_spec#*:}"

    local lua_line=""
    case "$action_type" in
        exec)
            lua_line="hl.bind(\"${key}\", hl.dsp.exec_cmd(\"${action_value}\"))"
            ;;
        dispatch)
            lua_line="hl.bind(\"${key}\", hl.dsp.${action_value})"
            ;;
        func)
            lua_line="hl.bind(\"${key}\", Retro.${action_value})"
            ;;
        *)
            echo "ERROR|invalid_action_type"
            return 1
            ;;
    esac

    {
        echo ""
        echo "-- user added"
        if [[ -n $existing ]]; then
            echo "hl.unbind(\"${key}\")"
        fi
        echo "${lua_line}"
    } >> "$kb_file"

    if [[ -n $existing ]]; then
        echo "REPLACED|${key}|${action_type}|${action_value}"
    else
        echo "ADDED|${key}|${action_type}|${action_value}"
    fi
}

rx_input_binds_remove() {
    local target_key="$1"
    local kb_file
    kb_file=$(rx_input_keybinds_path)

    if [[ ! -f $kb_file ]]; then
        echo "ERROR|no_keybinds_file"
        return 1
    fi

    local target_lines
    target_lines=$(lua "$_BINDS_PARSER" "$kb_file" | while IFS='|' read -r line key type value flags; do
        [[ -z $line ]] && continue
        if [[ $key == "$target_key" ]]; then
            echo "$line"
        fi
    done)

    if [[ -z $target_lines ]]; then
        echo "NOT_FOUND|${target_key}"
        return 1
    fi

    local lines_to_remove=()
    while IFS= read -r l; do
        [[ -n $l ]] && lines_to_remove+=("$l")
    done <<< "$target_lines"

    local tmp_file
    tmp_file=$(mktemp)
    local line_num=0
    local removed=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        local skip=false
        for rl in "${lines_to_remove[@]}"; do
            if [[ $line_num -eq $rl ]]; then
                skip=true
                removed=$((removed + 1))
                break
            fi
        done
        if [[ $skip == false ]]; then
            echo "$line" >> "$tmp_file"
        fi
    done < "$kb_file"

    mv "$tmp_file" "$kb_file"
    echo "OK|${target_key}|removed=${removed}"
}

case "$1" in
    "--set")
        rx_input_set "$2" "$3"
        ;;
    "--set-layout")
        rx_input_set_layout "$2" "$3" "$4" "$5" "$6"
        ;;
    "--set-repeat")
        rx_input_set_repeat "$2" "$3"
        ;;
    "--set-mouse")
        rx_input_set_mouse "$2" "$3"
        ;;
    "--set-touchpad")
        rx_input_set_touchpad "$2" "$3"
        ;;
    "--set-gesture")
        rx_input_set_gesture "$2" "$3" "$4"
        ;;
    "--set-device")
        rx_input_set_device "$2" "$3" "$4"
        ;;
    "--apply")
        rx_input_apply
        echo "OK"
        ;;
    "--status")
        rx_input_status
        ;;
    "--setup-get")
        rx_input_get_setup_values
        ;;
    "--keybinds-path")
        rx_input_keybinds_path
        ;;
    "--binds-list")
        rx_input_binds_list
        ;;
    "--binds-check")
        rx_input_binds_check "$2"
        ;;
    "--binds-add")
        rx_input_binds_add "$2" "$3"
        ;;
    "--binds-remove")
        rx_input_binds_remove "$2"
        ;;
esac
