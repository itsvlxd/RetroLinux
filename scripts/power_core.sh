#!/bin/bash

source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/lib/helpers.sh"

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
    "10300H|15,35,50|10,18,30" "1135G7|12,20,32|8,12,18"
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

sync_hardware_power() {
    local state="$1"

    if command -v powerprofilesctl >/dev/null 2>&1; then
        local ppd_state="balanced"
        [[ $state == "performance" ]] && ppd_state="performance"
        [[ $state == "saver" ]] && ppd_state="power-saver"
        powerprofilesctl set "$ppd_state" 2>/dev/null
    fi

    local wifi_pm="off"
    local bt_pm="on"
    local usb_pm="on"
    local pcie_policy="performance"
    local sata_policy="max_performance"
    local audio_sleep="0"
    local cpu_gov="performance"
    local nmi_watchdog="1"
    local vm_writeback="500"

    if [[ $state == "saver" ]]; then
        wifi_pm="on"
        bt_pm="auto"
        usb_pm="on"
        pcie_policy="powersave"
        sata_policy="min_power"
        audio_sleep="1"
        cpu_gov="powersave"
        nmi_watchdog="0"
        vm_writeback="6000"
    elif [[ $state == "balanced" ]]; then
        wifi_pm="on"
        sata_policy="med_power_with_dipm"
        cpu_gov="powersave"
        vm_writeback="1500"
    fi

    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [[ -f $gov ]] && echo "$cpu_gov" >"$gov" 2>/dev/null
    done

    if [[ -w /proc/sys/kernel/nmi_watchdog ]]; then
        echo "$nmi_watchdog" >/proc/sys/kernel/nmi_watchdog 2>/dev/null
    fi

    if [[ -w /proc/sys/vm/dirty_writeback_centisecs ]]; then
        echo "$vm_writeback" >/proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
    fi

    local wl_iface=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}')
    if [[ -n $wl_iface ]]; then
        iw dev "$wl_iface" set power_save "$wifi_pm" 2>/dev/null
    fi

    for bt in /sys/class/bluetooth/hci*/device/power/control; do
        [[ -f $bt ]] && echo "$bt_pm" >"$bt" 2>/dev/null
    done

    for usb in /sys/bus/usb/devices/*/power/control; do
        [[ -w $usb ]] && echo "$usb_pm" >"$usb" 2>/dev/null
    done

    if [[ -f /sys/module/snd_hda_intel/parameters/power_save ]]; then
        echo "$audio_sleep" >/sys/module/snd_hda_intel/parameters/power_save 2>/dev/null
    fi
}

set_profile() {
    local profile="${1#--}"
    profile="${profile,,}"

    local prev=$(get_var "PWR_CURRENT")
    set_var "PWR_PREVIOUS" "$prev"
    set_var "PWR_CURRENT" "$profile"

    local watts=$(get_pwr_var "$profile")
    local microwatts=$((watts * 1000000))

    sync_hardware_power "$profile"

    if [[ ! -d /sys/class/powercap/intel-rapl:0 ]]; then
        sudo modprobe intel_rapl_msr 2>/dev/null
        sudo modprobe intel_rapl_common 2>/dev/null
    fi

    if [[ $CPU_VENDOR == "GenuineIntel" ]]; then
        if [[ ! -d /sys/class/powercap/intel-rapl:0 ]]; then
            sudo modprobe intel_rapl_msr 2>/dev/null
        fi

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

                if [[ -f /sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw ]]; then
                    echo "$microwatts" >/sys/class/powercap/intel-rapl:1/constraint_0_power_limit_uw 2>/dev/null
                fi

                if [[ -f /sys/class/powercap/intel-rapl:0:1/constraint_0_power_limit_uw ]]; then
                    echo "3000000" >/sys/class/powercap/intel-rapl:0:1/constraint_0_power_limit_uw 2>/dev/null
                fi

                bash "$BAT_CORE" --saver "true"
                ;;
        esac
    elif [[ $CPU_VENDOR == "AuthenticAMD" ]]; then
        local amd_epp="balance_power"
        local amd_boost="1"

        [[ $profile == "performance" ]] && amd_epp="performance"
        if [[ $profile == "saver" ]]; then
            amd_epp="power"
            amd_boost="0"
        fi

        for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo "$amd_epp" >"$epp" 2>/dev/null
        done

        if [[ -f /sys/devices/system/cpu/cpufreq/boost ]]; then
            echo "$amd_boost" >/sys/devices/system/cpu/cpufreq/boost 2>/dev/null
        fi

        if [[ -f /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ]]; then
            echo "$microwatts" >/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null
        fi
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
        case "$curr" in
            "saver") prev="balanced" ;;
            "balanced") prev="performance" ;;
            *) prev="saver" ;;
        esac
    fi

    set_profile "$prev"
}

tune_settings() {
    local source="${1^^}"
    local profile="${2^^}"
    local watts="$3"

    if [[ ! $source =~ ^(BAT|AC)$ ]] || [[ ! $profile =~ ^(SAVER|BALANCED|PERFORMANCE)$ ]] || [[ -z $watts ]]; then
        echo "ERROR:invalid_args|source=$source|profile=$profile|watts=$watts"
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

apply_permissions() {
    echo -e "intel_rapl_msr\nintel_rapl_common" | sudo tee /etc/modules-load.d/retro-power.conf >/dev/null

    local udev_rule='SUBSYSTEM=="powercap", ACTION=="add", RUN+="/bin/sh -c \"chmod 666 /sys/class/powercap/intel-rapl:*/constraint_* 2>/dev/null\""'
    echo "$udev_rule" | sudo tee /etc/udev/rules.d/99-retro-power.rules >/dev/null
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=powercap

    read -r -d '' expected_content <<EOF
# Retro Power Management Permissions
z /sys/devices/system/cpu/intel_pstate/no_turbo                               0666 - - - -
z /sys/devices/system/cpu/intel_pstate/max_perf_pct                           0666 - - - -
z /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference          0666 - - - -
z /sys/class/bluetooth/hci*/device/power/control                              0666 - - - -
z /sys/module/snd_hda_intel/parameters/power_save                             0666 - - - -
z /sys/devices/system/cpu/cpufreq/boost                                       0666 - - - -
z /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor                       0666 - - - -
z /sys/bus/usb/devices/*/power/control                                        0666 - - - -
EOF

    local tmp_file="/etc/tmpfiles.d/retro-power.conf"
    echo "$expected_content" | sudo tee "$tmp_file" >/dev/null
    sudo systemd-tmpfiles --create "$tmp_file" 2>/dev/null

    sudo modprobe intel_rapl_msr 2>/dev/null
    sudo modprobe intel_rapl_common 2>/dev/null

    if [[ -f /sys/module/snd_hda_intel/parameters/power_save ]]; then
        sudo chmod 666 /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null
    fi

    sudo chmod 666 /sys/class/powercap/intel-rapl:*/constraint_* 2>/dev/null
    sudo chmod 666 /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null

    sudo chmod 666 /sys/bus/usb/devices/*/power/control 2>/dev/null
    sudo chmod 666 /sys/class/bluetooth/hci*/device/power/control 2>/dev/null

    return 0
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
    "--permissions") apply_permissions ;;
    "--model") grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//' ;;
esac
