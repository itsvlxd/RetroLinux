#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

cmd_power() {
    local pwr_script="$RETRO_DIR/scripts/power_core.sh"
    local action="${1,,}"
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

            rx_table_header "󱐋" "Power Profiles List"
            rx_table_row "󱐋" "Current Profile:" "${current_pwr^^}" "$PINK" "24"
            rx_table_row_gray "" "Last Profile:" "${prev_pwr^^}" "24"
            rx_table_separator

            bash "$pwr_script" --list | while read -r line; do
                local var=$(echo "$line" | cut -d: -f1)
                local val=$(echo "$line" | cut -d: -f2 | xargs)

                if [[ $var == "PWR_${source_mode}_${current_pwr^^}" ]]; then
                    rx_table_row "󰓅" "$var" "${val}W" "$PINK" "24"
                else
                    rx_table_row "󰓅" "$var" "${val}W" "$GRAY" "24"
                fi
            done

            rx_table_separator
            rx_table_spacer
            ;;

        "status")
            local limit=$(bash "$pwr_script" --get-val "$current")

            local mhz_raw=$(awk '/cpu MHz/ {sum+=$4; count++} END {print sum/count}' /proc/cpuinfo)
            local ghz=$(echo "scale=2; $mhz_raw/1000" | bc -l)

            rx_table_header "󰯉" "System Power Status"
            rx_table_row "󰍛" "CPU Model:" "$model" "$brand_color" "14"
            rx_table_row "󱐌" "CPU Clock:" "$ghz GHz" "$PINK" "14"
            rx_table_row "󱊦" "Power Source:" "$([[ $source == "true" ]] && echo "Battery" || echo "Wall/AC")" "$PINK" "14"
            rx_table_row "󱐋" "Active Plan:" "${current^^}" "$PINK" "14"
            rx_table_row "󱖫" "Current Cap:" "$limit W" "$PINK" "14"
            rx_table_separator
            rx_table_spacer
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

            rx_table_spacer
            rx_table_header "󰓅" "Suggested settings for $c_name"
            rx_table_row "󰚥" "Plugged In" "Saver: ${ac_s}W | Balanced: ${ac_b}W | Perf: ${ac_p}W" "$PINK" "24"
            rx_table_row "󱊦" "On Battery" "Saver: ${bat_s}W | Balanced: ${bat_b}W | Perf: ${bat_p}W" "$PINK" "24"
            rx_table_separator
            rx_table_spacer

            rx_yesno "Apply these power settings?" || { rx_log "info" "Optimization cancelled. Nothing changed."; return 0; }

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
            rx_help_usage "retro power <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "set <profile>" "Set power profile (saver/balanced/perf)"
            rx_help_cmd "tune" "Fine-tune wattage limits per profile"
            rx_help_cmd "toggle" "Cycle through power profiles"
            rx_help_cmd "restore" "Sync current profile to hardware"
            rx_help_cmd "list" "List all profile wattage values"
            rx_help_cmd "status" "Show CPU, clock, and power cap info"
            rx_help_cmd "optimize" "Auto-detect CPU and suggest settings"
            rx_help_cmd "permissions" "Configure kernel power permissions"
            rx_help_examples
            rx_help_example "retro power status" "Show power status and info"
            rx_help_example "retro power set balanced" "Set balanced power profile"
            rx_help_example "retro power list" "List all profile limits"
            rx_help_example "retro power optimize" "Auto-detect CPU and optimize"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "power" "Hardware power management and optimization" "cmd_power"
