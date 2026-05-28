#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "fans"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

_has_liquidctl() {
    command -v liquidctl &>/dev/null && return 0
    return 1
}

_has_sensors() {
    command -v sensors &>/dev/null && return 0
    return 1
}

_hwmon_dirs() {
    for d in /sys/class/hwmon/hwmon*; do
        [[ -d $d ]] && echo "$d"
    done
}

_has_pwm() {
    local dir="$1"
    for f in "$dir"/pwm*; do
        [[ -f $f ]] && return 0
    done
    return 1
}

_is_pwm_writable() {
    local pwm="$1"
    [[ -w $pwm ]] && return 0
    return 1
}

_pwm_to_pct() {
    local val="$1"
    echo "$(( (val * 100 + 127) / 255 ))"
}

_pct_to_pwm() {
    local pct="$1"
    echo "$(( (pct * 255 + 50) / 100 ))"
}

_detect_engine() {
    _has_liquidctl && { echo "liquidctl"; return; }
    _has_sensors && { echo "lm-sensors"; return; }
    echo "sysfs"
}

_get_liquidctl_devices() {
    _has_liquidctl || return 1
    $SUDO_CMD liquidctl list 2>/dev/null | grep -oP 'Device #\d+:.*' | sed 's/Device #\d+: //'
}

_get_liquidctl_status() {
    _has_liquidctl || return 1
    $SUDO_CMD liquidctl status --json 2>/dev/null
}

_get_liquidctl_fans() {
    local status
    status=$(_get_liquidctl_status)
    [[ -z $status ]] && return

    local count=0
    while true; do
        local key="fan${count} speed"
        local label_key="fan${count} label"
        local speed=$(echo "$status" | grep -oP "\"${key}\" *: *\K[0-9]+" 2>/dev/null || echo "")
        local label=$(echo "$status" | grep -oP "\"${label_key}\" *: *\"\K[^\"]+" 2>/dev/null || echo "Fan $count")
        [[ -z $speed ]] && break
        local temp=$(echo "$status" | grep -oP '"liquid temperature" *: *\K[0-9.]+' 2>/dev/null || echo "0")
        echo "liquidctl|${label}|${speed}|0|${temp}C"
        count=$((count + 1))
    done
}

_liquidctl_set_speed() {
    local fan="$1"
    local pct="$2"
    _has_liquidctl || return 1
    $SUDO_CMD liquidctl set "${fan}" speed "${pct}" 2>/dev/null && rx_log_file "info" "liquidctl: ${fan} set to ${pct}%"
}

_liquidctl_reset() {
    _has_liquidctl || return 1
    $SUDO_CMD liquidctl initialize 2>/dev/null
    rx_log_file "info" "liquidctl: all devices reset to defaults"
}

_parse_curve() {
    local curve="$1"
    local target_temp="$2"
    local prev_pct=30
    local prev_temp=0

    IFS=',' read -ra points <<<"$curve"
    for point in "${points[@]}"; do
        local temp="${point%%:*}"
        local pct="${point#*:}"
        if [[ $target_temp -ge $temp ]]; then
            prev_pct="$pct"
            prev_temp="$temp"
        else
            if [[ $target_temp -le $prev_temp ]]; then
                echo "$prev_pct"
                return
            fi
            local range=$((temp - prev_temp))
            [[ $range -eq 0 ]] && echo "$prev_pct" && return
            local pct_range=$((pct - prev_pct))
            local delta=$((target_temp - prev_temp))
            local result=$((prev_pct + (pct_range * delta) / range))
            echo "$result"
            return
        fi
    done
    echo "$prev_pct"
}

_sysfs_fans() {
    for hw in $(_hwmon_dirs); do
        local hw_name=$(basename "$hw")

        for f in "$hw"/fan*_input; do
            [[ -f $f ]] || continue
            local fan_idx
            fan_idx=$(echo "$f" | grep -oP 'fan\K[0-9]+')
            local rpm
            rpm=$(cat "$f" 2>/dev/null || echo "0")
            local label
            label=$(cat "$hw/fan${fan_idx}_label" 2>/dev/null || echo "")
            [[ -z $label ]] && label="Fan ${fan_idx}"
            label="${hw_name}/${label}"
            local pwm_file="$hw/pwm${fan_idx}"
            local pwm_val=0
            local pct=0
            if [[ -f $pwm_file ]]; then
                pwm_val=$(cat "$pwm_file" 2>/dev/null || echo "0")
                pct=$(_pwm_to_pct "$pwm_val")
            fi
            if [[ $pct -eq 0 && $rpm -gt 0 ]]; then
                local max_rpm=5000
                pct=$(( (rpm * 100 + max_rpm / 2) / max_rpm ))
                [[ $pct -gt 100 ]] && pct=100
            fi
            local temp="0C"
            for tf in "$hw"/temp*_input; do
                [[ -f $tf ]] || continue
                local tval
                tval=$(cat "$tf" 2>/dev/null || echo "0")
                local tlabel
                tlabel=$(cat "${tf%_input}_label" 2>/dev/null || echo "sensor")
                temp="$((tval / 1000))C ($tlabel)"
                break
            done
            local writable="no"
            _is_pwm_writable "$pwm_file" && writable="yes"
            echo "${hw_name}|${label}|${rpm}|${pct}|${temp}|${writable}"
        done
    done
}

_sysfs_temps() {
    for hw in $(_hwmon_dirs); do
        local hw_name=$(basename "$hw")
        for f in "$hw"/temp*_input; do
            [[ -f $f ]] || continue
            local tidx
            tidx=$(echo "$f" | grep -oP 'temp\K[0-9]+')
            local tval
            tval=$(cat "$f" 2>/dev/null || echo "0")
            local tlabel
            tlabel=$(cat "$hw/temp${tidx}_label" 2>/dev/null || echo "Temp ${tidx}")
            tlabel="${hw_name}/${tlabel}"
            echo "${hw_name}|${tlabel}|$((tval / 1000))C"
        done
    done
}

_sysfs_set_speed() {
    local fan_name="$1"
    local pct="$2"
    local pwm_val
    pwm_val=$(_pct_to_pwm "$pct")

    for hw in $(_hwmon_dirs); do
        local hw_name=$(basename "$hw")
        for f in "$hw"/fan*_input; do
            [[ -f $f ]] || continue
            local idx
            idx=$(echo "$f" | grep -oP 'fan\K[0-9]+')
            local raw_label
            raw_label=$(cat "$hw/fan${idx}_label" 2>/dev/null || echo "Fan ${idx}")
            local full_label="${hw_name}/${raw_label}"
            if [[ "$raw_label" == "$fan_name" || "$full_label" == "$fan_name" || "$raw_label" == "${fan_name//_/ }" || "$full_label" == "${fan_name//_/ }" || "$raw_label" == "${fan_name// /_}" || "$full_label" == "${fan_name// /_}" ]]; then
                local pwm_file="$hw/pwm${idx}"
                if [[ -f $pwm_file ]]; then
                    $SUDO_CMD bash -c "echo 1 > '$hw/pwm${idx}_enable' 2>/dev/null; echo ${pwm_val} > '$pwm_file' 2>/dev/null" 2>/dev/null && {
                        rx_log_file "info" "sysfs: ${fan_name} set to ${pct}% (PWM ${pwm_val})"
                        return 0
                    }
                fi
                return 1
            fi
        done
    done
    return 1
}

_sysfs_set_curve() {
    local fan_name="$1"
    local curve="$2"

    rx_log_file "info" "sysfs: set_curve called for '${fan_name}' with curve '${curve}'"

    for hw in $(_hwmon_dirs); do
        local hw_name=$(basename "$hw")
        for f in "$hw"/fan*_input; do
            [[ -f $f ]] || continue
            local idx
            idx=$(echo "$f" | grep -oP 'fan\K[0-9]+')
            local raw_label
            raw_label=$(cat "$hw/fan${idx}_label" 2>/dev/null || echo "Fan ${idx}")
            local full_label="${hw_name}/${raw_label}"
            if [[ "$raw_label" == "$fan_name" || "$full_label" == "$fan_name" || "$raw_label" == "${fan_name//_/ }" || "$full_label" == "${fan_name//_/ }" || "$raw_label" == "${fan_name// /_}" || "$full_label" == "${fan_name// /_}" ]]; then
                local current_temp
                current_temp=$(_get_coretemp)
                [[ -z $current_temp || $current_temp -eq 0 ]] && current_temp=30

                local target_pct
                target_pct=$(_parse_curve "$curve" "$current_temp")
                local pwm_val
                pwm_val=$(_pct_to_pwm "$target_pct")

                local pwm_ctrl="$hw/pwm${idx}"
                if [[ -f $pwm_ctrl ]]; then
                    rx_log_file "info" "sysfs: ${fan_name} → ${target_pct}% (${current_temp}C) at ${pwm_ctrl}"
                    $SUDO_CMD bash -c "echo 1 > '$hw/pwm${idx}_enable' 2>/dev/null; echo ${pwm_val} > '$pwm_ctrl' 2>/dev/null" 2>/dev/null
                    local rc=$?
                    if [[ $rc -eq 0 ]]; then
                        rx_log_file "success" "sysfs: ${fan_name} set ${target_pct}% (${current_temp}C, PWM ${pwm_val})"
                        return 0
                    else
                        rx_log_file "error" "sysfs: ${fan_name} PWM write failed (rc=${rc})"
                    fi
                fi
                return 1
            fi
        done
    done
    return 1
}

_sysfs_reset() {
    for hw in $(_hwmon_dirs); do
        for f in "$hw"/pwm*_enable; do
            [[ -f $f ]] || continue
            $SUDO_CMD bash -c "echo 2 > '$f'" 2>/dev/null
        done
    done
    rx_log_file "info" "sysfs: all fans reset to auto mode"
}

_get_coretemp() {
    local max_temp=0
    for f in /sys/class/hwmon/hwmon*/temp*_input; do
        [[ -f $f ]] || continue
        local val
        val=$(cat "$f" 2>/dev/null || echo "0")
        val=$((val / 1000))
        [[ $val -gt $max_temp ]] && max_temp=$val
    done
    echo "$max_temp"
}

_get_default_curve() {
    local profile="${1:-balanced}"
    case "$profile" in
        quiet) echo "30:20,50:40,70:60,85:80" ;;
        balanced) echo "30:30,50:50,70:75,85:100" ;;
        performance) echo "30:40,50:70,70:90,85:100" ;;
        *) echo "30:30,50:50,70:75,85:100" ;;
    esac
}

case "$1" in
    "--detect")
        engine=$(_detect_engine)
        devices=""
        if [[ $engine == "liquidctl" ]]; then
            devices=$(_get_liquidctl_devices | tr '\n' ',' | sed 's/,$//')
        elif [[ $engine == "lm-sensors" ]]; then
            devices=$(_has_sensors && sensors --version 2>/dev/null | head -1 | xargs || echo "lm-sensors")
        else
            local count=0
            for hw in $(_hwmon_dirs); do
                for f in "$hw"/pwm*; do
                    [[ -f $f ]] && count=$((count + 1))
                done
            done
            devices="${count} PWM controls"
        fi
        echo "engine=${engine}"
        echo "devices=${devices}"
        rx_log_file "info" "Detected engine: ${engine} (${devices})"
        ;;

    "--scan-engines")
        _has_liquidctl && echo "liquidctl"
        _has_sensors && echo "lm-sensors"
        echo "sysfs"
        ;;

    "--status")
        engine=$(_detect_engine)
        echo "engine:${engine}"

        _get_coretemp >/dev/null 2>&1
        cpu_temp=$(_get_coretemp)
        echo "cpu_temp:${cpu_temp}C"

        if [[ $engine == "liquidctl" ]]; then
            lq_status=""
            lq_status=$(_get_liquidctl_status)
            if [[ -n $lq_status ]]; then
                liq_temp=$(echo "$lq_status" | grep -oP '"liquid temperature" *: *\K[0-9.]+' 2>/dev/null || echo "0")
                echo "liquid_temp:${liq_temp}C"
                count=0
                while true; do
                    key="fan${count} speed"
                    speed=$(echo "$lq_status" | grep -oP "\"${key}\" *: *\K[0-9]+" 2>/dev/null || echo "")
                    [[ -z $speed ]] && break
                    dkey="fan${count} duty"
                    duty=$(echo "$lq_status" | grep -oP "\"${dkey}\" *: *\K[0-9]+" 2>/dev/null || echo "0")
                    echo "fan_${count}:${speed}rpm (${duty}%)"
                    count=$((count + 1))
                done
            fi
        else
            while IFS='|' read -r hw label rpm pct temp writable; do
                safe_label="${label// /_}"
                echo "fan_${safe_label}:${rpm}rpm (${pct}%)"
            done < <(_sysfs_fans)
        fi

        profile=$(get_var "FAN_PROFILE" "balanced")
        echo "profile:${profile}"
        rx_log_file "info" "Status reported (engine: ${engine}, profile: ${profile})"
        ;;

    "--list-fans")
        engine=$(_detect_engine)
        if [[ $engine == "liquidctl" ]]; then
            _get_liquidctl_fans
        else
            _sysfs_fans
        fi
        ;;

    "--list-temps")
        _sysfs_temps
        ;;

    "--set-speed")
        fan_name="$2"
        pct="$3"
        [[ -z $fan_name ]] && rx_log_file "error" "Missing fan name" && exit 1
        [[ -z $pct ]] && rx_log_file "error" "Missing speed percentage" && exit 1
        [[ ! $pct =~ ^[0-9]+$ ]] && rx_log_file "error" "Speed must be numeric" && exit 1
        [[ $pct -lt 0 || $pct -gt 100 ]] && rx_log_file "error" "Speed must be 0-100" && exit 1

        engine=$(_detect_engine)
        if [[ $engine == "liquidctl" ]]; then
            _liquidctl_set_speed "$fan_name" "$pct"
        else
            _sysfs_set_speed "$fan_name" "$pct"
        fi
        set_var "FAN_ENGINE" "$engine"
        set_var "FAN_ENABLED" "true"
        ;;

    "--set-curve")
        fan_name="$2"
        curve="$3"
        [[ -z $fan_name ]] && rx_log_file "error" "Missing fan name" && exit 1
        [[ -z $curve ]] && rx_log_file "error" "Missing curve data" && exit 1

        set_var "FAN_CURVE_${fan_name}" "$curve"
        _sysfs_set_curve "$fan_name" "$curve"
        ;;

    "--profile")
        profile="$2"
        curve=""
        curve=$(_get_default_curve "${profile:-balanced}")

        engine=$(_detect_engine)
        if [[ $engine == "liquidctl" ]]; then
            devices=""
            devices=$(_get_liquidctl_devices)
            count=0
            current_temp=$(_get_coretemp)
            [[ -z $current_temp || $current_temp -eq 0 ]] && current_temp=30
            while IFS= read -r dev; do
                [[ -z $dev ]] && continue
                target_pct=$(_parse_curve "$curve" "$current_temp")
                _liquidctl_set_speed "fan${count}" "$target_pct" 2>/dev/null
                count=$((count + 1))
            done <<<"$devices"
        else
            while IFS='|' read -r hw label rpm pct temp writable; do
                safe_label="${label// /_}"
                _sysfs_set_curve "$label" "$curve"
                set_var "FAN_CURVE_${safe_label}" "$curve"
            done < <(_sysfs_fans)
        fi

        set_var "FAN_PROFILE" "$profile"
        set_var "FAN_ENABLED" "true"
        rx_log_file "success" "Profile '${profile}' applied"
        echo "OK|profile=${profile}"
        ;;

    "--reset")
        engine=$(_detect_engine)
        if [[ $engine == "liquidctl" ]]; then
            _liquidctl_reset
        else
            _sysfs_reset
        fi
        set_var "FAN_PROFILE" "auto"
        set_var "FAN_ENABLED" "false"
        rx_log_file "success" "All fans reset to defaults"
        ;;

    "--daemon-tick")
        enabled=$(get_var "FAN_ENABLED" "false")
        [[ $enabled != "true" ]] && exit 0

        engine=$(get_var "FAN_ENGINE" "auto")
        [[ $engine == "auto" ]] && engine=$(_detect_engine)

        profile=$(get_var "FAN_PROFILE" "balanced")
        curve=$(_get_default_curve "$profile")

        current_temp=$(_get_coretemp)
        [[ -z $current_temp || $current_temp -eq 0 ]] && exit 0

        fan_count=0
        while IFS='|' read -r hw label rpm pct temp writable; do
            safe_label="${label// /_}"
            custom_curve=$(get_var "FAN_CURVE_${safe_label}" "")
            use_curve="${custom_curve:-$curve}"
            target_pct=$(_parse_curve "$use_curve" "$current_temp")
            [[ $target_pct -gt 100 ]] && target_pct=100
            [[ $target_pct -lt 0 ]] && target_pct=0
            _sysfs_set_speed "$label" "$target_pct" 2>/dev/null
            fan_count=$((fan_count + 1))
        done < <(_sysfs_fans)

        echo "${current_temp}C: ${fan_count} fans → ${profile}"
        ;;

    "--setup-apply")
        engine=""
        profile=""
        for arg in "$@"; do
            case "$arg" in
                engine=*) engine="${arg#engine=}" ;;
                profile=*) profile="${arg#profile=}" ;;
            esac
        done

        [[ -z $engine ]] && engine=$(_detect_engine)
        [[ -z $profile ]] && profile="balanced"

        set_var "FAN_ENGINE" "$engine"
        set_var "FAN_PROFILE" "$profile"
        set_var "FAN_ENABLED" "true"

        curve=""
        curve=$(_get_default_curve "$profile")

        fan_count=0
        while IFS='|' read -r hw label rpm pct temp writable; do
            safe_label="${label// /_}"
            custom_curve=$(get_var "FAN_CURVE_${safe_label}" "")
            use_curve="${custom_curve:-$curve}"
            _sysfs_set_curve "$label" "$use_curve"
            set_var "FAN_CURVE_${safe_label}" "$use_curve"
            fan_count=$((fan_count + 1))
        done < <(_sysfs_fans)

        echo "OK|engine=${engine}|profile=${profile}|fans=${fan_count}"
        rx_log_file "success" "Fan setup applied: engine=${engine} profile=${profile} fans=${fan_count}"
        ;;

    *)
        echo "Usage: $0 --{detect|status|list-fans|list-temps|set-speed|set-curve|reset|profile|scan-engines|setup-get|setup-apply} [args]"
        exit 1
        ;;
esac
