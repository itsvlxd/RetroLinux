#!/bin/bash

cmd_power() {
    local pwr_script="$RETRO_DIR/scripts/power_core.sh"
    local action="$1"
    local val1="$2"
    local val2="$3"
    local val3="$4"

    local vendor=$(bash "$pwr_script" --vendor)
    local model=$(bash "$pwr_script" --model)
    local current=$(bash "$pwr_script" --get)
    local source=$(bash "$pwr_script" --source)

    local INTEL_BLUE="\e[38;5;33m" # Vivid Blue
    local AMD_RED="\e[38;5;196m"   # Bright Red
    local brand_color="$INTEL_BLUE"
    [[ $vendor == "AuthenticAMD" ]] && brand_color="$AMD_RED"

    local src_icon="󱊦"
    [[ $source == "false" ]] && src_icon="󰚥"

    case "$action" in
        "set")
            [[ -z $val1 ]] && rx_log "error" "Please provide a profile: [SAVER|BALANCED|PERFORMANCE]" && return 1
            local profile="${val1,,}"
            [[ ! $profile =~ ^(saver|balanced|performance)$ ]] && rx_log "error" "Invalid profile '${val1}'. Use: saver, balanced, or performance" && return 1
            bash "$pwr_script" --set "$profile" && rx_log "success" "Profile set to: ${PINK}${profile^^}${RESET}" || rx_log "error" "Couldn't set profile."
            ;;

        "tune")
            [[ -z $val3 ]] && rx_log "error" "Usage: --power tune [BAT|AC] [SAVER|BALANCED|PERFORMANCE] [WATTS]" && return 1
            bash "$pwr_script" --tune "$val1" "$val2" "$val3" && rx_log "success" "Updated ${PINK}PWR_${val1^^}_${val2^^}${RESET} to ${val3}W" || rx_log "error" "Couldn't update settings."
            cmd_power "restore"
            ;;

        "toggle")
            rx_log "info" "Switching power profile..."

            local new_mode=$(bash "$pwr_script" --toggle)
            if [[ -n $new_mode ]]; then
                rx_log "success" "Profile is now: ${PINK}${new_mode^^}${RESET}"
            else
                rx_log "error" "Failed to switch profiles."
            fi
            ;;

        "restore")
            local current_mode=$(bash "$pwr_script" --get)
            rx_log "info" "Syncing ${PINK}${current_mode^^}${RESET} limits to hardware..."

            if bash "$pwr_script" --restore; then
                local limit=$(bash "$pwr_script" --get-val "$current_mode")
                rx_log "success" "Hardware refreshed ${GRAY}(${limit}W Max Usage)${RESET}"
            else
                rx_log "error" "Failed to refresh hardware."
            fi
            ;;

        "list")
            local current_pwr=$(bash "$pwr_script" --get)
            local prev_pwr=$(bash "$VAR_SCRIPT" --get "PWR_PREVIOUS")
            local source_mode="AC"

            [[ $(bash "$pwr_script" --source) == "true" ]] && source_mode="BAT"

            : ${prev_pwr:="None"}

            echo -e "\n ${PINK}󱐋 Power Profiles List${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            printf " ${PINK}󱐋 ${RESET} %-24s ${PINK}%s${RESET}\n" "Current Profile:" "${current_pwr^^}"
            printf " ${PINK} ${RESET} %-24s ${GRAY}%s${RESET}\n" "Last Profile:" "${prev_pwr^^}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            bash "$pwr_script" --list | while read -r line; do
                local var=$(echo "$line" | cut -d: -f1)
                local val=$(echo "$line" | cut -d: -f2 | xargs)

                if [[ $var == "PWR_${source_mode}_${current_pwr^^}" ]]; then
                    printf " ${PINK}󰓅 ${RESET} %-24s ${PINK}%sW${RESET}\n" "$var:" "$val"
                else
                    printf " ${PINK}󰓅 ${RESET} %-24s ${GRAY}%sW${RESET}\n" "$var:" "$val"
                fi
            done

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "status")
            local limit=$(bash "$pwr_script" --get-val "$current")

            local mhz_raw=$(awk '/cpu MHz/ {sum+=$4; count++} END {print sum/count}' /proc/cpuinfo)
            local ghz=$(echo "scale=2; $mhz_raw/1000" | bc -l)

            echo -e "\n ${PINK}󰯉 System Power Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            printf " ${PINK}󰍛${RESET} %-14s ${brand_color}%s${RESET}\n" "CPU Model:" "$model"
            printf " ${PINK}󱐌${RESET} %-14s %s GHz\n" "CPU Clock:" "$ghz"
            printf " ${PINK}${src_icon}${RESET} %-14s %s\n" "Power Source:" "$([[ $source == "true" ]] && echo -e "Battery" || echo "Wall/AC")"
            printf " ${PINK}󱐋${RESET} %-14s ${PINK}%s${RESET}\n" "Active Plan:" "${current^^}"
            printf " ${PINK}󱖫${RESET} %-14s %sW\n" "Current Cap:" "$limit"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "optimize")
            rx_log "info" "Scanning CPU hardware..."

            local min_mhz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq 2>/dev/null || echo 0)
            local max_mhz=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 0)

            local min_ghz=$(echo "scale=2; $min_mhz/1000000" | bc -l)
            local max_ghz=$(echo "scale=2; $max_mhz/1000000" | bc -l)

            [[ $min_ghz == .* ]] && min_ghz="0$min_ghz"
            [[ $max_ghz == .* ]] && max_ghz="0$max_ghz"

            local raw_match=$(bash "$pwr_script" --optimize)
            IFS='|' read -r c_name ac_csv bat_csv <<<"$raw_match"
            IFS=',' read -r ac_s ac_b ac_p <<<"$ac_csv"
            IFS=',' read -r bat_s bat_b bat_p <<<"$bat_csv"

            rx_log "info" "Found your cpu: ${brand_color}$model${RESET}"
            rx_log "info" "Speed Range: ${PINK}${min_ghz}${RESET} - ${PINK}${max_ghz}${RESET} GHz"

            if [[ $c_name == *"Generic"* ]]; then
                rx_log "warn" "We don't have power profiles for this CPU yet. Drop us an issue on GitHub and we'll add it!"
            fi

            echo -e ""
            echo -e " ${PINK}󰓅 ${RESET}Suggested settings for ${PINK}$c_name${RESET}:"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"
            printf " ${PINK}󰚥 Plugged In:${RESET}   Saver: ${ac_s}W | Balanced: ${ac_b}W | Perf: ${ac_p}W\n"
            printf " ${PINK}󱊦 On Battery:${RESET}   Saver: ${bat_s}W | Balanced: ${bat_b}W | Perf: ${bat_p}W\n"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────\n"

            echo -ne " ${PINK}󰄾 ${RESET}Apply these power settings? ${PINK}[y/N]${RESET}: "
            read -r allow
            [[ ! $allow =~ ^[Yy]$ ]] && rx_log "info" "Optimization cancelled. Nothing changed." && return 0

            bash "$VAR_SCRIPT" --set "PWR_AC_SAVER" "$ac_s"
            bash "$VAR_SCRIPT" --set "PWR_AC_BALANCED" "$ac_b"
            bash "$VAR_SCRIPT" --set "PWR_AC_PERFORMANCE" "$ac_p"
            bash "$VAR_SCRIPT" --set "PWR_BAT_SAVER" "$bat_s"
            bash "$VAR_SCRIPT" --set "PWR_BAT_BALANCED" "$bat_b"
            bash "$VAR_SCRIPT" --set "PWR_BAT_PERFORMANCE" "$bat_p"

            rx_log "success" "Done! Power limits are now set for ${PINK}$c_name${RESET}."
            bash "$pwr_script" --restore
            ;;

        "permissions")
            rx_log "info" "Configuring kernel modules for early boot..."
            rx_log "info" "Requesting root access to write deep-kernel permissions..."

            if bash "$pwr_script" --permissions; then
                rx_log "success" "Udev rules and Tmpfiles generated successfully."
            else
                rx_log "error" "Failed to generate power permissions."
            fi
            ;;

        *)
            rx_log "info" "Usage: retro power <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "set <profile>" "Set power profile (saver/balanced/perf)"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "tune" "Fine-tune wattage limits per profile"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "toggle" "Cycle through power profiles"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "restore" "Sync current profile to hardware"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List all profile wattage values"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show CPU, clock, and power cap info"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "optimize" "Auto-detect CPU and suggest settings"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "permissions" "Configure kernel power permissions"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "power" "Hardware power management and optimization" "cmd_power"
