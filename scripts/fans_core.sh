#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "fans"

SUDO_CMD=""
[[ $EUID -ne 0 ]] && SUDO_CMD="sudo"

_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/retro"
_CONFIG_FILE="${_CONFIG_DIR}/fan_config.json"

_hwmon_dirs() {
    for d in /sys/class/hwmon/hwmon*; do
        [[ -d $d ]] && echo "$d"
    done
}

_has_liquidctl() { command -v liquidctl &>/dev/null; }
_has_sensors() { command -v sensors &>/dev/null; }
_has_acpi_platform_profile() { [[ -f /sys/firmware/acpi/platform_profile_choices ]]; }

_pwm_to_pct() { echo "$(( ($1 * 100 + 127) / 255 ))"; }
_pct_to_pwm() {
    local p=$1
    [[ $p -gt 100 ]] && p=100; [[ $p -lt 0 ]] && p=0
    echo "$(( (p * 255 + 50) / 100 ))"
}

_config_read() {
    [[ -f $_CONFIG_FILE ]] && cat "$_CONFIG_FILE" || echo '{"master":false,"profile":"balanced","fans":{}}'
}
_config_write() {
    mkdir -p "$_CONFIG_DIR"
    echo "$1" | jq '.' > "${_CONFIG_FILE}.tmp" && mv "${_CONFIG_FILE}.tmp" "$_CONFIG_FILE"
}
_config_set_fan() {
    local id="$1" mode="$2" curve="$3" speed="$4"
    _config_write "$(_config_read | jq --arg id "$id" --arg m "$mode" --arg c "$curve" --argjson s "$speed" '.fans[$id] = {mode:$m,curve:$c,speed:$s}')"
}
_config_set_master() {
    _config_write "$(_config_read | jq --argjson v "$1" '.master = $v')"
}
_config_apply_profile_to_fans() {
    local c
    c=$(_get_default_curve "$1")
    _config_write "$(_config_read | jq --arg c "$c" --arg p "$1" '(.profile=$p) | (.fans |= with_entries(.value.curve=$c | .value.mode="curve"))')"
}

_get_default_curve() {
    case "${1:-balanced}" in
        quiet)        echo "30:20,50:40,70:60,85:80" ;;
        balanced)     echo "30:30,50:50,70:75,85:100" ;;
        performance)  echo "30:40,50:70,70:90,85:100" ;;
        *)            echo "30:30,50:50,70:75,85:100" ;;
    esac
}

_parse_curve() {
    local curve="$1" target_temp="$2"
    local prev_pct=30 prev_temp=0 temp pct range pct_range delta result
    [[ -z $curve ]] && echo "30" && return
    IFS=',' read -ra points <<< "$curve"
    for point in "${points[@]}"; do
        temp="${point%%:*}"; pct="${point#*:}"
        if [[ $target_temp -ge $temp ]]; then
            prev_pct="$pct"; prev_temp="$temp"
        else
            [[ $target_temp -le $prev_temp ]] && echo "$prev_pct" && return
            range=$((temp - prev_temp))
            [[ $range -eq 0 ]] && echo "$prev_pct" && return
            pct_range=$((pct - prev_pct))
            delta=$((target_temp - prev_temp))
            result=$((prev_pct + (pct_range * delta) / range))
            [[ $result -gt 100 ]] && result=100
            [[ $result -lt 0 ]] && result=0
            echo "$result"; return
        fi
    done
    echo "$prev_pct"
}

_get_cpu_temp() {
    local max=0 hw hw_name f val
    for hw in $(_hwmon_dirs); do
        hw_name=$(cat "$hw/name" 2>/dev/null || echo "")
        case "$hw_name" in
            coretemp|k10temp|zenpower|it87*|nct*)
                for f in "$hw"/temp*_input; do
                    [[ -f $f ]] || continue
                    val=$(cat "$f" 2>/dev/null || echo "0")
                    val=$((val / 1000))
                    [[ $val -gt $max ]] && max=$val
                done ;;
        esac
    done
    if [[ $max -eq 0 ]]; then
        for f in /sys/class/hwmon/hwmon*/temp*_input; do
            [[ -f $f ]] || continue
            val=$(cat "$f" 2>/dev/null || echo "0"); val=$((val / 1000))
            [[ $val -gt $max ]] && max=$val
        done
    fi
    echo "$max"
}

_sysfs_fans() {
    local hw hw_name fi f rpm label pf pv pct temp tval w
    for hw in $(_hwmon_dirs); do
        hw_name=$(cat "$hw/name" 2>/dev/null || echo "")
        for f in "$hw"/fan*_input; do
            [[ -f $f ]] || continue
            fi=$(echo "$f" | grep -oP 'fan\K[0-9]+')
            rpm=$(cat "$f" 2>/dev/null || echo "0")
            label=$(cat "$hw/fan${fi}_label" 2>/dev/null || echo "Fan ${fi}")
            pf="$hw/pwm${fi}"; pv=0; pct=0
            if [[ -f $pf ]]; then
                pv=$(cat "$pf" 2>/dev/null || echo "0")
                pct=$(_pwm_to_pct "$pv")
            fi
            [[ $pct -eq 0 && $rpm -gt 0 ]] && { pct=$(( (rpm*100+2500)/5000 )); [[ $pct -gt 100 ]] && pct=100; }
            temp="0C"
            for tf in "$hw"/temp*_input; do
                [[ -f $tf ]] || continue
                tval=$(cat "$tf" 2>/dev/null || echo "0")
                temp="$((tval / 1000))C"; break
            done
            w="no"
            [[ -f "$hw/pwm${fi}_enable" && -w "$hw/pwm${fi}_enable" ]] && w="yes"
            echo "${hw_name}|${label}|${rpm}|${pct}|${temp}|${w}|$(basename "$hw")|${fi}"
        done
    done
}

_sysfs_temps() {
    local hw hw_name f ti tv tl
    for hw in $(_hwmon_dirs); do
        hw_name=$(cat "$hw/name" 2>/dev/null || echo "")
        for f in "$hw"/temp*_input; do
            [[ -f $f ]] || continue
            ti=$(echo "$f" | grep -oP 'temp\K[0-9]+')
            tv=$(cat "$f" 2>/dev/null || echo "0")
            tl=$(cat "$hw/temp${ti}_label" 2>/dev/null || echo "Temp ${ti}")
            echo "${hw_name}|${tl}|$((tv / 1000))C"
        done
    done
}

_sysfs_set_speed() {
    local fid="$1" pct="$2"
    local hn fn hw pf pv ef
    hn=$(echo "$fid" | grep -oP 'hwmon\K[0-9]+')
    fn=$(echo "$fid" | grep -oP 'fan\K[0-9]+$')
    [[ -z $hn || -z $fn ]] && return 1
    hw="/sys/class/hwmon/hwmon${hn}"; [[ ! -d $hw ]] && return 1
    pf="${hw}/pwm${fn}"; ef="${hw}/pwm${fn}_enable"
    [[ -f $pf ]] || return 1
    pv=$(_pct_to_pwm "$pct")
    echo 1 > "$ef" 2>/dev/null; echo "$pv" > "$pf" 2>/dev/null
}

_sysfs_set_auto() {
    local fid="$1" hn fn ef
    hn=$(echo "$fid" | grep -oP 'hwmon\K[0-9]+')
    fn=$(echo "$fid" | grep -oP 'fan\K[0-9]+$')
    [[ -z $hn || -z $fn ]] && return 1
    ef="/sys/class/hwmon/hwmon${hn}/pwm${fn}_enable"
    [[ -f $ef ]] || return 1
    echo 2 > "$ef" 2>/dev/null
}

_sysfs_reset_all() { local hw f; for hw in $(_hwmon_dirs); do for f in "$hw"/pwm*_enable; do [[ -f $f ]] && echo 2 > "$f" 2>/dev/null; done; done; }

_has_writable_pwm() { local hw f; for hw in $(_hwmon_dirs); do for f in "$hw"/pwm*_enable; do [[ -w $f ]] && return 0; done; done; return 1; }

_detect_engine() {
    if _has_liquidctl; then
        local d; d=$(liquidctl list 2>/dev/null | grep -oP 'Device #\d+' || true)
        [[ -n $d ]] && { echo "liquidctl"; return; }
    fi
    _has_writable_pwm && { echo "sysfs"; return; }
    _has_acpi_platform_profile && { echo "acpi_platform"; return; }
    echo "sysfs"
}

_acpi_get_choices() { cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null || echo ""; }
_acpi_set_profile() {
    [[ ! -w /sys/firmware/acpi/platform_profile ]] && return 1
    echo "$1" > /sys/firmware/acpi/platform_profile 2>/dev/null
}

_output_json() {
    local engine cpu_temp master profile pwm_avail acpi_choices acpi_current
    engine=$(_detect_engine)
    cpu_temp=$(_get_cpu_temp)
    master=$(echo "$(_config_read)" | jq -r '.master')
    profile=$(echo "$(_config_read)" | jq -r '.profile // "balanced"')
    pwm_avail="false"; _has_writable_pwm && pwm_avail="true"
    acpi_choices=""; acpi_current=""
    _has_acpi_platform_profile && { acpi_choices=$(_acpi_get_choices); acpi_current=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo ""); }

    local fans_json="[]"
    local fans_data; fans_data=$(_sysfs_fans)
    if [[ -n $fans_data ]]; then
        local tmpf; tmpf=$(mktemp)
        while IFS='|' read -r hw_name label rpm pct temp writable hw_id fan_idx; do
            [[ -z $hw_name ]] && continue
            local fid="${hw_id}_${hw_name}_fan${fan_idx}"
            local cfg_mode="auto" cfg_curve="" cfg_speed=100
            local fc; fc=$(echo "$(_config_read)" | jq -r ".fans[\"$fid\"] // empty")
            if [[ -n $fc ]]; then
                cfg_mode=$(echo "$fc" | jq -r '.mode // "auto"')
                cfg_curve=$(echo "$fc" | jq -r '.curve // ""')
                cfg_speed=$(echo "$fc" | jq -r '.speed // 100')
            fi
            jq -n --arg id "$fid" --arg label "$label" --arg hw "$hw_name" \
                --arg hid "$hw_id" --argjson fi "$fan_idx" --argjson rpm "$rpm" \
                --argjson pct "$pct" --arg temp "$temp" --arg w "$writable" \
                --arg mode "$cfg_mode" --arg curve "$cfg_curve" --argjson speed "$cfg_speed" \
                '{id:$id,label:$label,hwmon:$hw,hw_id:$hid,fan_idx:$fi,rpm:$rpm,pct:$pct,temp:$temp,writable:$w,mode:$mode,curve:$curve,speed:$speed}'
        done <<< "$fans_data" > "$tmpf"
        fans_json=$(jq -s '.' "$tmpf")
        rm -f "$tmpf"
    fi

    local temps_json="[]"
    local temps_data; temps_data=$(_sysfs_temps)
    if [[ -n $temps_data ]]; then
        local tmpf; tmpf=$(mktemp)
        while IFS='|' read -r hw_name label temp; do
            [[ -z $hw_name ]] && continue
            jq -n --arg hw "$hw_name" --arg label "$label" --arg temp "$temp" \
                '{hwmon:$hw,label:$label,temp:$temp}'
        done <<< "$temps_data" > "$tmpf"
        temps_json=$(jq -s '.' "$tmpf")
        rm -f "$tmpf"
    fi

    jq -n --arg engine "$engine" --argjson cpu_temp "$cpu_temp" --argjson master "$master" \
        --arg profile "$profile" --argjson fans "$fans_json" --argjson temps "$temps_json" \
        --argjson pwm "$pwm_avail" --arg acpi_choices "$acpi_choices" --arg acpi_current "$acpi_current" \
        '{engine:$engine,cpu_temp:$cpu_temp,master:$master,profile:$profile,fans:$fans,temps:$temps,writable_pwm:$pwm,acpi_choices:$acpi_choices,acpi_current:$acpi_current}'
}

case "$1" in
    "--json") _output_json ;;
    "--detect")
        engine=$(_detect_engine); echo "engine=${engine}"
        case "$engine" in
            liquidctl)  echo "devices=$(_get_liquidctl_devices | tr '\n' ',' | sed 's/,$//')" ;;
            acpi_platform) echo "devices=ACPI platform profile ($(_acpi_get_choices))" ;;
            *)  n=0; for hw in $(_hwmon_dirs); do for f in "$hw"/pwm*_enable; do [[ -f $f ]] && n=$((n+1)); done; done; echo "devices=${n} PWM controls" ;;
        esac ;;
    "--scan-engines")
        _has_liquidctl && echo "liquidctl"
        echo "sysfs"
        _has_acpi_platform_profile && echo "acpi_platform" ;;
    "--status")
        engine=$(_detect_engine); cpu_temp=$(_get_cpu_temp)
        profile=$(echo "$(_config_read)" | jq -r '.profile // "balanced"')
        master=$(echo "$(_config_read)" | jq -r '.master')
        echo "engine:${engine}"; echo "cpu_temp:${cpu_temp}C"; echo "profile:${profile}"; echo "master:${master}"
        while IFS='|' read -r hw_name label rpm pct temp writable hw_id fan_idx; do
            [[ -z $hw_name ]] && continue
            echo "fan_${hw_id}_fan${fan_idx}:${label}:${rpm}rpm (${pct}%) [${temp}]"
        done < <(_sysfs_fans) ;;
    "--list-fans") _sysfs_fans ;;
    "--list-temps") _sysfs_temps ;;
    "--set-master")
        [[ -z $2 ]] && { echo "Usage: --set-master on|off"; exit 1; }
        case "$2" in
            on|true|1)  _config_set_master "true"; set_var "FAN_ENABLED" "true" ;;
            off|false|0) _config_set_master "false"; set_var "FAN_ENABLED" "false"; _sysfs_reset_all ;;
            *) echo "Invalid: use on or off"; exit 1 ;;
        esac; echo "OK|master=$2" ;;
    "--set-mode")
        [[ -z $2 || -z $3 ]] && { echo "Usage: --set-mode <id> auto|curve|manual"; exit 1; }
        case "$3" in auto) _sysfs_set_auto "$2" ;; curve|manual) ;; *) echo "Invalid"; exit 1 ;; esac
        c= c=$(echo "$(_config_read)" | jq -r ".fans[\"$2\"].curve // \"\""); s=$(echo "$(_config_read)" | jq -r ".fans[\"$2\"].speed // 100")
        [[ -z $c ]] && c=$(_get_default_curve "balanced")
        _config_set_fan "$2" "$3" "$c" "$s"; echo "OK|fan=$2|mode=$3" ;;
    "--set-speed")
        [[ -z $2 || -z $3 ]] && { echo "Usage: --set-speed <id> <0-100>"; exit 1; }
        [[ ! $3 =~ ^[0-9]+$ || $3 -lt 0 || $3 -gt 100 ]] && { echo "Speed must be 0-100"; exit 1; }
        _sysfs_set_speed "$2" "$3"; c= c=$(echo "$(_config_read)" | jq -r ".fans[\"$2\"].curve // \"\"")
        [[ -z $c ]] && c=$(_get_default_curve "balanced")
        _config_set_fan "$2" "manual" "$c" "$3"; echo "OK|fan=$2|speed=$3" ;;
    "--set-curve")
        [[ -z $2 || -z $3 ]] && { echo "Usage: --set-curve <id> <curve>"; exit 1; }
        tp=$(_get_cpu_temp); [[ $tp -eq 0 ]] && tp=30
        tpct= tpct=$(_parse_curve "$3" "$tp"); _sysfs_set_speed "$2" "$tpct" 2>/dev/null
        s= s=$(echo "$(_config_read)" | jq -r ".fans[\"$2\"].speed // 100")
        _config_set_fan "$2" "curve" "$3" "$s"; echo "OK|fan=$2|curve=$3|target=$tpct" ;;
    "--set-profile")
        [[ -z $2 ]] && { echo "Usage: --set-profile quiet|balanced|performance"; exit 1; }
        _config_apply_profile_to_fans "$2"; set_var "FAN_PROFILE" "$2"
        if _has_acpi_platform_profile; then
            case "$2" in quiet) _acpi_set_profile "quiet" ;; balanced) _acpi_set_profile "balanced" ;; performance) _acpi_set_profile "performance" ;; esac 2>/dev/null
        fi
        echo "OK|profile=$2" ;;
    "--reset")
        while IFS='|' read -r _ _ _ _ _ _ hw_id fan_idx; do
            [[ -n $hw_id ]] && _sysfs_set_auto "${hw_id}_${hw_name}_fan${fan_idx}" 2>/dev/null
        done < <(_sysfs_fans)
        _sysfs_reset_all 2>/dev/null
        _config_write '{"master":false,"profile":"balanced","fans":{}}'
        set_var "FAN_ENABLED" "false"; set_var "FAN_PROFILE" "balanced"
        echo "OK|reset=true" ;;
    "--daemon-tick")
        master=$(echo "$(_config_read)" | jq -r '.master')
        [[ $master != "true" ]] && exit 0
        cpu_temp=$(_get_cpu_temp); [[ $cpu_temp -eq 0 ]] && exit 0
        profile=$(echo "$(_config_read)" | jq -r '.profile // "balanced"')
        default_curve=$(_get_default_curve "$profile")
        fc=0
        while IFS='|' read -r hw_name label rpm pct temp_val writable hw_id fan_idx; do
            [[ -z $hw_name ]] && continue
            fid="${hw_id}_${hw_name}_fan${fan_idx}"
            fm="auto" fc2="" fs=100
            fdata= fdata=$(echo "$(_config_read)" | jq -r ".fans[\"$fid\"] // empty")
            [[ -n $fdata ]] && { fm=$(echo "$fdata" | jq -r '.mode // "auto"'); fc2=$(echo "$fdata" | jq -r '.curve // ""'); fs=$(echo "$fdata" | jq -r '.speed // 100'); }
            case "$fm" in
                curve)
                    uc="${fc2:-$default_curve}"
                    tgt=$(_parse_curve "$uc" "$cpu_temp")
                    [[ $tgt -gt 100 ]] && tgt=100; [[ $tgt -lt 0 ]] && tgt=0
                    _sysfs_set_speed "$fid" "$tgt" 2>/dev/null; fc=$((fc+1)) ;;
                manual) _sysfs_set_speed "$fid" "$fs" 2>/dev/null; fc=$((fc+1)) ;;
            esac
        done < <(_sysfs_fans)
        echo "${cpu_temp}C: ${fc} fans -> ${profile}" ;;
    "--setup-get")
        echo "engine=$(echo "$(_config_read)" | jq -r '.engine // "auto"')"
        echo "profile=$(echo "$(_config_read)" | jq -r '.profile // "balanced"')" ;;
    "--setup-apply")
        ep="" pp=""
        for arg in "$@"; do case "$arg" in engine=*) ep="${arg#engine=}" ;; profile=*) pp="${arg#profile=}" ;; esac; done
        [[ -z $ep ]] && ep=$(_detect_engine); [[ -z $pp ]] && pp="balanced"
        _config_apply_profile_to_fans "$pp"; set_var "FAN_PROFILE" "$pp"; set_var "FAN_ENABLED" "true"
        n=0; while IFS='|' read -r hw_name _ _ _ _ _ _ _; do [[ -n $hw_name ]] && n=$((n+1)); done < <(_sysfs_fans)
        echo "OK|engine=${ep}|profile=${pp}|fans=${n}" ;;
    "--ensure-sudoers")
        [[ $EUID -ne 0 ]] && { echo "ERR|must be root"; exit 1; }
        cat <<'SEOF' > /etc/sudoers.d/99-retro-fans
%wheel ALL=(ALL) NOPASSWD: /opt/retrolinux/scripts/fans_core.sh
%wheel ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/firmware/acpi/platform_profile
%wheel ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/class/hwmon/hwmon*/pwm*
%wheel ALL=(ALL) NOPASSWD: /usr/bin/tee /sys/class/hwmon/hwmon*/pwm*_enable
SEOF
        chmod 440 /etc/sudoers.d/99-retro-fans
        echo "OK|sudoers=true" ;;
    "--cpu-temp") _get_cpu_temp ;;
    *)          echo "Usage: $0 --{json|detect|status|list-fans|list-temps|set-master|set-mode|set-speed|set-curve|set-profile|reset|cpu-temp|setup-get|setup-apply|scan-engines|ensure-sudoers}"
        exit 1 ;;
esac
