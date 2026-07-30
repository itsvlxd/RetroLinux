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
        disabled|identify_by_description) return 0 ;;
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
    local dpi
    dpi=$(echo "$scale * 96" | bc -l | cut -d'.' -f1)
    _set_xft_dpi "$dpi"
    _cmd_apply_sddm_hidpi "$name" "$scale" >/dev/null 2>&1 || true
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

_cmd_set_brightness() {
    local name="$1"
    local value="$2"
    [[ -z $name || -z $value ]] && echo "ERR_ARGS" && return 1

    if ! command -v brightnessctl >/dev/null 2>&1; then
        echo "ERR_NO_BRIGHTNESSCTL"
        return 1
    fi

    if [[ $value != *%* ]]; then
        if [[ $value == -* ]]; then
            value="${value#-}%-"
        else
            value="${value}%"
        fi
    fi

    if ! brightnessctl set "$value" >/dev/null 2>&1; then
        rx_log_file "error" "Failed to set brightness for $name"
        echo "ERR_SET_FAILED"
        return 1
    fi
    rx_log_file "info" "Set brightness for $name to $value"
    bash "$RETRO_DIR/scripts/shell_core.sh" --run "brightness_ping" 2>/dev/null &
}

_cmd_get_brightness() {
    local name="$1"
    if ! command -v brightnessctl >/dev/null 2>&1; then
        echo "ERR_NO_BRIGHTNESSCTL"
        return 1
    fi

    local pct
    pct=$(brightnessctl -m info 2>/dev/null | cut -d',' -f4 | tr -d '%')
    if [[ -z $pct ]]; then
        local cur max
        cur=$(brightnessctl get 2>/dev/null)
        max=$(brightnessctl max 2>/dev/null)
        [[ -z $cur || -z $max || $max -eq 0 ]] && echo "ERR_NO_BRIGHTNESS" && return 1
        pct=$((cur * 100 / max))
    fi
    echo "$pct"
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

_set_xft_dpi() {
    local dpi="$1"
    [[ -z $dpi || $dpi == "0" ]] && dpi=96

    local xresources="$HOME/.Xresources"
    if grep -q '^Xft\.dpi' "$xresources" 2>/dev/null; then
        sed -i "s/^Xft\.dpi:.*/Xft.dpi: $dpi/" "$xresources"
    else
        echo "Xft.dpi: $dpi" >> "$xresources"
    fi
    command -v xrdb >/dev/null 2>&1 && DISPLAY="${DISPLAY:-:0}" xrdb -merge "$xresources" 2>/dev/null || true
    rx_log_file "info" "Set Xft.dpi to $dpi"
}

_cmd_set_xft_dpi() {
    local dpi="$1"
    [[ -z $dpi ]] && echo "ERR_ARGS" && return 1
    _set_xft_dpi "$dpi"
}

_cmd_get_xft_dpi() {
    local dpi
    dpi=$(command -v xrdb >/dev/null 2>&1 && DISPLAY="${DISPLAY:-:0}" xrdb -get Xft.dpi 2>/dev/null || true)
    if [[ -z $dpi ]]; then
        dpi=$(grep '^Xft\.dpi' "$HOME/.Xresources" 2>/dev/null | head -1 | awk '{print $2}')
    fi
    echo "${dpi:-96}"
}

_cmd_scale_to_dpi() {
    local scale="$1"
    [[ -z $scale ]] && echo "ERR_ARGS" && return 1
    local dpi
    dpi=$(echo "$scale * 96" | bc -l | cut -d'.' -f1)
    [[ -z $dpi || $dpi == "0" ]] && dpi=96
    echo "$dpi"
}

_cmd_set_transform() {
    local name="$1"
    local t="$2"
    [[ -z $name || -z $t ]] && echo "ERR_ARGS" && return 1
    [[ $t != [0-7] ]] && echo "ERR_INVALID_TRANSFORM" && return 1

    local json
    json=$(_get_monitor_json "$name")
    [[ -z $json ]] && echo "ERR_NO_MONITOR" && return 1

    local mode
    mode=$(echo "$json" | jq -r '.availableModes[0] // "preferred"')
    local pos
    pos=$(echo "$json" | jq -r '"\(.x)x\(.y)"')
    local scale
    scale=$(echo "$json" | jq -r '.scale')
    local vrr
    vrr=$(echo "$json" | jq -r 'if .vrr then 1 else 0 end')
    local cm
    cm=$(echo "$json" | jq -r '.colorManagementPreset // empty')
    local bitdepth
    bitdepth=$(echo "$json" | jq -r '.bitdepth // empty')
    local disabled
    disabled=$(echo "$json" | jq -r '.disabled')

    local extra=""
    [[ -n $cm ]] && extra="$extra, cm = \"$cm\""
    [[ -n $bitdepth ]] && extra="$extra, bitdepth = $bitdepth"
    [[ $disabled == "true" ]] && extra="$extra, disabled = true"

    local lua="hl.monitor({ output = \"$name\", mode = \"$mode\", position = \"$pos\", scale = $scale, vrr = $vrr, transform = $t$extra })"

    if ! hyprctl eval "$lua" >/dev/null 2>&1; then
        rx_log_file "error" "Failed to set transform for $name"
        echo "ERR_SET_FAILED"
        return 1
    fi

    local touch_base
    touch_base=$(hyprctl devices -j 2>/dev/null | jq -r '(.touch // [])[0].name // ""')
    if [[ -n $touch_base ]]; then
        local devs
        devs=$(hyprctl devices -j 2>/dev/null | jq -r --arg b "$touch_base" '
            [(.touch // [])[] | select(.name | startswith($b)) | .name] +
            [(.tablets // [])[] | select(.name | startswith($b)) | .name] +
            [(.mice // [])[] | select(.name | startswith($b)) | .name]
            | unique[]
        ')
        while IFS= read -r dev; do
            [[ -z $dev ]] && continue
            hyprctl eval 'hl.device({ name = "'"$dev"'", transform = '"$t"', output = "'"$name"'" })' >/dev/null 2>&1 || true
        done <<< "$devs"
    fi

    pkill -x hyprpaper >/dev/null 2>&1 || true
    hyprpaper >/dev/null 2>&1 &

    rx_log_file "info" "Set transform for $name to $t"
}

_cmd_apply_sddm_hidpi() {
    local name="$1"
    local scale="$2"

    if [[ -z $scale ]]; then
        if [[ -n $name ]]; then
            scale=$(_get_monitor_field "$name" "scale")
            [[ -z $scale || $scale == "null" ]] && echo "ERR_NO_MONITOR" && return 1
        else
            scale=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .scale' | head -1)
            [[ -z $scale ]] && echo "ERR_NO_FOCUSED" && return 1
        fi
    fi

    local dpi
    dpi=$(echo "$scale * 96" | bc -l | cut -d'.' -f1)
    [[ -z $dpi || $dpi == "0" ]] && dpi=96

    local sddm_dir="/etc/sddm.conf.d"
    local sddm_file="$sddm_dir/hidpi.conf"

    mkdir -p "$sddm_dir" 2>/dev/null || true

    local content="[General]
GreeterEnvironment=QT_SCREEN_SCALE_FACTORS=${scale},QT_FONT_DPI=${dpi}

[Wayland]
EnableHiDPI=true

[X11]
EnableHiDPI=true
ServerArguments=-nolisten tcp -dpi ${dpi}
"
    if ! echo "$content" | tee "$sddm_file" >/dev/null 2>&1; then
        rx_log_file "error" "Failed to write SDDM HiDPI config"
        echo "ERR_SDDM_FAILED"
        return 1
    fi

    rx_log_file "info" "Applied SDDM HiDPI config: scale=$scale, dpi=$dpi"
    echo "SDDM HiDPI config applied: scale=$scale, dpi=$dpi (takes effect on next login)"
}

_cmd_get_transform() {
    local name="$1"
    _cmd_get "$name" "transform"
}

_cmd_lock_rotation() {
    local action="${1:-status}"
    case "$action" in
        on)
            set_var "ROTATION_LOCK" "true"
            ;;
        off)
            set_var "ROTATION_LOCK" "false"
            ;;
        toggle)
            local cur
            cur=$(get_var "ROTATION_LOCK" "false")
            if [[ $cur == "true" ]]; then
                set_var "ROTATION_LOCK" "false"
            else
                set_var "ROTATION_LOCK" "true"
            fi
            ;;
        status)
            local locked
            locked=$(get_var "ROTATION_LOCK" "false")
            echo "$locked"
            ;;
    esac
}

_cmd_detect_internal_monitor() {
    _get_monitors_json | jq -r '.[] | select(.name | test("^(eDP|LVDS|DSI)")) | .name' | head -1
}

_cmd_rotation_status() {
    local monitor
    monitor=$(_cmd_detect_internal_monitor)
    local transform
    transform=$(_cmd_get_transform "$monitor" 2>/dev/null || echo "?")
    local locked
    locked=$(get_var "ROTATION_LOCK" "false")
    local names=("normal" "90°" "180°" "270°" "flipped" "flipped+90°" "flipped+180°" "flipped+270°")
    local tname="${names[$transform]:-unknown}"
    echo "monitor:$monitor"
    echo "transform:$transform ($tname)"
    echo "locked:$locked"
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
    "--set-brightness")
        _cmd_set_brightness "$2" "$3"
        ;;
    "--get-brightness")
        _cmd_get_brightness "$2"
        ;;
    "--set-dpms")
        _cmd_set_dpms "$2" "$3"
        ;;
    "--set-xft-dpi")
        _cmd_set_xft_dpi "$2"
        ;;
    "--get-xft-dpi")
        _cmd_get_xft_dpi
        ;;
    "--scale-to-dpi")
        _cmd_scale_to_dpi "$2"
        ;;
    "--generate-config")
        _cmd_generate_config "$2"
        ;;
    "--set-transform")
        _cmd_set_transform "$2" "$3"
        ;;
    "--get-transform")
        _cmd_get_transform "$2"
        ;;
    "--lock-rotation")
        _cmd_lock_rotation "$2"
        ;;
    "--detect-internal-monitor")
        _cmd_detect_internal_monitor
        ;;
    "--rotation-status")
        _cmd_rotation_status
        ;;
    *)
        echo "ERR_UNKNOWN_FLAG"
        exit 1
        ;;
esac
