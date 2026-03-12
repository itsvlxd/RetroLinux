#!/bin/bash

source "$RETRO_DIR/scripts/lib/battery.sh"
source "$RETRO_DIR/scripts/lib/variable.sh"

CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
BAT_CORE="$RETRO_DIR/scripts/battery_core.sh"

readonly INTEL_DB=(
    "Ultra 9 185H|25,45,95|15,25,45" "Ultra 7 155H|15,28,65|10,18,35" "Ultra 5 125H|12,25,50|8,15,28"
    "Ultra 7 258V|10,17,37|7,12,25" "Ultra 5 226V|8,15,30|5,10,20" "14900HX|45,85,157|25,45,75"
    "14700HX|35,65,135|20,35,65" "14650HX|35,55,115|20,30,55" "13980HX|45,85,157|25,45,75"
    "13900H|25,45,115|15,25,45" "13700H|20,45,115|12,25,45" "13620H|20,35,95|12,20,35"
    "12900HK|30,45,115|18,25,45" "12700H|20,45,115|12,25,45" "12650H|20,35,95|12,20,35"
    "1360P|15,28,64|10,15,28" "1260P|15,28,64|10,15,28" "1355U|10,15,25|7,10,15"
    "1255U|10,15,25|7,10,15" "11800H|25,45,95|15,25,45" "11370H|15,28,50|10,18,28"
    "10875H|25,45,95|15,25,45" "10750H|20,45,75|12,20,35" "14900K|65,125,253|35,65,95"
    "13900K|65,125,253|35,65,95" "12900K|65,125,241|35,65,95" "11900K|65,125,250|35,65,95"
    "10900K|65,125,250|35,65,95" "9900K|65,95,210|35,65,95" "8700K|65,95,140|35,65,95"
)

readonly AMD_DB=(
    "9945HX|45,75,120|25,45,65" "8945HS|25,45,70|15,25,40" "8845HS|20,45,65|12,25,35"
    "8840U|10,18,30|7,12,20" "7945HX|45,75,120|25,45,65" "7940HS|20,54,80|12,28,45"
    "7845HX|35,65,110|20,35,55" "7840HS|15,35,65|10,20,35" "7840U|10,25,30|7,15,22"
    "7735HS|15,35,54|10,20,30" "7640HS|15,35,50|10,18,30" "7540U|10,18,28|7,12,20"
    "6980HX|25,54,80|15,30,45" "6900HX|20,45,65|12,25,35" "6800H|15,35,54|10,20,30"
    "6800U|10,20,28|7,12,18" "5980HX|25,54,80|15,30,45" "5900HX|20,45,65|12,25,35"
    "5800H|15,35,54|10,20,30" "5800U|10,15,25|7,10,15" "4800H|15,35,54|10,20,30"
    "9950X|65,125,200|45,65,95" "9900X|65,105,160|45,65,85" "7950X3D|65,120,162|45,65,85"
    "7900X|65,105,170|45,65,85" "7800X3D|45,65,85|35,45,65" "5800X3D|45,65,105|35,45,65"
    "5950X|65,105,142|45,65,85" "3950X|65,105,142|45,65,85" "3700X|45,65,88|35,45,65"
)

get_pwr_var() {
    local profile="${1^^}"
    local source="AC"
    [[ $(is_on_battery) == "true" ]] && source="BAT"

    local var_name="PWR_${source}_${profile}"
    local val=$(get_var "$var_name")

    if [[ -z $val ]]; then
        case "${source}_${profile}" in
            "BAT_SAVER") val=7 ;;
            "AC_SAVER") val=15 ;;
            "BAT_BALANCED") val=14 ;;
            "AC_BALANCED") val=28 ;;
            "BAT_PERFORMANCE") val=35 ;;
            "AC_PERFORMANCE") val=65 ;;
        esac
    fi
    echo "$val"
}

set_profile() {
    local profile="${1#--}"
    profile="${profile,,}"

    #local current=$(get_var "PWR_CURRENT")
    #if [[ $profile == "$current" ]]; then
    #    return 0
    #fi

    local prev=$(get_var "PWR_CURRENT")
    set_var "PWR_PREVIOUS" "$prev"
    set_var "PWR_CURRENT" "$profile"

    local watts=$(get_pwr_var "$profile")
    local microwatts=$((watts * 1000000))

    if [[ $CPU_VENDOR == "GenuineIntel" ]]; then
        case "$profile" in
            "performance")
                echo "0" >/sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null
                echo "100" >/sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
                for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo "performance" >"$epp" 2>/dev/null; done

                if [[ -d /sys/class/powercap/intel-rapl:0 ]]; then
                    echo "$microwatts" >/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null
                    echo "$microwatts" >/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null
                    echo "27983872" >/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us 2>/dev/null
                fi
                ;;

            "balanced")
                echo "0" >/sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null
                echo "100" >/sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
                for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo "balance_performance" >"$epp" 2>/dev/null; done

                if [[ -d /sys/class/powercap/intel-rapl:0 ]]; then
                    echo "$microwatts" >/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null
                    echo "$((microwatts + 5000000))" >/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null
                    echo "976" >/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us 2>/dev/null
                fi
                ;;

            "saver")
                echo "1" >/sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null
                echo "30" >/sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null
                for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo "power" >"$epp" 2>/dev/null; done

                if [[ -d /sys/class/powercap/intel-rapl:0 ]]; then
                    echo "$microwatts" >/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null
                    echo "$microwatts" >/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw 2>/dev/null
                    echo "976" >/sys/class/powercap/intel-rapl:0/constraint_0_time_window_us 2>/dev/null
                fi

                [[ -d /sys/class/powercap/intel-rapl:1 ]] &&
                    echo "3000000" >/sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw 2>/dev/null

                bash "$BAT_CORE" --saver "true"
                ;;
        esac
        # TODO: Finish the implementation for AMD cpus
    elif [[ $CPU_VENDOR == "AuthenticAMD" ]]; then
        local amd_epp="balance_power"
        [[ $profile == "performance" ]] && amd_epp="performance"
        [[ $profile == "saver" ]] && amd_epp="power"

        for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo "$amd_epp" >"$epp" 2>/dev/null
        done
    fi

    return 0
}

restore_profile() {
    curr=$(get_var "PWR_CURRENT")
    set_profile "$curr"
}

toggle_profile() {
    local curr=$(get_var "PWR_CURRENT")
    local prev=$(get_var "PWR_PREVIOUS")

    if [[ -z $prev || $prev == "$curr" ]]; then
        [[ $curr == "saver" ]] && prev="balanced" || prev="saver"
    fi

    set_profile "$prev"
}

tune_settings() {
    local source="${1^^}"
    local profile="${2^^}"
    local watts="$3"

    if [[ ! $source =~ ^(BAT|AC)$ ]] || [[ ! $profile =~ ^(SAVER|BALANCED|PERFORMANCE)$ ]] || [[ -z $watts ]]; then
        echo "Error: Usage --settings [BAT|AC] [SAVER|BALANCED|PERFORMANCE] [WATTS]" >&2
        return 1
    fi

    local var_name="PWR_${source}_${profile}"

    if set_var "$var_name" "$watts"; then
        local current_pwr=$(get_var "PWR_CURRENT")
        local current_source="AC"
        [[ $(is_on_battery) == "true" ]] && current_source="BAT"

        if [[ $current_pwr == "${profile,,}" && $current_source == "$source" ]]; then
            set_profile "$current_pwr"
        fi
    fi
}

list_settings() {
    local sources=("AC" "BAT")
    local profiles=("SAVER" "BALANCED" "PERFORMANCE")

    for src in "${sources[@]}"; do
        for prf in "${profiles[@]}"; do
            local var_name="PWR_${src}_${prf}"

            local val=$(get_var "$var_name")

            if [[ -z $val ]]; then
                case "${src}_${prf}" in
                    "BAT_SAVER") val=7 ;; "AC_SAVER") val=15 ;;
                    "BAT_BALANCED") val=14 ;; "AC_BALANCED") val=28 ;;
                    "BAT_PERFORMANCE") val=35 ;; "AC_PERFORMANCE") val=65 ;;
                esac
            fi

            echo "$var_name: $val"
        done
    done
}

optimize_cpu() {
    local model=$(grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//')
    local target_db=("${INTEL_DB[@]}")
    [[ $CPU_VENDOR == "AuthenticAMD" ]] && target_db=("${AMD_DB[@]}")

    local match=""
    for entry in "${target_db[@]}"; do
        local regex=$(echo "$entry" | cut -d'|' -f1)
        [[ $model == *"$regex"* ]] && match="$entry" && break
    done

    if [[ -z $match ]]; then
        if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
            match="Generic Laptop|15,25,45|10,15,25"
        else
            match="Generic PC|65,95,125|45,65,95"
        fi
    fi

    echo "$match"
}

case "$1" in
    "--set") set_profile "$2" ;;
    "--get") get_var "PWR_CURRENT" ;;
    "--restore") restore_profile ;;
    "--toggle") toggle_profile ;;
    "--tune") tune_settings "$2" "$3" "$4" ;;
    "--list") list_settings ;;
    "--vendor") echo "$CPU_VENDOR" ;;
    "--source") is_on_battery ;;
    "--get-val") get_pwr_var "$2" ;;
    "--optimize") optimize_cpu ;;
    "--model") grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//' ;;
esac
