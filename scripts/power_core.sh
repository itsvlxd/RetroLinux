#!/bin/bash

source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/scripts/battery_core.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "power"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
BAT_CORE="$RETRO_DIR/scripts/battery_core.sh"
RAPL_LOADED_FILE="/tmp/retro_rapl_loaded"

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
    "10300H|15,35,50|10,18,30" "1135G7|12,20,32|8,12,18" "1235U|10,15,25|7,10,15"
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

    local current_ppd=$(powerprofilesctl get 2>/dev/null)
    if [[ -n $current_ppd ]]; then
        local ppd_state="balanced"
        [[ $state == "performance" ]] && ppd_state="performance"
        [[ $state == "saver" ]] && ppd_state="power-saver"
        [[ $current_ppd != "$ppd_state" ]] && powerprofilesctl set "$ppd_state" 2>/dev/null
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

    echo "$cpu_gov" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null 2>&1

    (
        if [[ -w /proc/sys/kernel/nmi_watchdog ]]; then
            echo "$nmi_watchdog" >/proc/sys/kernel/nmi_watchdog 2>/dev/null
        fi

        if [[ -w /proc/sys/vm/dirty_writeback_centisecs ]]; then
            echo "$vm_writeback" >/proc/sys/vm/dirty_writeback_centisecs 2>/dev/null
        fi

        if [[ -f /sys/module/snd_hda_intel/parameters/power_save ]]; then
            echo "$audio_sleep" >/sys/module/snd_hda_intel/parameters/power_save 2>/dev/null
        fi
    ) &

    (
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
    ) &

    wait
}

set_profile() {
    local profile="${1#--}"
    profile="${profile,,}"

    local prev=$(get_var "PWR_CURRENT")
    if [[ $prev != "$profile" ]]; then
        set_var "PWR_PREVIOUS" "$prev"
    fi
    set_var "PWR_CURRENT" "$profile"

    local watts=$(get_pwr_var "$profile")
    local microwatts=$((watts * 1000000))

    sync_hardware_power "$profile"

    if [[ ! -d /sys/class/powercap/intel-rapl:0 && ! -f $RAPL_LOADED_FILE ]]; then
        $SUDO_CMD modprobe intel_rapl_msr 2>/dev/null
        $SUDO_CMD modprobe intel_rapl_common 2>/dev/null
        [[ -d /sys/class/powercap/intel-rapl:0 ]] && touch "$RAPL_LOADED_FILE"
    fi

    if [[ $CPU_VENDOR == "GenuineIntel" ]]; then
        if [[ ! -d /sys/class/powercap/intel-rapl:0 && ! -f $RAPL_LOADED_FILE ]]; then
            $SUDO_CMD modprobe intel_rapl_msr 2>/dev/null
            [[ -d /sys/class/powercap/intel-rapl:0 ]] && touch "$RAPL_LOADED_FILE"
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

                set_var "BAT_SAVER_FORCED" "true"
                set_var "BAT_SAVER_ACTIVE" "true"
                sync_hyprland_power "true"
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
    local curr=$(get_var "PWR_CURRENT")
    set_profile "$curr"
}

restore_previous() {
    local prev=$(get_var "PWR_PREVIOUS")
    if [[ -n $prev && $prev != "null" ]]; then
        set_profile "$prev"
    else
        restore_profile
    fi
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
        if [[ $(has_battery) == "true" ]]; then
            match="Generic Laptop|15,25,45|10,15,25"
        else
            match="Generic PC|65,95,125|45,65,95"
        fi
    fi

    echo "$match"
}

apply_permissions() {
    echo -e "intel_rapl_msr\nintel_rapl_common" | $SUDO_CMD tee /etc/modules-load.d/retro-power.conf >/dev/null

    local udev_rule='SUBSYSTEM=="powercap", ACTION=="add", RUN+="/bin/sh -c \"chmod 666 /sys/class/powercap/intel-rapl:*/constraint_* 2>/dev/null\""'
    echo "$udev_rule" | $SUDO_CMD tee /etc/udev/rules.d/99-retro-power.rules >/dev/null
    $SUDO_CMD udevadm control --reload-rules
    $SUDO_CMD udevadm trigger --subsystem-match=powercap

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
    echo "$expected_content" | $SUDO_CMD tee "$tmp_file" >/dev/null
    $SUDO_CMD systemd-tmpfiles --create "$tmp_file" 2>/dev/null

    $SUDO_CMD modprobe intel_rapl_msr 2>/dev/null
    $SUDO_CMD modprobe intel_rapl_common 2>/dev/null

    if [[ -f /sys/module/snd_hda_intel/parameters/power_save ]]; then
        $SUDO_CMD chmod 666 /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null
    fi

    $SUDO_CMD chmod 666 /sys/class/powercap/intel-rapl:*/constraint_* 2>/dev/null
    $SUDO_CMD chmod 666 /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference 2>/dev/null

    $SUDO_CMD chmod 666 /sys/bus/usb/devices/*/power/control 2>/dev/null
    $SUDO_CMD chmod 666 /sys/class/bluetooth/hci*/device/power/control 2>/dev/null

    return 0
}

case "$1" in
    "--set") set_profile "$2" ;;
    "--get") get_var "PWR_CURRENT" ;;
    "--restore") restore_profile ;;
    "--restore-prev") restore_previous ;;
    "--toggle") toggle_profile ;;
    "--tune") tune_settings "$2" "$3" "$4" ;;
    "--list") list_settings ;;
    "--vendor") echo "$CPU_VENDOR" ;;
    "--source") is_on_battery ;;
    "--get-val") get_pwr_var "$2" ;;
    "--optimize") optimize_cpu ;;
    "--permissions") apply_permissions ;;
    "--model") grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//' ;;
    "--setup-get")
        as=$(get_var "PWR_AC_SAVER" "15")
        ab=$(get_var "PWR_AC_BALANCED" "28")
        ap=$(get_var "PWR_AC_PERFORMANCE" "65")
        bs=$(get_var "PWR_BAT_SAVER" "7")
        bb=$(get_var "PWR_BAT_BALANCED" "14")
        bp=$(get_var "PWR_BAT_PERFORMANCE" "35")
        cpu=$(grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//')
        echo "ac_saver=${as}"
        echo "ac_balanced=${ab}"
        echo "ac_performance=${ap}"
        echo "bat_saver=${bs}"
        echo "bat_balanced=${bb}"
        echo "bat_performance=${bp}"
        echo "cpu_model=${cpu}"
        ;;
    "--setup-apply")
        apply_permissions

        if [[ $# -ge 7 ]]; then
            s_ac="$2"
            s_bal="$3"
            s_perf="$4"
            s_bats="$5"
            s_batb="$6"
            s_batp="$7"
            cpu_name=$(grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//')
        else
            match=$(optimize_cpu)
            IFS='|' read -r cpu_name ac_csv bat_csv <<<"$match"
            IFS=',' read -r s_ac s_bal s_perf <<<"$ac_csv"
            IFS=',' read -r s_bats s_batb s_batp <<<"$bat_csv"
        fi

        set_var "PWR_AC_SAVER" "$s_ac"
        set_var "PWR_AC_BALANCED" "$s_bal"
        set_var "PWR_AC_PERFORMANCE" "$s_perf"
        set_var "PWR_BAT_SAVER" "$s_bats"
        set_var "PWR_BAT_BALANCED" "$s_batb"
        set_var "PWR_BAT_PERFORMANCE" "$s_batp"

        set_profile "balanced"

        echo "OK|configured|cpu_model=${cpu_name}|ac_saver=${s_ac}|ac_balanced=${s_bal}|ac_performance=${s_perf}|bat_saver=${s_bats}|bat_balanced=${s_batb}|bat_performance=${s_batp}"
        rx_log_file "success" "Power configured: ${cpu_name} (${s_ac}/${s_bal}/${s_perf} AC, ${s_bats}/${s_batb}/${s_batp} BAT)"
        ;;
    "--cpu-name")
        grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//'
        ;;
esac
