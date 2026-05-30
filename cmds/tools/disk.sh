#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_disk() {
    local action="${1,,}"
    local subarg="$2"
    local setup_args=("$@")
    shift 2 2>/dev/null || true
    local core="$RETRO_DIR/scripts/disk_core.sh"

    case "$action" in
        "status")
            _render_bar() {
                local pct="${1%-}"
                [[ -z $pct || $pct == "N/A" || $pct == "?" ]] && pct=0
                local filled=$(( pct / 5 ))
                [[ $filled -gt 20 ]] && filled=20
                local empty=$(( 20 - filled ))
                [[ $empty -lt 0 ]] && empty=0
                local bar=""
                for ((i=0; i<filled; i++)); do bar="${bar}█"; done
                for ((i=0; i<empty; i++)); do bar="${bar}░"; done
                echo "$bar"
            }

            local line
            local -a all_devs=()
            local -a primary=() removable=()
            while IFS='|' read -r dev type model size used health temp mounts wear; do
                [[ -z $dev ]] && continue
                [[ $used == "?" || -z $used ]] && used="0%"
                all_devs+=("${dev}|${type}|${model}|${size}|${used}|${health}|${temp}|${mounts}|${wear}")
                if [[ $dev == nvme* ]]; then
                    primary+=("${dev}|${type}|${model}|${size}|${used}|${health}|${temp}|${mounts}|${wear}")
                else
                    removable+=("${dev}|${type}|${model}|${size}|${used}|${health}|${temp}|${mounts}|${wear}")
                fi
            done < <(bash "$core" --status 2>/dev/null)
            [[ ${#all_devs[@]} -eq 0 ]] && rx_log "error" "No disk data" && return 1

            rx_table_header "󰦝" "Storage Status"

            _render_pool() {
                local icon="$1" title="$2" color="$3"
                shift 3
                local -a devices=("$@")
                [[ ${#devices[@]} -eq 0 ]] && return

                local total_gb=0
                local dev_entry rest sz num unit int_part
                for dev_entry in "${devices[@]}"; do
                    rest="${dev_entry}"
                    for ((idx=0; idx<3; idx++)); do rest="${rest#*|}"; done
                    sz="${rest%%|*}"
                    num="${sz%[A-Z]}"
                    unit="${sz: -1}"
                    int_part="${num%.*}"
                    [[ -z $int_part ]] && int_part=0
                    case "$unit" in
                        T) total_gb=$((total_gb + int_part * 1024)) ;;
                        G) total_gb=$((total_gb + int_part)) ;;
                    esac
                done

                local total=${#devices[@]}

                local cap_str
                if [[ $total_gb -ge 1024 ]]; then
                    local tb=$((total_gb / 1024))
                    local rem=$((total_gb % 1024 * 10 / 1024))
                    cap_str="${tb}.${rem} TB"
                else
                    cap_str="${total_gb} GB"
                fi
                rx_table_row "$icon" "Drives:" "$title" "$color" "20"
                echo "  ${MUTE}Aggregate Capacity: ${cap_str}  │  State: Nominal${RESET}"
                rx_table_separator

                local d t m s u h tp mo w badge badge_color temp_msg temp_color wear_suffix used_num bar_str
                for dev_entry in "${devices[@]}"; do
                    d="${dev_entry%%|*}"
                    rest="${dev_entry#*|}"
                    t="${rest%%|*}"
                    rest="${rest#*|}"
                    m="${rest%%|*}"
                    rest="${rest#*|}"
                    s="${rest%%|*}"
                    rest="${rest#*|}"
                    u="${rest%%|*}"
                    rest="${rest#*|}"
                    h="${rest%%|*}"
                    rest="${rest#*|}"
                    tp="${rest%%|*}"
                    rest="${rest#*|}"
                    mo="${rest%%|*}"
                    rest="${rest#*|}"
                    w="${rest%%|*}"

                    badge="●"
                    badge_color="$SUCCESS"
                    case "$h" in
                        PASSED|OK) badge="●"; badge_color="$SUCCESS" ;;
                        FAILED|CRITICAL) badge="✖"; badge_color="$ERROR" ;;
                        *) badge="󰜥"; badge_color="$GRAY" ;;
                    esac

                    temp_msg="${tp}°C"
                    temp_color="$SUCCESS"
                    if [[ $tp =~ ^[0-9]+$ ]]; then
                        if [[ $tp -gt 70 ]]; then
                            temp_color="$ERROR"
                            temp_msg="${tp}°C [Critical Threshold]"
                        elif [[ $tp -gt 50 ]]; then
                            temp_color="$WARN"
                            temp_msg="${tp}°C [Elevated Operating Point]"
                        else
                            temp_msg="${tp}°C [Optimal Window]"
                        fi
                    else
                        temp_msg="-- (No Active Probe Data)"
                        temp_color="$GRAY"
                    fi

                    wear_suffix=""
                    [[ -n $w && $w != "N/A" ]] && wear_suffix=" (${w} Wear Life Remaining)"

                    used_num="${u%\%}"
                    bar_str=$(_render_bar "$used_num")

                    rx_table_row "󰋊" "Device Node:" "/dev/${d} (${t})" "$RESET" "14"
                    rx_table_row "󰈔" "Model:" "${m} (${s})" "$GRAY" "14"
                    rx_table_row "󰒓" "Health:" "${badge} ${h}${wear_suffix}" "$badge_color" "14"
                    rx_table_row "󰔏" "Temp:" "${temp_msg}" "$temp_color" "14"
                    rx_table_row "󱎒" "Used:" "${bar_str} ${u}" "$PINK" "14"
                    rx_table_row "󰉍" "Mounts:" "${mo:-Unmapped}" "$GRAY" "14"
                done
                rx_table_separator
            }

            _render_pool "󰋊" "[Internal]" "$PINK" "${primary[@]}"
            _render_pool "󱊞" "[Removable]" "$GRAY" "${removable[@]}"
            rx_table_spacer
            ;;

        "health")
            local device="$subarg"
            local data
            if [[ -n $device ]]; then
                data=$(bash "$core" --health "$device" 2>/dev/null)
                [[ -z $data ]] && rx_log "error" "No SMART data for ${PINK}/dev/${device}${RESET}" && return 1

                local dev_name status temp
                while IFS='|' read -r key val; do
                    case "$key" in
                        device) dev_name="$val" ;;
                        status) status="$val" ;;
                        temp) temp="$val" ;;
                        *) [[ $key =~ ^[0-9]+$ ]] && attrs+=("${key}|${val}") ;;
                    esac
                done <<<"$(echo "$data" | head -20)"
                local attrs=()
                while IFS='|' read -r id name value; do
                    [[ $id =~ ^[0-9]+$ ]] && attrs+=("${id}=${name}=${value}")
                done <<<"$(echo "$data" | tail -n +4)"

                local status_icon=""
                local status_color="$SUCCESS"
                [[ $status == "FAILED" ]] && status_icon="󰅙" && status_color="$ERROR"
                [[ $status == "UNKNOWN" ]] && status_icon="" && status_color="$MUTE"

                local temp_color="$SUCCESS"
                [[ $temp =~ ^[0-9]+$ ]] && [[ $temp -gt 50 ]] && temp_color="$WARN"
                [[ $temp =~ ^[0-9]+$ ]] && [[ $temp -gt 70 ]] && temp_color="$ERROR"

                rx_table_header "󰒓" "SMART Health — /dev/${dev_name}"
                rx_table_row "$status_icon" "Status:" "$status" "$status_color" "24"
                local temp_disp="${temp}C"
                [[ $temp == "N/A" ]] && temp_disp="N/A"
                rx_table_row "󰔏" "Temp:" "$temp_disp" "$temp_color" "24"
                rx_table_separator

                for attr in "${attrs[@]}"; do
                    local a_id="${attr%%=*}"
                    local rest="${attr#*=}"
                    local a_name="${rest%%=*}"
                    local a_val="${rest#*=}"
                    local a_color="$PINK"
                    [[ $a_name == "Reallocated_Sector_Ct" && $a_val -gt 0 ]] && a_color="$WARN"
                    [[ $a_name == "Current_Pending_Sector" && $a_val -gt 0 ]] && a_color="$ERROR"
                    [[ $a_name == "Temperature_Celsius" ]] && a_val="${a_val}C"
                    rx_table_row "󰈔" "${a_name}:" "$a_val" "$a_color" "24"
                done
            else
                data=$(bash "$core" --health 2>/dev/null)
                [[ -z $data ]] && rx_log "error" "No disk health data" && return 1

                rx_table_header "󰒓" "Disk Health"
                while IFS='|' read -r name size model dtype health temp; do
                    [[ -z $name ]] && continue
                    local h_color="$SUCCESS"
                    local h_icon=""
                    case "$health" in
                        PASSED)
                            h_color="$SUCCESS"
                            h_icon=""
                            ;;
                        FAILED)
                            h_color="$ERROR"
                            h_icon="󰅙"
                            ;;
                        *)
                            h_color="$MUTE"
                            h_icon=""
                            ;;
                    esac
                    local t_color="$SUCCESS"
                    [[ $temp =~ ^[0-9]+$ ]] && [[ $temp -gt 50 ]] && t_color="$WARN"
                    [[ $temp =~ ^[0-9]+$ ]] && [[ $temp -gt 70 ]] && t_color="$ERROR"
                    rx_table_row "󰋊" "/dev/${name}:" "${model:0:25}" "$PINK" "24"
                    local temp_disp="${temp}C"
                    [[ $temp == "N/A" ]] && temp_disp="N/A"
                    rx_table_row "${h_icon}" "  Health:" "${health}  |  ${temp_disp}" "${h_color}" "24"
                done <<<"$data"
            fi
            rx_table_separator
            rx_table_spacer
            ;;

        "list")
            local data
            data=$(bash "$core" --list 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "No disks detected" && return 1

            rx_table_header "󰋊" "Physical Disks"
            while IFS='|' read -r name size model dtype rota; do
                [[ -z $name ]] && continue
                local type_icon="󰋊"
                [[ $rota -eq 0 || $dtype == "nvme" ]] && type_icon="󰖔"
                local rot_label=""
                [[ $rota -eq 1 ]] && rot_label=" (HDD)"
                [[ $dtype == "nvme" ]] && rot_label=" (NVMe)"
                rx_table_row "$type_icon" "/dev/${name}:" "${size} — ${model:0:30}${rot_label}" "$PINK" "24"
            done <<<"$data"
            rx_table_separator
            rx_table_spacer
            ;;

        "mount")
            local dev="$subarg"
            local path="$1"
            [[ -z $dev ]] && rx_log "error" "Usage: retro disk mount <device> [path]" && return 1

            local result
            result=$(bash "$core" --mount "$dev" "$path" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                local mnt=$(echo "$result" | sed 's/OK|mounted=//')
                rx_log "success" "Mounted ${PINK}/dev/${dev}${RESET} at ${PINK}${mnt}${RESET}"
            else
                rx_log "error" "Failed to mount /dev/${dev}"
                return 1
            fi
            ;;

        "umount" | "unmount")
            local path="$subarg"
            [[ -z $path ]] && rx_log "error" "Usage: retro disk umount <path>" && return 1

            if ! rx_confirm "Unmount ${PINK}${path}${RESET}?" "N"; then
                return 0
            fi

            local result
            result=$(bash "$core" --umount "$path" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                rx_log "success" "Unmounted ${PINK}${path}${RESET}"
            elif echo "$result" | grep -q "cannot_umount_system"; then
                rx_log "error" "Cannot unmount system path: ${PINK}${path}${RESET}"
                return 1
            else
                rx_log "error" "Failed to unmount ${PINK}${path}${RESET}"
                return 1
            fi
            ;;

        "btrfs")
            local sub="$subarg"
            local bpath="${1:-/}"

            case "$sub" in
                "list" | "subvolumes" | "")
                    local data
                    data=$(bash "$core" --btrfs-list "$bpath" 2>/dev/null)
                    if echo "$data" | grep -q "not_btrfs"; then
                        rx_log "warn" "${PINK}${bpath}${RESET} is not a BTRFS filesystem"
                        return 0
                    fi
                    [[ -z $data ]] && rx_log "error" "Failed to list BTRFS subvolumes" && return 1

                    rx_table_header "󰋊" "BTRFS Subvolumes — ${bpath}"
                    while IFS='|' read -r id subpath gen level; do
                        [[ -z $id ]] && continue
                        rx_table_row "󰉍" "ID ${id}:" "${subpath}" "$PINK" "24"
                    done <<<"$data"
                    rx_table_separator
                    rx_table_spacer
                    ;;
                "quota")
                    local data
                    data=$(bash "$core" --btrfs-quota "$bpath" 2>/dev/null)
                    if echo "$data" | grep -q "not_btrfs"; then
                        rx_log "warn" "${PINK}${bpath}${RESET} is not a BTRFS filesystem"
                        return 0
                    fi
                    [[ -z $data ]] && rx_log "error" "BTRFS quotas not enabled. Run: ${PINK}sudo btrfs quota enable ${bpath}${RESET}" && return 1

                    rx_table_header "󰋊" "BTRFS Quota — ${bpath}"
                    while IFS='|' read -r id rfer excl; do
                        [[ -z $id ]] && continue
                        rx_table_row "󰈔" "${id}:" "${rfer} | excl: ${excl}" "$PINK" "24"
                    done <<<"$data"
                    rx_table_separator
                    rx_table_spacer
                    ;;
                *)
                    rx_log "error" "Unknown BTRFS action: $sub"
                    rx_log "info" "Use: list, quota"
                    return 1
                    ;;
            esac
            ;;

        "setup")
            rx_setup_parse "${setup_args[@]:1}"
            rx_setup_validate "automount,btrfs_quota" "automount:in=true,false|btrfs_quota:in=true,false" || return 1

            local config_data
            config_data=$(bash "$core" --setup-get 2>/dev/null)
            local cur_auto cur_quota
            while IFS='=' read -r key val; do
                case "$key" in
                    automount) cur_auto="$val" ;;
                    btrfs_quota) cur_quota="$val" ;;
                esac
            done <<<"$config_data"

            : "${cur_auto:=true}"
            : "${cur_quota:=false}"

            local config_exists=false
            [[ $cur_quota == "true" ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            local auto_input="$cur_auto"
            local quota_input="$cur_quota"

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                auto_input=$(rx_setup_get_opt "automount" "$cur_auto")
                quota_input=$(rx_setup_get_opt "btrfs_quota" "$cur_quota")
            else
                if [[ $config_exists == true ]]; then
                    rx_setup_current "󰋊" "Current Disk Setup" \
                        "Automount" "$cur_auto" \
                        "BTRFS Quotas" "$cur_quota" || true

                    if ! rx_confirm "Reconfigure?" "N"; then
                        rx_log "info" "Setup cancelled."
                        return 0
                    fi
                fi

                local -a bools=("true" "false")
                if rx_confirm "Enable automount for external drives?" "$([[ $cur_auto == "true" ]] && echo "Y" || echo "N")"; then
                    auto_input="true"
                else
                    auto_input="false"
                fi
                if rx_confirm "Enable BTRFS quota management?" "$([[ $cur_quota == "true" ]] && echo "Y" || echo "N")"; then
                    quota_input="true"
                else
                    quota_input="false"
                fi
            fi

            rx_setup_summary "󰋊" "Disk Setup Summary" \
                "Automount" "$auto_input" \
                "BTRFS Quotas" "$quota_input"

            if ! rx_confirm "Apply these settings?" "N"; then
                rx_log "info" "Setup cancelled."
                return 0
            fi

            local result
            result=$(bash "$core" --setup-apply "automount=${auto_input}" "btrfs_quota=${quota_input}" 2>/dev/null)
            if echo "$result" | grep -q "^OK"; then
                rx_setup_success "󰋊" "Disk Configured" \
                    "Automount" "$auto_input" \
                    "BTRFS Quotas" "$quota_input"
            else
                rx_log "error" "Failed to apply disk setup"
                return 1
            fi
            ;;

        "help" | "")
            rx_help_usage "retro disk <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show disk overview, health, and usage" 42
            rx_help_cmd "health [dev]" "SMART health report (all or specific device)" 42
            rx_help_cmd "list" "List all physical disks" 42
            rx_help_cmd "mount <dev> [path]" "Mount a disk to a path" 42
            rx_help_cmd "umount <path>" "Unmount a mount point" 42
            rx_help_cmd "btrfs list" "List BTRFS subvolumes" 42
            rx_help_cmd "btrfs quota" "Show BTRFS quota usage" 42
            rx_help_cmd "setup" "Configure automount and BTRFS quotas" 42
            rx_help_examples
            rx_help_example "retro disk status" "Overview with health and space" 30
            rx_help_example "retro disk health" "SMART report for all disks" 30
            rx_help_example "retro disk health sda" "SMART details for /dev/sda" 30
            rx_help_example "retro disk mount sdb1" "Mount /dev/sdb1" 30
            rx_help_example "retro disk umount /mnt/data" "Unmount /mnt/data" 30
            rx_help_example "retro disk btrfs list" "List BTRFS subvolumes" 30
            rx_help_example "retro disk setup" "Interactive disk setup" 30
            rx_help_spacer
            ;;

        *)
            rx_log "error" "Unknown command: ${PINK}$action${RESET}"
            rx_log "info" "Use ${PINK}retro disk help${RESET} to see available commands."
            return 1
            ;;
    esac
}

register_command "TOOLS" "disk" "Disk and storage management (SMART, mount, BTRFS)" "cmd_disk"
