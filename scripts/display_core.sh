#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/variable.sh"
rx_log_register "display"

_IS_STRING() {
    case "$1" in
        output|mode|position|mirror|cm|icc|sdr_eotf) return 0 ;;
        *) return 1 ;;
    esac
}

_IS_BOOL() {
    case "$1" in
        disabled) return 0 ;;
        *) return 1 ;;
    esac
}

_IS_TABLE() {
    case "$1" in
        reserved_area) return 0 ;;
        *) return 1 ;;
    esac
}

_get_monitors_json() {
    hyprctl -j monitors all 2>/dev/null || echo "[]"
}

_get_monitor_json() {
    local name="$1"
    _get_monitors_json | jq -r --arg n "$name" '.[] | select(.name==$n) // empty'
}

_get_monitor_field() {
    local name="$1"
    local field="$2"
    local json
    json=$(_get_monitor_json "$name")
    [[ -z $json ]] && echo "" && return 1
    echo "$json" | jq -r ".$field" 2>/dev/null || echo ""
}

_get_monitor_config() {
    local name="$1"
    _get_monitors_json | jq -r --arg n "$name" '
        .[] | select(.name==$n) |
        "\(.width)x\(.height)@\((.refreshRate | floor) | tostring),\(.x)x\(.y),\(.scale | tostring)"
    '
}

_cmd_list_monitors() {
    _get_monitors_json | jq -r '.[] | [
        .name,
        .description,
        .make,
        .model,
        (.width | tostring),
        (.height | tostring),
        (.refreshRate | floor | tostring),
        (.x | tostring),
        (.y | tostring),
        (.scale | tostring),
        (.vrr | tostring),
        (.dpmsStatus | tostring),
        (.disabled | tostring),
        (.transform | tostring),
        (.mirrorOf // "none"),
        ((.activeWorkspace.id // 0) | tostring),
        (.activeWorkspace.name // ""),
        (.focused | tostring),
        ((.availableModes | length) | tostring)
    ] | join("|")'
}

_cmd_list_modes() {
    local name="$1"
    local json
    json=$(_get_monitor_json "$name")
    [[ -z $json ]] && echo "ERR_NO_MONITOR" && return 1
    echo "$json" | jq -r '.availableModes[]? // empty' || { echo "ERR_NO_MODES"; return 1; }
}

_cmd_status() {
    local json
    json=$(_get_monitors_json)
    local count
    count=$(echo "$json" | jq 'length')
    echo "monitor_count:$count"
}

_cmd_get() {
    local name="$1"
    local field="$2"
    local val
    val=$(_get_monitor_field "$name" "$field")
    [[ -z $val || $val == "null" ]] && echo "ERR_NO_MONITOR" && return 1
    echo "$val"
}

_cmd_set_resolution() {
    local name="$1"
    local mode="$2"
    [[ -z $name || -z $mode ]] && echo "ERR_ARGS" && return 1

    local config
    config=$(_get_monitor_config "$name")
    [[ -z $config ]] && echo "ERR_NO_MONITOR" && return 1

    local pos_scale="${config#*,}"
    local pos="${pos_scale%,*}"
    local scale="${pos_scale#*,}"

    if [[ $mode != *"@"* ]]; then
        local current_refresh
        current_refresh=$(_get_monitor_field "$name" "refreshRate")
        current_refresh=$(echo "$current_refresh" | cut -d'.' -f1)
        mode="${mode}@${current_refresh}"
    fi

    if ! hyprctl keyword monitor "$name, $mode, $pos, $scale" >/dev/null 2>&1; then
        rx_log_file "error" "Failed to set resolution for $name"
        echo "ERR_SET_FAILED"
        return 1
    fi
    rx_log_file "info" "Set resolution for $name to $mode"
}

_cmd_set_refresh() {
    local name="$1"
    local hz="$2"
    [[ -z $name || -z $hz ]] && echo "ERR_ARGS" && return 1

    local current_res
    current_res=$(_get_monitor_field "$name" "width")
    [[ -z $current_res ]] && echo "ERR_NO_MONITOR" && return 1
    local h_res=$current_res
    current_res=$(_get_monitor_field "$name" "height")
    local v_res=$current_res

    _cmd_set_resolution "$name" "${h_res}x${v_res}@${hz}"
    return $?
}

_cmd_set_scale() {
    local name="$1"
    local scale="$2"
    [[ -z $name || -z $scale ]] && echo "ERR_ARGS" && return 1

    local config
    config=$(_get_monitor_config "$name")
    [[ -z $config ]] && echo "ERR_NO_MONITOR" && return 1

    local mode="${config%%,*}"
    local pos_scale="${config#*,}"
    local pos="${pos_scale%,*}"

    if ! hyprctl keyword monitor "$name, $mode, $pos, $scale" >/dev/null 2>&1; then
        rx_log_file "error" "Failed to set scale for $name"
        echo "ERR_SET_FAILED"
        return 1
    fi
    rx_log_file "info" "Set scale for $name to $scale"
}

_cmd_set_position() {
    local name="$1"
    local pos="$2"
    [[ -z $name || -z $pos ]] && echo "ERR_ARGS" && return 1

    local config
    config=$(_get_monitor_config "$name")
    [[ -z $config ]] && echo "ERR_NO_MONITOR" && return 1

    local mode="${config%%,*}"
    local scale="${config##*,}"

    if ! hyprctl keyword monitor "$name, $mode, $pos, $scale" >/dev/null 2>&1; then
        rx_log_file "error" "Failed to set position for $name"
        echo "ERR_SET_FAILED"
        return 1
    fi
    rx_log_file "info" "Set position for $name to $pos"
}

_cmd_set_dpms() {
    local state="$1"
    local monitor="$2"
    [[ -z $state ]] && echo "ERR_ARGS" && return 1
    [[ $state != "on" && $state != "off" ]] && echo "ERR_INVALID_STATE" && return 1

    if [[ -n $monitor ]]; then
        hyprctl dispatch dpms "$state" "$monitor" >/dev/null 2>&1 || { rx_log_file "error" "Failed to set DPMS $state"; echo "ERR_DPMS_FAILED"; return 1; }
    else
        hyprctl dispatch dpms "$state" >/dev/null 2>&1 || { rx_log_file "error" "Failed to set DPMS $state"; echo "ERR_DPMS_FAILED"; return 1; }
    fi
    rx_log_file "info" "DPMS set to $state${monitor:+ for $monitor}"
}

_cmd_generate_config() {
    local input="$1"
    [[ -z $input ]] && echo "ERR_ARGS" && return 1

    echo "-- Auto-generated by retro display setup"
    echo ""

    IFS='|' read -ra monitors <<< "$input"
    for mon in "${monitors[@]}"; do
        [[ -z $mon ]] && continue

        echo "hl.monitor({"

        IFS=',' read -ra fields <<< "$mon"
        for field in "${fields[@]}"; do
            key="${field%%=*}"
            val="${field#*=}"
            [[ -z $key || -z $val ]] && continue

            if _IS_BOOL "$key"; then
                echo "    $key = $val,"
            elif _IS_STRING "$key"; then
                echo "    $key = \"$val\","
            elif _IS_TABLE "$key"; then
                if [[ $val == *"="* ]]; then
                    echo "    $key = { ${val//=/ = } },"
                else
                    echo "    $key = $val,"
                fi
            else
                echo "    $key = $val,"
            fi
        done

        echo "})"
        echo ""
    done

    echo "hl.monitor({"
    echo "    output = \"\","
    echo "    mode = \"preferred\","
    echo "    position = \"auto\","
    echo "    scale = 1,"
    echo "})"
}

case "$1" in
    "--list-monitors")
        _cmd_list_monitors
        ;;
    "--list-modes")
        _cmd_list_modes "$2"
        ;;
    "--status")
        _cmd_status
        ;;
    "--get")
        _cmd_get "$2" "$3"
        ;;
    "--set-resolution")
        _cmd_set_resolution "$2" "$3"
        ;;
    "--set-refresh")
        _cmd_set_refresh "$2" "$3"
        ;;
    "--set-scale")
        _cmd_set_scale "$2" "$3"
        ;;
    "--set-position")
        _cmd_set_position "$2" "$3"
        ;;
    "--set-dpms")
        _cmd_set_dpms "$2" "$3"
        ;;
    "--generate-config")
        _cmd_generate_config "$2"
        ;;
    *)
        echo "ERR_UNKNOWN_FLAG"
        exit 1
        ;;
esac
