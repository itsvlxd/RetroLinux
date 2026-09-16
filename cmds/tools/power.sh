#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/setup.sh"

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
            local prev_pwr=$(get_var "PWR_PREVIOUS")
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

            set_var "PWR_AC_SAVER" "$ac_s"
            set_var "PWR_AC_BALANCED" "$ac_b"
            set_var "PWR_AC_PERFORMANCE" "$ac_p"
            set_var "PWR_BAT_SAVER" "$bat_s"
            set_var "PWR_BAT_BALANCED" "$bat_b"
            set_var "PWR_BAT_PERFORMANCE" "$bat_p"

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

        "setup")
            rx_setup_parse "$@"
            rx_setup_validate "ac_saver,ac_balanced,ac_performance,bat_saver,bat_balanced,bat_performance,profile" "ac_saver:numeric|ac_balanced:numeric|ac_performance:numeric|bat_saver:numeric|bat_balanced:numeric|bat_performance:numeric|profile" || return 1

            config_data=$(bash "$pwr_script" --setup-get 2>/dev/null)
            while IFS='=' read -r key val; do
                case "$key" in
                    cpu_model) cu_cpu="$val" ;;
                    ac_saver) cu_as="$val" ;;
                    ac_balanced) cu_ab="$val" ;;
                    ac_performance) cu_ap="$val" ;;
                    bat_saver) cu_bs="$val" ;;
                    bat_balanced) cu_bb="$val" ;;
                    bat_performance) cu_bp="$val" ;;
                esac
            done <<<"$config_data"

            config_exists=true
            [[ -z $cu_as || $cu_as == "null" ]] && config_exists=false

            rx_setup_check_needed "$config_exists" && return 0

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                fw_ac_s=$(rx_setup_get_opt "ac_saver" "")
                fw_ac_b=$(rx_setup_get_opt "ac_balanced" "")
                fw_ac_p=$(rx_setup_get_opt "ac_performance" "")
                fw_bat_s=$(rx_setup_get_opt "bat_saver" "")
                fw_bat_b=$(rx_setup_get_opt "bat_balanced" "")
                fw_bat_p=$(rx_setup_get_opt "bat_performance" "")
                fw_profile=$(rx_setup_get_opt "profile" "")

                if [[ -n $fw_ac_s && -n $fw_ac_b && -n $fw_ac_p && -n $fw_bat_s && -n $fw_bat_b && -n $fw_bat_p ]]; then
                    result=$(bash "$pwr_script" --setup-apply "$fw_ac_s" "$fw_ac_b" "$fw_ac_p" "$fw_bat_s" "$fw_bat_b" "$fw_bat_p" 2>/dev/null)
                else
                    result=$(bash "$pwr_script" --setup-apply 2>/dev/null)
                fi

                if echo "$result" | grep -q "^OK|"; then
                    ok_line=$(echo "$result" | grep "^OK|")
                    s_cpu=$(echo "$ok_line" | sed -n 's/.*cpu_model=\([^|]*\).*/\1/p')
                    s_ac=$(echo "$ok_line" | sed -n 's/.*ac_saver=\([^|]*\).*/\1/p')"W / "$(echo "$ok_line" | sed -n 's/.*ac_balanced=\([^|]*\).*/\1/p')"W / "$(echo "$ok_line" | sed -n 's/.*ac_performance=\([^|]*\).*/\1/p')"W"
                    s_bat=$(echo "$ok_line" | sed -n 's/.*bat_saver=\([^|]*\).*/\1/p')"W / "$(echo "$ok_line" | sed -n 's/.*bat_balanced=\([^|]*\).*/\1/p')"W / "$(echo "$ok_line" | sed -n 's/.*bat_performance=\([^|]*\).*/\1/p')"W"
                    rx_setup_success "󰐋" "Power Configured" \
                        "CPU" "$s_cpu" \
                        "AC Limits" "$s_ac" \
                        "BAT Limits" "$s_bat"
                else
                    rx_log "error" "Failed to apply power config"
                    return 1
                fi
            else
                if [[ $config_exists == true ]]; then
                    rx_setup_prompt_reconfigure "󰐋" "Current Power Configuration" \
                        "CPU" "${cu_cpu:-unknown}" \
                        "AC Limits" "${cu_as}W / ${cu_ab}W / ${cu_ap}W" \
                        "BAT Limits" "${cu_bs}W / ${cu_bb}W / ${cu_bp}W" || return 0
                fi

                cpu_name=$(bash "$pwr_script" --cpu-name 2>/dev/null)
                match=$(bash "$pwr_script" --optimize 2>/dev/null)
                IFS='|' read -r _ ac_csv bat_csv <<<"$match"
                IFS=',' read -r sg_ac sg_bal sg_perf <<<"$ac_csv"
                IFS=',' read -r sg_bats sg_batb sg_batp <<<"$bat_csv"

                rx_log "info" "Detected CPU: ${PINK}${cpu_name}${RESET}"

                if rx_confirm "Use these optimized presets for your CPU?" "Y"; then
                    use_ac_s="$sg_ac"; use_ac_b="$sg_bal"; use_ac_p="$sg_perf"
                    use_bat_s="$sg_bats"; use_bat_b="$sg_batb"; use_bat_p="$sg_batp"
                else
                    rx_log "info" "Configure custom wattage limits:"
                    use_ac_s=$(rx_input_numeric "AC Saver (W)" "$sg_ac" 1 250)
                    use_ac_b=$(rx_input_numeric "AC Balanced (W)" "$sg_bal" 1 250)
                    use_ac_p=$(rx_input_numeric "AC Performance (W)" "$sg_perf" 1 250)
                    use_bat_s=$(rx_input_numeric "BAT Saver (W)" "$sg_bats" 1 250)
                    use_bat_b=$(rx_input_numeric "BAT Balanced (W)" "$sg_batb" 1 250)
                    use_bat_p=$(rx_input_numeric "BAT Performance (W)" "$sg_batp" 1 250)
                fi

                rx_setup_summary "󰐋" "Power Setup Summary" \
                    "CPU" "$cpu_name" \
                    "AC Limits" "${use_ac_s}W / ${use_ac_b}W / ${use_ac_p}W" \
                    "BAT Limits" "${use_bat_s}W / ${use_bat_b}W / ${use_bat_p}W"

                rx_setup_confirm || return 0

                rx_log "info" "Applying power optimizations..."
                result=$(bash "$pwr_script" --setup-apply "$use_ac_s" "$use_ac_b" "$use_ac_p" "$use_bat_s" "$use_bat_b" "$use_bat_p" 2>/dev/null)

                if echo "$result" | grep -q "^OK|"; then
                    ok_line=$(echo "$result" | grep "^OK|")
                    s_cpu=$(echo "$ok_line" | sed -n 's/.*cpu_model=\([^|]*\).*/\1/p')
                    s_ac=$(echo "$ok_line" | sed -n 's/.*ac_saver=\([^|]*\).*/\1/p')"W / "$(echo "$ok_line" | sed -n 's/.*ac_balanced=\([^|]*\).*/\1/p')"W / "$(echo "$ok_line" | sed -n 's/.*ac_performance=\([^|]*\).*/\1/p')"W"
                    s_bat=$(echo "$ok_line" | sed -n 's/.*bat_saver=\([^|]*\).*/\1/p')"W / "$(echo "$ok_line" | sed -n 's/.*bat_balanced=\([^|]*\).*/\1/p')"W / "$(echo "$ok_line" | sed -n 's/.*bat_performance=\([^|]*\).*/\1/p')"W"
                    rx_setup_success "󰐋" "Power Configured" \
                        "CPU" "$s_cpu" \
                        "AC Limits" "$s_ac" \
                        "BAT Limits" "$s_bat"
                else
                    rx_log "error" "Failed to apply power config"
                    return 1
                fi
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
            rx_help_cmd "setup" "Run power optimization wizard"
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
