#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_fans() {
    local action="${1,,}"
    local subarg="$2"
    local setup_args=("$@")
    shift 2 2>/dev/null || true
    local core="$RETRO_DIR/scripts/fans_core.sh"

    case "$action" in
        "detect")
            local data
            data=$(bash "$core" --detect 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "Failed to detect cooling hardware" && return 1

            local engine devices
            while IFS='=' read -r key val; do
                case "$key" in
                    engine) engine="$val" ;;
                    devices) devices="$val" ;;
                esac
            done <<<"$data"

            local eng_color="$PINK"
            local eng_icon="󱠝"
            case "$engine" in
                liquidctl) eng_icon="󰣆" ;;
                lm-sensors) eng_icon="󰔏" ;;
                acpi_platform) eng_icon="󰏲"; eng_color="$SUCCESS" ;;
                sysfs)
                    eng_icon="󰈐"
                    eng_color="$MUTE"
                    ;;
            esac

            rx_table_header "󰈐" "Cooling Detection"
            rx_table_row "󱠝" "Engine:" "$engine" "$eng_color" "20"
            rx_table_row "󰈐" "Devices:" "$devices" "$PINK" "20"
            rx_table_separator
            rx_table_spacer
            ;;

        "status")
            local data
            data=$(bash "$core" --json 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "Failed to get fan status" && return 1

            local engine cpu_temp master profile
            engine=$(echo "$data" | jq -r '.engine')
            cpu_temp=$(echo "$data" | jq -r '.cpu_temp')
            master=$(echo "$data" | jq -r '.master')
            profile=$(echo "$data" | jq -r '.profile')

            local engine_color="$PINK"
            [[ $engine == "sysfs" ]] && engine_color="$MUTE"
            [[ $engine == "acpi_platform" ]] && engine_color="$SUCCESS"
            [[ -z $engine || $engine == "null" ]] && engine="none" && engine_color="$MUTE"

            local prof_color="$SUCCESS"
            [[ $profile == "performance" ]] && prof_color="$WARN"
            [[ $profile == "quiet" ]] && prof_color="$SUCCESS"
            [[ -z $profile || $profile == "null" ]] && profile="auto" && prof_color="$MUTE"

            local temp_color="$SUCCESS"
            [[ $cpu_temp -gt 50 ]] && temp_color="$WARN"
            [[ $cpu_temp -gt 70 ]] && temp_color="$ERROR"

            local master_str="off"
            [[ $master == "true" ]] && master_str="on"

            rx_table_row "󰔏" "CPU Temp:" "${cpu_temp}°C" "$temp_color" "24"
            rx_table_row "󰈐" "Engine:" "${engine}" "$engine_color" "24"
            rx_table_row "󰥲" "Profile:" "${profile}" "$prof_color" "24"
            rx_table_row "󱠝" "Master:" "${master_str}" "$PINK" "24"
            rx_table_separator

            local fans_json
            fans_json=$(echo "$data" | jq -c '.fans[]')
            while IFS= read -r fan; do
                local flabel=$(echo "$fan" | jq -r '.label')
                local frpm=$(echo "$fan" | jq -r '.rpm')
                local fpct=$(echo "$fan" | jq -r '.pct')
                local ftemp=$(echo "$fan" | jq -r '.temp')
                local fmode=$(echo "$fan" | jq -r '.mode')
                local fw=$(echo "$fan" | jq -r '.writable')
                local w_color="$MUTE"
                [[ $fw == "yes" ]] && w_color="$PINK"
                rx_table_row "󱠝" "${flabel}:" "${frpm}rpm (${fpct}%) [${ftemp}] ${fmode}" "$w_color" "24"
            done <<<"$fans_json"

            rx_table_separator
            rx_table_spacer
            ;;

        "json")
            bash "$core" --json 2>/dev/null
            ;;

        "set")
            local fan="$subarg"
            local pct="$1"
            [[ -z $fan ]] && rx_log "error" "Usage: retro fans set <fan_id> <percentage>" && return 1
            [[ -z $pct ]] && rx_log "error" "Usage: retro fans set <fan_id> <percentage>" && return 1
            [[ ! $pct =~ ^[0-9]+$ ]] && rx_log "error" "Percentage must be a number" && return 1
            [[ $pct -lt 0 || $pct -gt 100 ]] && rx_log "error" "Percentage must be 0-100" && return 1

            local result
            result=$(bash "$core" --set-speed "$fan" "$pct" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "Fan ${PINK}${fan}${RESET} set to ${PINK}${pct}%${RESET}"
            else
                rx_log "error" "Failed to set fan speed. Try: ${PINK}retro fans list${RESET}"
                return 1
            fi
            ;;

        "list-fans" | "list" | "fans")
            local data
            data=$(bash "$core" --list-fans 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "No controllable fans detected" && return 1

            rx_table_header "󱠝" "Detected Fans"
            while IFS='|' read -r hw_name label rpm pct temp writable hw_id fan_idx; do
                local w_color="$MUTE"
                [[ $writable == "yes" ]] && w_color="$PINK"
                rx_table_row "󱠝" "${label}:" "${rpm}rpm (${pct}%)" "$w_color" "24"
            done <<<"$data"
            rx_table_separator
            rx_table_spacer
            ;;

        "list-temps" | "temps")
            local data
            data=$(bash "$core" --list-temps 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "No temperature sensors detected" && return 1

            rx_table_header "󰔏" "Temperature Sensors"
            while IFS='|' read -r hw_name label temp; do
                local t_color="$SUCCESS"
                rx_table_row "󰔏" "${label}:" "$temp" "$t_color" "24"
            done <<<"$data"
            rx_table_separator
            rx_table_spacer
            ;;

        "master")
            local val="${subarg,,}"
            [[ -z $val ]] && rx_log "error" "Usage: retro fans master <on|off>" && return 1
            local result
            result=$(bash "$core" --set-master "$val" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "Fan master control ${PINK}${val}${RESET}"
            else
                rx_log "error" "Failed to set master control"
                return 1
            fi
            ;;

        "profile")
            local profile="$subarg"
            [[ -z $profile ]] && rx_log "error" "Usage: retro fans profile <quiet|balanced|performance>" && return 1
            case "$profile" in
                quiet | balanced | performance) ;;
                *) rx_log "error" "Invalid profile: ${PINK}$profile${RESET}. Use: quiet, balanced, performance" && return 1 ;;
            esac

            local result
            result=$(bash "$core" --set-profile "$profile" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "Fan profile set to ${PINK}${profile}${RESET}"
            else
                rx_log "error" "Failed to apply profile"
                return 1
            fi
            ;;

        "mode")
            local fan="$subarg"
            local mode="$1"
            [[ -z $fan || -z $mode ]] && rx_log "error" "Usage: retro fans mode <fan_id> <auto|curve|manual>" && return 1
            local result
            result=$(bash "$core" --set-mode "$fan" "$mode" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "Fan ${PINK}${fan}${RESET} mode set to ${PINK}${mode}${RESET}"
            else
                rx_log "error" "Failed to set fan mode"
                return 1
            fi
            ;;

        "curve")
            local fan="$subarg"
            local curve="$1"
            [[ -z $fan || -z $curve ]] && rx_log "error" "Usage: retro fans curve <fan_id> <temp:pct,...>" && return 1
            local result
            result=$(bash "$core" --set-curve "$fan" "$curve" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "Fan ${PINK}${fan}${RESET} curve applied"
            else
                rx_log "error" "Failed to set curve"
                return 1
            fi
            ;;

        "reset")
            bash "$core" --reset 2>/dev/null
            rx_log "success" "Fans reset to auto/default mode"
            ;;

        "scan" | "engines")
            local engines
            engines=$(bash "$core" --scan-engines 2>/dev/null)
            [[ -z $engines ]] && rx_log "warn" "No cooling engines detected" && return 0

            rx_table_header "󰈐" "Available Cooling Engines"
            while IFS= read -r eng; do
                local e_color="$PINK"
                local e_icon="󱠝"
                case "$eng" in
                    liquidctl)     e_icon="󰣆"; e_color="$SUCCESS" ;;
                    lm-sensors)    e_icon="󰔏"; e_color="$SUCCESS" ;;
                    acpi_platform) e_icon="󰏲"; e_color="$SUCCESS" ;;
                    sysfs)         e_icon="󰈐"; e_color="$MUTE" ;;
                esac
                rx_table_row "$e_icon" "$eng" "" "$e_color" "18"
            done <<<"$engines"
            rx_table_separator
            rx_table_spacer
            ;;

        "setup")
            rx_setup_parse "${setup_args[@]:1}"
            rx_setup_validate "engine,profile" "engine:in=liquidctl,lm-sensors,sysfs,acpi_platform|profile:in=quiet,balanced,performance" || return 1

            local config_data
            config_data=$(bash "$core" --setup-get 2>/dev/null)
            local cur_engine cur_profile
            while IFS='=' read -r key val; do
                case "$key" in
                    engine) cur_engine="$val" ;;
                    profile) cur_profile="$val" ;;
                esac
            done <<<"$config_data"

            : "${cur_engine:=auto}"
            : "${cur_profile:=balanced}"

            local config_exists=false
            [[ $cur_engine != "auto" ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            local engine_input="$cur_engine"
            local profile_input="$cur_profile"

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                engine_input=$(rx_setup_get_opt "engine" "$cur_engine")
                profile_input=$(rx_setup_get_opt "profile" "$cur_profile")
            else
                if [[ $config_exists == true ]]; then
                    rx_setup_current "󱠝" "Current Cooling Setup" \
                        "Engine" "$cur_engine" \
                        "Profile" "$cur_profile" || true

                    if ! rx_confirm "Reconfigure?" "N"; then
                        rx_log "info" "Setup cancelled."
                        return 0
                    fi
                fi

                local -a avail_engines=()
                local scan_data
                scan_data=$(bash "$core" --scan-engines 2>/dev/null)
                while IFS= read -r eng; do
                    [[ -n $eng ]] && avail_engines+=("$eng")
                done <<<"$scan_data"

                if [[ ${#avail_engines[@]} -eq 0 ]]; then
                    rx_log "error" "No cooling engines detected"
                    return 1
                fi

                local eng_default="$cur_engine"
                [[ $eng_default == "auto" ]] && eng_default="${avail_engines[0]}"
                engine_input=$(rx_input_choice "" "Select Cooling Engine" "$eng_default" "${avail_engines[@]}")

                local -a profiles=("quiet" "balanced" "performance")
                profile_input=$(rx_input_choice "" "Select Fan Profile" "$cur_profile" "${profiles[@]}")
            fi

            rx_setup_summary "󱠝" "Cooling Setup Summary" \
                "Engine" "$engine_input" \
                "Profile" "$profile_input"

            if ! rx_confirm "Apply these settings?" "N"; then
                rx_log "info" "Setup cancelled."
                return 0
            fi

            local result
            result=$(bash "$core" --setup-apply "engine=${engine_input}" "profile=${profile_input}" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                rx_setup_success "󱠝" "Cooling Configured" \
                    "Engine" "$engine_input" \
                    "Profile" "$profile_input"
            else
                rx_log "error" "Failed to apply cooling setup"
                return 1
            fi
            ;;

        "help" | "")
            rx_help_usage "retro fans <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show fan speeds, temps, and cooling status" 40
            rx_help_cmd "detect" "Auto-detect cooling hardware" 40
            rx_help_cmd "setup" "Interactive cooling setup wizard" 40
            rx_help_cmd "list" "List all controllable fans" 40
            rx_help_cmd "temps" "List all temperature sensors" 40
            rx_help_cmd "set <id> <pct>" "Set manual fan speed (0-100%)" 40
            rx_help_cmd "profile <name>" "Apply profile: quiet, balanced, performance" 40
            rx_help_cmd "master <on|off>" "Enable/disable master fan control" 40
            rx_help_cmd "mode <id> <mode>" "Set fan mode: auto, curve, manual" 40
            rx_help_cmd "curve <id> <curve>" "Set custom fan curve (temp:pct,...)" 40
            rx_help_cmd "reset" "Reset fans to auto mode" 40
            rx_help_cmd "engines" "List available cooling engines" 40
            rx_help_cmd "json" "Machine-readable JSON status" 40
            rx_help_examples
            rx_help_example "retro fans status" "Show cooling status" 30
            rx_help_example "retro fans detect" "Auto-detect hardware" 30
            rx_help_example "retro fans profile balanced" "Apply balanced profile" 30
            rx_help_example "retro fans master on" "Enable fan control" 30
            rx_help_example "retro fans set hwmon6_hp_fan1 75" "Set fan to 75%" 30
            rx_help_example "retro fans curve hwmon6_hp_fan1 30:30,50:50,70:75,85:100" "Set curve" 30
            rx_help_spacer
            ;;

        *)
            rx_log "error" "Unknown command: ${PINK}$action${RESET}"
            rx_log "info" "Use ${PINK}retro fans help${RESET} to see available commands."
            return 1
            ;;
    esac
}

register_command "TOOLS" "fans" "Fan and cooling management (liquidctl, sysfs, ACPI)" "cmd_fans"
