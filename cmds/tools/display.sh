#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_display() {
    local display_core="$RETRO_DIR/scripts/display_core.sh"
    local action="${1,,}"
    local arg1="$2"
    local arg2="$3"
    local arg3="$4"

    case "$action" in
        "status")
            _display_status "$display_core"
            ;;
        "list" | "ls")
            _display_list "$display_core"
            ;;
        "modes" | "available")
            [[ -z $arg1 ]] && rx_log "error" "Usage: retro display modes <monitor>" && return 1
            _display_modes "$display_core" "$arg1"
            ;;
        "resolution" | "res")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display resolution <monitor> [wxh@hz]" && return 1
            fi
            if [[ -n $arg2 ]]; then
                _display_set_resolution "$display_core" "$arg1" "$arg2"
            else
                _display_get_resolution "$display_core" "$arg1"
            fi
            ;;
        "refresh" | "hz")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display refresh <monitor> [hz]" && return 1
            fi
            if [[ -n $arg2 ]]; then
                _display_set_refresh "$display_core" "$arg1" "$arg2"
            else
                _display_get_refresh "$display_core" "$arg1"
            fi
            ;;
        "scale")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display scale <monitor> [factor]" && return 1
            fi
            if [[ -n $arg2 ]]; then
                _display_set_scale "$display_core" "$arg1" "$arg2"
            else
                _display_get_scale "$display_core" "$arg1"
            fi
            ;;
        "position" | "pos")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display position <monitor> [x y]" && return 1
            fi
            if [[ -n $arg2 && -n $arg3 ]]; then
                _display_set_position "$display_core" "$arg1" "${arg2}x${arg3}"
            elif [[ -n $arg2 ]]; then
                _display_set_position "$display_core" "$arg1" "$arg2"
            else
                _display_get_position "$display_core" "$arg1"
            fi
            ;;
        "vrr")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display vrr <monitor> [on|off|adaptive]" && return 1
            fi
            if [[ -n $arg2 ]]; then
                _display_set_vrr "$display_core" "$arg1" "$arg2"
            else
                _display_get_vrr "$display_core" "$arg1"
            fi
            ;;
        "dpms")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display dpms <on|off>" && return 1
            fi
            _display_set_dpms "$display_core" "$arg1" "$arg2"
            ;;
        "brightness" | "br")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display brightness <monitor>" && return 1
            fi
            _display_get_brightness "$display_core" "$arg1"
            ;;
        "saturation" | "sat")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display saturation <monitor>" && return 1
            fi
            _display_get_saturation "$display_core" "$arg1"
            ;;
        "enable" | "on")
            [[ -z $arg1 ]] && rx_log "error" "Usage: retro display enable <monitor>" && return 1
            _display_set_enable "$display_core" "$arg1"
            ;;
        "disable" | "off")
            [[ -z $arg1 ]] && rx_log "error" "Usage: retro display disable <monitor>" && return 1
            _display_set_disable "$display_core" "$arg1"
            ;;
        "mirror")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display mirror <source> [target]" && return 1
            fi
            _display_set_mirror "$display_core" "$arg1" "$arg2"
            ;;
        "transform" | "rot")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display transform <monitor>" && return 1
            fi
            _display_get_transform "$display_core" "$arg1"
            ;;
        "bitdepth" | "bpc")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display bitdepth <monitor>" && return 1
            fi
            _display_get_bitdepth "$display_core" "$arg1"
            ;;
        "cm" | "colormanagement")
            if [[ -z $arg1 ]]; then
                rx_log "error" "Usage: retro display cm <monitor>" && return 1
            fi
            _display_get_cm "$display_core" "$arg1"
            ;;
        "setup")
            _display_setup "$display_core"
            ;;
        "help" | "")
            rx_help_usage "retro display <command> [args...]"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show all monitors status" 26
            rx_help_cmd "list" "List monitor names" 26
            rx_help_cmd "modes <mon>" "List available modes for a monitor" 26
            rx_help_cmd "resolution <mon> [wxh@hz]" "Get or set resolution" 26
            rx_help_cmd "refresh <mon> [hz]" "Get or set refresh rate" 26
            rx_help_cmd "scale <mon> [factor]" "Get or set scale" 26
            rx_help_cmd "position <mon> [x y]" "Get or set position" 26
            rx_help_cmd "vrr <mon> [on|off|adaptive]" "Get or set VRR" 26
            rx_help_cmd "dpms <on|off>" "Toggle display power saving" 26
            rx_help_cmd "enable <mon>" "Enable a disabled monitor" 26
            rx_help_cmd "disable <mon>" "Disable a monitor" 26
            rx_help_cmd "mirror <src> [dst]" "Mirror a monitor" 26
            rx_help_cmd "brightness <mon>" "Show SDR brightness" 26
            rx_help_cmd "saturation <mon>" "Show SDR saturation" 26
            rx_help_cmd "transform <mon>" "Show rotation" 26
            rx_help_cmd "bitdepth <mon>" "Show color depth" 26
            rx_help_cmd "cm <mon>" "Show color management" 26
            rx_help_cmd "setup" "Interactive monitor configuration" 26
            rx_help_examples
            rx_help_example "retro display status" "Show monitor overview" 26
            rx_help_example "retro display res DP-1 1920x1080@144" "Set resolution" 26
            rx_help_example "retro display hz eDP-1 60" "Set refresh rate" 26
            rx_help_example "retro display scale eDP-1 1.5" "Set scaling" 26
            rx_help_example "retro display pos HDMI-A-1 1920 0" "Set position" 26
            rx_help_example "retro display dpms off" "Turn off monitors" 26
            rx_help_example "retro display setup" "Interactive config" 26
            rx_help_spacer
            ;;
        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}

_display_status() {
    local core="$1"
    local raw
    raw=$(bash "$core" --list-monitors)
    [[ -z $raw ]] && rx_log "info" "No monitors detected" && return 0

    rx_table_header "󰍹" "Display Status"

    local first=true
    # shellcheck disable=SC2034
    while IFS='|' read -r name desc make model w h refresh_x x y scale vrr dpms disabled _tr _mirror_of _ws_id ws_name _focused _mc; do
        [[ -z $name ]] && continue

        if $first; then
            first=false
        else
            rx_table_separator
        fi

        local res_display="${w}x${h}"
        local hz_display="${refresh_x}Hz"
        local pos_display="${x}x${y}"
        local scale_display="$scale"

        local vrr_color="$MUTE"
        local vrr_display="○ Off"
        [[ $vrr == "true" ]] && vrr_color="$SUCCESS" && vrr_display="● On"
        [[ $vrr == "2" ]] || [[ $vrr == "adaptive" ]] && vrr_color="$WARN" && vrr_display="○ Adaptive"

        local dpms_color="$SUCCESS"
        local dpms_display="● On"
        [[ $dpms == "false" ]] && dpms_color="$MUTE" && dpms_display="○ Off"

        local status_color="$SUCCESS"
        local status_display="● Active"
        [[ $disabled == "true" ]] && status_color="$ERROR" && status_display="○ Disabled"

        rx_table_row "󰍹" "Monitor:" "$name ($desc)" "$PINK" "16"
        rx_table_row_gray "󰐓" "Make/Model:" "$make $model" "16"
        rx_table_row "󰩺" "Resolution:" "$res_display" "$PINK" "16"
        rx_table_row "" "Refresh:" "$hz_display" "$PINK" "16"
        rx_table_row "󰘶" "Position:" "$pos_display" "$GRAY" "16"
        rx_table_row "󰧑" "Scale:" "$scale_display" "$GRAY" "16"
        rx_table_row "󰑪" "VRR:" "$vrr_display" "$vrr_color" "16"
        rx_table_row "󰤇" "DPMS:" "$dpms_display" "$dpms_color" "16"
        rx_table_row "󰙀" "Workspace:" "$ws_name" "$GRAY" "16"
        rx_table_row "󰪥" "Status:" "$status_display" "$status_color" "16"

        if [[ $_mirror_of != "none" ]]; then
            rx_table_row_gray "󰛐" "Mirror of:" "$_mirror_of" "16"
        fi
    done <<<"$raw"

    rx_table_separator
    rx_table_spacer
}

_display_list() {
    local core="$1"
    local raw
    raw=$(bash "$core" --list-monitors)
    [[ -z $raw ]] && rx_log "info" "No monitors detected" && return 0

    rx_table_header "󰍹" "Connected Monitors"

    # shellcheck disable=SC2034
    while IFS='|' read -r name desc _ _ _ _ _ _ _ _ _ _ disabled _ _ _ _ _ _; do
        [[ -z $name ]] && continue

        local status_color="$SUCCESS"
        local status_icon="󰄹"
        [[ $disabled == "true" ]] && status_color="$MUTE" && status_icon="󰄰"

        rx_table_row "$status_icon" "$name" "$desc" "$status_color" "24"
    done <<<"$raw"

    rx_table_separator
    rx_table_spacer
}

_display_modes() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --list-modes "$monitor")
    [[ $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ $raw == ERR_NO_MODES ]] && rx_log "error" "No modes available for $monitor" && return 1
    [[ -z $raw ]] && rx_log "error" "No modes available for $monitor" && return 1

    rx_table_header "󰩺" "Available Modes — $monitor"

    while IFS= read -r mode; do
        [[ -z $mode ]] && continue
        rx_table_simple "󰄾" "$mode" "$PINK"
    done <<<"$raw"

    rx_table_separator
    rx_table_spacer
}

_display_get_resolution() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "width" 2>/dev/null) || true
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    local w=$raw
    local h
    h=$(bash "$core" --get "$monitor" "height" 2>/dev/null)
    local hz
    hz=$(bash "$core" --get "$monitor" "refreshRate" 2>/dev/null | cut -d'.' -f1)

    rx_table_simple "󰩺" "${monitor}: ${w}x${h} @ ${hz}Hz" "$PINK"
}

_display_set_resolution() {
    local core="$1"
    local monitor="$2"
    local mode="$3"
    local result
    result=$(bash "$core" --set-resolution "$monitor" "$mode" 2>/dev/null)
    [[ $result == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ $result == ERR_ARGS ]] && rx_log "error" "Usage: retro display resolution <monitor> <wxh@hz>" && return 1
    [[ $result == ERR_SET_FAILED ]] && rx_log "error" "Failed to set resolution for $monitor" && return 1
    rx_log "success" "Set $monitor resolution to $mode"
}

_display_get_refresh() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "refreshRate" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    local hz
    hz=$(echo "$raw" | cut -d'.' -f1)
    rx_table_simple "" "${monitor}: ${hz}Hz" "$PINK"
}

_display_set_refresh() {
    local core="$1"
    local monitor="$2"
    local hz="$3"
    local result
    result=$(bash "$core" --set-refresh "$monitor" "$hz" 2>/dev/null)
    [[ $result == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ $result == ERR_ARGS ]] && rx_log "error" "Usage: retro display refresh <monitor> <hz>" && return 1
    [[ $result == ERR_SET_FAILED ]] && rx_log "error" "Failed to set refresh rate for $monitor" && return 1
    rx_log "success" "Set $monitor refresh rate to ${hz}Hz"
}

_display_get_scale() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "scale" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    rx_table_simple "󰧑" "${monitor}: scale ${raw}" "$PINK"
}

_display_set_scale() {
    local core="$1"
    local monitor="$2"
    local scale="$3"
    local result
    result=$(bash "$core" --set-scale "$monitor" "$scale" 2>/dev/null)
    [[ $result == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ $result == ERR_ARGS ]] && rx_log "error" "Usage: retro display scale <monitor> <factor>" && return 1
    [[ $result == ERR_SET_FAILED ]] && rx_log "error" "Failed to set scale for $monitor" && return 1
    rx_log "success" "Set $monitor scale to $scale"
}

_display_get_position() {
    local core="$1"
    local monitor="$2"
    local x
    x=$(bash "$core" --get "$monitor" "x" 2>/dev/null)
    local y
    y=$(bash "$core" --get "$monitor" "y" 2>/dev/null)
    [[ -z $x || $x == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    rx_table_simple "󰘶" "${monitor}: ${x}x${y}" "$PINK"
}

_display_set_position() {
    local core="$1"
    local monitor="$2"
    local pos="$3"
    local result
    result=$(bash "$core" --set-position "$monitor" "$pos" 2>/dev/null)
    [[ $result == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ $result == ERR_ARGS ]] && rx_log "error" "Usage: retro display position <monitor> <x> <y>" && return 1
    [[ $result == ERR_SET_FAILED ]] && rx_log "error" "Failed to set position for $monitor" && return 1
    rx_log "success" "Set $monitor position to $pos"
}

_display_get_vrr() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "vrr" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1

    local display
    local color
    if [[ $raw == "true" ]]; then
        display="● On"
        color="$SUCCESS"
    elif [[ $raw == "2" || $raw == "adaptive" ]]; then
        display="○ Adaptive"
        color="$WARN"
    else
        display="○ Off"
        color="$MUTE"
    fi
    rx_table_simple "󰑪" "${monitor}: $display" "$color"
    rx_log "info" "Use ${PINK}retro display setup${RESET} to change VRR"
}

_display_set_vrr() {
    local core="$1"
    local monitor="$2"
    local value="$3"

    local vrr_val
    case "${value,,}" in
        on | 1 | true) vrr_val=1 ;;
        off | 0 | false) vrr_val=0 ;;
        adaptive | 2) vrr_val=2 ;;
        *) rx_log "error" "Invalid VRR value: $value (use on, off, or adaptive)" && return 1 ;;
    esac

    rx_log "info" "VRR changes require config reload. Use ${PINK}retro display setup${RESET} to apply"
}

_display_set_dpms() {
    local core="$1"
    local state="${2,,}"
    local monitor="$3"

    [[ $state != "on" && $state != "off" ]] && rx_log "error" "Usage: retro display dpms <on|off>" && return 1

    local result
    result=$(bash "$core" --set-dpms "$state" "$monitor" 2>/dev/null)
    [[ $result == ERR_ARGS ]] && rx_log "error" "Usage: retro display dpms <on|off>" && return 1
    [[ $result == ERR_DPMS_FAILED ]] && rx_log "error" "Failed to set DPMS" && return 1

    local msg="DPMS turned $state"
    [[ -n $monitor ]] && msg="$msg for $monitor"
    rx_log "success" "$msg"
}

_display_get_brightness() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "sdrBrightness" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ -z $raw || $raw == "null" ]] && rx_log "info" "SDR brightness not reported for $monitor" && return 0
    rx_table_simple "󰃟" "${monitor}: $raw" "$PINK"
    rx_log "info" "Use ${PINK}retro display setup${RESET} to change brightness"
}

_display_get_saturation() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "sdrSaturation" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ -z $raw || $raw == "null" ]] && rx_log "info" "SDR saturation not reported for $monitor" && return 0
    rx_table_simple "󰜚" "${monitor}: $raw" "$PINK"
    rx_log "info" "Use ${PINK}retro display setup${RESET} to change saturation"
}

_display_get_transform() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "transform" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1

    local names=("normal" "90°" "180°" "270°" "flipped" "flipped+90°" "flipped+180°" "flipped+270°")
    local name="${names[$raw]:-unknown}"
    rx_table_simple "󰔄" "${monitor}: $raw ($name)" "$PINK"
    rx_log "info" "Use ${PINK}retro display setup${RESET} to change transform"
}

_display_get_bitdepth() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "bitdepth" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ -z $raw || $raw == "null" ]] && rx_log "info" "Bit depth not reported for $monitor" && return 0
    rx_table_simple "󰌨" "${monitor}: ${raw}-bit" "$PINK"
    rx_log "info" "Use ${PINK}retro display setup${RESET} to change bit depth"
}

_display_get_cm() {
    local core="$1"
    local monitor="$2"
    local raw
    raw=$(bash "$core" --get "$monitor" "colorManagementPreset" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ -z $raw || $raw == "null" ]] && rx_log "info" "Color management not reported for $monitor" && return 0
    rx_table_simple "󰗡" "${monitor}: $raw" "$PINK"
    rx_log "info" "Use ${PINK}retro display setup${RESET} to change color management"
}

_display_set_enable() {
    local core="$1"
    local monitor="$2"

    local raw
    raw=$(bash "$core" --get "$monitor" "disabled" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ $raw == "false" ]] && rx_log "info" "$monitor is already enabled" && return 0

    rx_log "info" "Use ${PINK}retro display setup${RESET} to re-enable $monitor"
}

_display_set_disable() {
    local core="$1"
    local monitor="$2"

    local raw
    raw=$(bash "$core" --get "$monitor" "disabled" 2>/dev/null)
    [[ -z $raw || $raw == ERR_NO_MONITOR ]] && rx_log "error" "Monitor not found: $monitor" && return 1
    [[ $raw == "true" ]] && rx_log "info" "$monitor is already disabled" && return 0

    rx_log "info" "Use ${PINK}retro display setup${RESET} to disable $monitor"
}

_display_set_mirror() {
    local core="$1"
    local source="$2"
    local target="$3"

    if [[ -n $target ]]; then
        rx_log "info" "Mirror $source → $target. Use ${PINK}retro display setup${RESET} to apply"
    else
        rx_log "info" "Unmirror $source. Use ${PINK}retro display setup${RESET} to apply"
    fi
}

_display_setup() {
    local core="$1"

    rx_setup_parse "$@"

    local monitors_raw
    monitors_raw=$(bash "$core" --list-monitors)
    local monitor_names=()
    local monitor_descs=()
    local monitor_count=0

    while IFS='|' read -r name desc _; do
        [[ -z $name ]] && continue
        monitor_names+=("$name")
        monitor_descs+=("$desc")
        ((monitor_count++))
    done <<<"$monitors_raw"

    if [[ $monitor_count -eq 0 ]]; then
        rx_log "error" "No monitors detected" && return 1
    fi

    rx_setup_validate "config" "" || return 1

    local config_exists=false
    [[ -f "$HOME/.config/retro/monitors.lua" ]] && config_exists=true
    rx_setup_check_needed "$config_exists" && return 0

    local mon_fields=""

    if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
        local config_file
        config_file=$(rx_setup_get_opt "config" "")
        if [[ -n $config_file && -f $config_file ]]; then
            mon_fields=$(<"$config_file")
        else
            rx_log "error" "Non-interactive mode requires -o config=<file> with monitor config"
            rx_log "info" "Example: retro display setup -o config=/tmp/monitors.txt -y"
            return 1
        fi
    else
        # Interactive: prompt for each monitor
        rx_log "info" "Configuring ${PINK}$monitor_count${RESET} monitor(s)"
        rx_table_spacer

        local idx=0
        for ((idx = 0; idx < monitor_count; idx++)); do
            local m_name="${monitor_names[$idx]}"
            local m_desc="${monitor_descs[$idx]}"

            # Read current values from JSON
            local cur_w cur_h cur_refresh cur_x cur_y cur_scale cur_vrr cur_disabled cur_transform cur_mirror
            # shellcheck disable=SC2034
            while IFS='|' read -r name _ _ _ w2 h2 r2 x2 y2 s2 v2 d2 dis2 t2 m2 _ _ _ _; do
                [[ $name != "$m_name" ]] && continue
                cur_w=$w2
                cur_h=$h2
                cur_refresh=$r2
                cur_x=$x2
                cur_y=$y2
                cur_scale=$s2
                cur_vrr=$v2
                cur_disabled=$dis2
                cur_transform=$t2
                cur_mirror=$m2
            done <<<"$monitors_raw"

            [[ -z $cur_w || -z $cur_h ]] && continue

            rx_table_header "󰍹" "Monitor $((idx + 1)): $m_name"
            rx_table_row_gray "󰐓" "Description:" "$m_desc" "20"

            local input_disabled
            if [[ $cur_disabled == "true" ]]; then
                input_disabled=$(rx_input_choice "󰪥" "Enable this monitor?" "yes" yes no)
            else
                input_disabled=$(rx_input_choice "󰪥" "Disable this monitor?" "no" no yes)
            fi

            [[ $input_disabled == "yes" ]] && cur_disabled="true" || cur_disabled="false"

            if [[ $cur_disabled == "false" ]]; then
                local current_mode="${cur_w}x${cur_h}@${cur_refresh}"
                local mode_options=("preferred" "highres" "highrr")

                # Add current mode if not in defaults
                local has_current=false
                for m in "${mode_options[@]}"; do [[ $m == "$current_mode" ]] && has_current=true && break; done
                $has_current || mode_options=("$current_mode" "${mode_options[@]}")

                input_mode=$(rx_input_choice "󰩺" "Select mode for $m_name" "${mode_options[0]}" "${mode_options[@]}")
                [[ -z $input_mode ]] && input_mode="$current_mode"

                input_pos=$(rx_input "Position (x,y or auto)" "${cur_x}x${cur_y}")
                [[ -z $input_pos ]] && input_pos="${cur_x}x${cur_y}"

                input_scale=$(rx_input "Scale (number or auto)" "$cur_scale")
                [[ -z $input_scale ]] && input_scale="$cur_scale"

                local vrr_options=("off" "on" "adaptive")
                local vrr_default="off"
                [[ $cur_vrr == "true" ]] && vrr_default="on"
                [[ $cur_vrr == "2" || $cur_vrr == "adaptive" ]] && vrr_default="adaptive"
                input_vrr=$(rx_input_choice "󰑪" "VRR for $m_name" "$vrr_default" "${vrr_options[@]}")

                local trans_options=("0 (normal)" "1 (90°)" "2 (180°)" "3 (270°)" "4 (flipped)" "5 (flipped+90°)" "6 (flipped+180°)" "7 (flipped+270°)")
                input_transform=$(rx_input_choice "󰔄" "Transform for $m_name" "0 (normal)" "${trans_options[@]}")
                input_transform="${input_transform%% *}"

                local cm_options=("srgb" "auto" "dcip3" "adobe" "wide" "edid" "hdr")
                input_cm=$(rx_input_choice "󰗡" "Color management for $m_name" "srgb" "${cm_options[@]}")

                input_bitdepth=$(rx_input_choice "󰌨" "Bit depth for $m_name" "8" "8" "10")

                local mirror_names=("none" "${monitor_names[@]}")
                input_mirror=$(rx_input_choice "󰛐" "Mirror from another monitor?" "none" "${mirror_names[@]}")
            fi

            # Build field string for this monitor
            local mon_entry="output=desc:${m_desc%% (*}"
            mon_entry="${mon_entry%%(*}"
            mon_entry="${mon_entry%"${mon_entry##*[! ]}"}" # trim trailing space

            if [[ $cur_disabled == "true" ]]; then
                mon_entry="${mon_entry},disabled=true"
            else
                mon_entry="${mon_entry},mode=${input_mode},position=${input_pos},scale=${input_scale}"
                local vrr_val=0
                [[ $input_vrr == "on" ]] && vrr_val=1
                [[ $input_vrr == "adaptive" ]] && vrr_val=2
                mon_entry="${mon_entry},vrr=${vrr_val}"
                mon_entry="${mon_entry},transform=${input_transform}"
                mon_entry="${mon_entry},cm=${input_cm}"
                mon_entry="${mon_entry},bitdepth=${input_bitdepth}"
                [[ $input_mirror != "none" ]] && mon_entry="${mon_entry},mirror=${input_mirror}"
            fi

            if [[ -n $mon_fields ]]; then
                mon_fields="${mon_fields}|${mon_entry}"
            else
                mon_fields="${mon_entry}"
            fi
        done
    fi

    if [[ -z $mon_fields ]]; then
        rx_log "error" "No monitor configuration provided" && return 1
    fi

    # Show summary
    rx_setup_summary "󰍹" "Display Configuration" \
        "Monitors" "$(echo "$mon_fields" | grep -o '|' | wc -l | tr -d ' ') monitors"

    if [[ $RX_SETUP_YES == true ]]; then
        rx_log "info" "Auto-confirming (--yes flag provided)"
    else
        rx_setup_confirm || return 0
    fi

    # Generate and write config
    local config_output
    config_output=$(bash "$core" --generate-config "$mon_fields" 2>/dev/null)
    if [[ $config_output == ERR_ARGS ]]; then
        rx_log "error" "Failed to generate monitor config" && return 1
    fi

    # Backup existing config
    if [[ -f "$HOME/.config/retro/monitors.lua" ]]; then
        cp "$HOME/.config/retro/monitors.lua" "$HOME/.config/retro/monitors.lua.bak" 2>/dev/null
    fi

    mkdir -p "$HOME/.config/retro"
    if ! echo "$config_output" >"$HOME/.config/retro/monitors.lua" 2>/dev/null; then
        rx_log "error" "Failed to write monitors.lua" && return 1
    fi

    # Reload Hyprland config
    hyprctl reload 2>/dev/null || true

    rx_setup_success "󰍹" "Display Configuration Applied" \
        "Config" "monitors.lua"
}

register_command "TOOLS" "display" "Display/monitor management (resolution, scale, VRR, layout)" "cmd_display"
