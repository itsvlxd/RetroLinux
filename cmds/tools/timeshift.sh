#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/menu.sh"
source "$RETRO_DIR/lib/setup.sh"
source "$RETRO_DIR/scripts/timeshift_core.sh"

cmd_timeshift() {
    local ts_script="$RETRO_DIR/scripts/timeshift_core.sh"
    local action="${1,,}"
    shift 2>/dev/null || true

    case "$action" in
        "status")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_log "error" "Timeshift is not installed"
                return 1
            fi

            local config=$(bash "$ts_script" --config)
            if [[ $config == "ERROR"* ]]; then
                rx_table_header "󰕰" "Timeshift Status"
                rx_table_row "󰓅" "State:" "Not configured" "$WARN" "20"
                rx_table_row "󱗼" "Run setup:" "retro timeshift setup" "$GRAY" "20"
                rx_table_separator
                rx_table_spacer
                return 0
            fi

            local disk=$(bash "$ts_script" --disk-usage)
            local snapshots=$(bash "$ts_script" --list 2>/dev/null)
            local snap_count=0
            if [[ $snapshots != "NONE" && $snapshots != "ERROR"* ]]; then
                snap_count=$(echo "$snapshots" | grep -c "^SNAPSHOT|" 2>/dev/null)
            fi

            IFS='|' read -r ckey device uuid parent btrfs daily weekly monthly hourly boot config_snap_count snap_size include_home exclude exclude_apps <<<"$config"
            IFS='|' read -r dkey dev_name total used avail pct <<<"$disk"

            local snap_label="$snap_count"
            [[ -z $snap_count || $snap_count == "0" ]] && snap_label="${snap_count}" || true

            local filters=""
            if [[ -n $exclude && $exclude != "[]" ]]; then
                filters=$(echo "$exclude" | sed 's/\[//; s/\]//' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | tr -d '"' | tr '\n' ',' | sed 's/,$//')
            fi

            rx_table_header "󰕰" "Timeshift Status"
            rx_table_row "󰏗" "State:" "Configured" "$SUCCESS" "20"
            rx_table_row "󰏗" "Device:" "$device" "$PINK" "20"
            rx_table_row "󰏗" "Type:" "$([ "$btrfs" == "true" ] && echo "BTRFS" || echo "RSYNC")" "$PINK" "20"
            rx_table_row "󰕰" "Snapshots:" "$snap_count" "$PINK" "20"
            rx_table_separator
            rx_table_row "󰓅" "Daily:" "$daily" "$PINK" "20"
            rx_table_row "󰓅" "Weekly:" "$weekly" "$PINK" "20"
            rx_table_row "󰓅" "Monthly:" "$monthly" "$PINK" "20"
            rx_table_row "󰓅" "Hourly:" "$hourly" "$PINK" "20"
            rx_table_row "󰀧" "Boot:" "$boot" "$PINK" "20"
            rx_table_separator
            if [[ -n $filters ]]; then
                rx_table_row "󰓅" "Filters:" "$filters" "$PINK" "20"
            fi
            if [[ $dev_name != "none" && -n $total ]]; then
                rx_table_row "󰓅" "Disk:" "$used / $total ($pct)" "$PINK" "20"
            fi
            rx_table_separator
            rx_table_spacer
            ;;

        "list")
            local snapshots=$(bash "$ts_script" --list)

            if [[ $snapshots == "ERROR"* ]]; then
                rx_log "error" "Timeshift is not configured"
                return 1
            fi

            if [[ $snapshots == "NONE" ]]; then
                rx_table_header "󰕰" "Timeshift Snapshots"
                rx_table_simple "󰄪" "No snapshots found" "$PINK"
                rx_table_separator
                rx_table_spacer
                return 0
            fi

            if [[ $snapshots == *"AUTH_REQUIRED"* ]]; then
                local snap_count=$(echo "$snapshots" | grep "^COUNT|" | cut -d'|' -f2)
                rx_table_header "󰕰" "Timeshift Snapshots"
                rx_table_row "󰏗" "Total snapshots:" "$snap_count" "$PINK" "25"
                rx_table_row "󰓅" "Run with sudo to list:" "sudo retro timeshift list" "$GRAY" "25"
                rx_table_separator
                rx_table_spacer
                return 0
            fi

            rx_table_header "󰕰" "Timeshift Snapshots"

            while IFS= read -r line; do
                IFS='|' read -r key date tag comment <<<"$line"
                if [[ $key == "SNAPSHOT" ]]; then
                    local tag_icon="󰕰"
                    [[ $tag == "B" ]] && tag_icon="󰀧"
                    local comment_text=""
                    [[ -n $comment ]] && comment_text=" - $comment"
                    rx_table_simple "$tag_icon" "$date - $tag$comment_text" "$GRAY"
                fi
            done <<<"$snapshots"
            rx_table_separator
            rx_table_spacer
            ;;

        "create")
            local comment="$1"
            local tag="O"

            rx_log "info" "Creating snapshot${comment:+: $comment}..."

            local result=$(bash "$ts_script" --create "$comment" "$tag")

            if [[ $result == *"CREATED"* ]]; then
                rx_log "success" "Snapshot created successfully"
            else
                rx_log "error" "Failed to create snapshot"
            fi
            ;;

        "restore")
            local snapshot="$1"
            [[ -z $snapshot ]] && rx_log "info" "Usage: retro timeshift restore <snapshot-name>" && return 1

            rx_log "warn" "This will restore snapshot: ${PINK}$snapshot${RESET}"
            rx_log "warn" "The system will reboot after restore"
            rx_yesno "Continue?" || {
                rx_log "info" "Aborted."
                return 0
            }

            bash "$ts_script" --restore "$snapshot"
            ;;

        "delete")
            local snapshot="$1"
            [[ -z $snapshot ]] && rx_log "info" "Usage: retro timeshift delete <snapshot-name>" && return 1

            rx_log "warn" "This will delete snapshot: ${PINK}$snapshot${RESET}"
            rx_yesno "Continue?" || {
                rx_log "info" "Aborted."
                return 0
            }

            local result=$(bash "$ts_script" --delete "$snapshot")

            if [[ $result == *"DELETED"* ]]; then
                rx_log "success" "Snapshot deleted"
            else
                rx_log "error" "Failed to delete snapshot"
            fi
            ;;

        "schedule")
            local timeframe="${1,,}"
            local value="${2,,}"

            if [[ -z $timeframe ]]; then
                local config=$(bash "$ts_script" --config 2>/dev/null || echo "ERROR")
                if [[ $config == "ERROR"* ]]; then
                    rx_log "error" "Timeshift is not configured"
                    return 1
                fi

                IFS='|' read -r key device uuid parent btrfs daily weekly monthly hourly boot snap_count snap_size <<<"$config"

                rx_table_header "󰕰" "Backup Schedule"
                rx_table_row "󰓅" "Daily:" "$daily" "$PINK" "20"
                rx_table_row "󰓅" "Weekly:" "$weekly" "$PINK" "20"
                rx_table_row "󰓅" "Monthly:" "$monthly" "$PINK" "20"
                rx_table_row "󰓅" "Hourly:" "$hourly" "$PINK" "20"
                rx_table_row "󰀧" "Boot:" "$boot" "$PINK" "20"
                rx_table_separator
                rx_log "info" "Usage: retro timeshift schedule [daily|weekly|monthly|hourly|boot] [number|disable]"
                echo ""
                return 0
            fi

            [[ -z $value ]] && value="disable"

            local result=$(bash "$ts_script" --schedule "$timeframe" "$value")

            if [[ $result == *"SET"* ]]; then
                IFS='|' read -r status tf count <<<"$result"
                if [[ $count == "0" ]]; then
                    rx_log "success" "${PINK}${tf^}${RESET} backups disabled"
                else
                    rx_log "success" "${PINK}${tf^}${RESET} set to ${PINK}$count${RESET} snapshots"
                fi
            else
                rx_log "error" "Failed to set schedule"
            fi
            ;;

        "setup")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_confirm "Timeshift is not installed. Would you like to install it?" "Y" || {
                    rx_log "info" "Aborted."
                    return 0
                }

                local pkg_helper=$(get_var "PKG_HELPER" "yay")
                if command -v "$pkg_helper" >/dev/null 2>&1; then
                    $pkg_helper -S --needed --noconfirm timeshift 2>&1
                else
                    sudo pacman -S --needed --noconfirm timeshift 2>&1
                fi
                if [[ $? -eq 0 ]]; then
                    rx_log "success" "Timeshift installed successfully"
                else
                    rx_log "error" "Failed to install timeshift"
                    return 1
                fi
            fi

            rx_setup_parse "$@"
            rx_setup_validate "device,btrfs,daily,weekly,monthly,boot,boot_count,exclude_home,filters" "device:required|btrfs:in=true,false|daily:numeric|weekly:numeric|monthly:numeric|boot:in=true,false|boot_count:numeric|exclude_home:in=true,false|filters:" || return 1

            local config=$(bash "$ts_script" --config 2>/dev/null || echo "ERROR")
            local config_exists=false
            [[ $config != "ERROR"* ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            local device_choice=""
            local btrfs_mode="true"
            local daily_count="5"
            local weekly_count="3"
            local monthly_count="2"
            local boot_enabled="true"
            local boot_count="2"
            local exclude_home="false"
            local custom_filters=""

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                device_choice=$(rx_setup_get_opt "device")
                btrfs_mode=$(rx_setup_get_opt "btrfs" "true")
                daily_count=$(rx_setup_get_opt "daily" "5")
                weekly_count=$(rx_setup_get_opt "weekly" "3")
                monthly_count=$(rx_setup_get_opt "monthly" "2")
                boot_enabled=$(rx_setup_get_opt "boot" "true")
                boot_count=$(rx_setup_get_opt "boot_count" "2")
                exclude_home=$(rx_setup_get_opt "exclude_home" "false")
                custom_filters=$(rx_setup_get_opt "filters" "")
                if [[ $custom_filters == "optimized" ]]; then
                    exclude_home="false"
                    custom_filters=""
                fi
            else
                if [[ $config_exists == true ]]; then
                    IFS='|' read -r ckey cur_device cur_uuid cur_parent cur_btrfs cur_daily cur_weekly cur_monthly cur_hourly cur_boot cur_snap_count cur_snap_size cur_include_home cur_exclude cur_exclude_apps <<<"$config"

                    local cur_filters="none"
                    if [[ -n $cur_exclude && $cur_exclude != "[]" ]]; then
                        cur_filters=$(echo "$cur_exclude" | sed 's/\[//; s/\]//' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | tr -d '"' | tr '\n' ',' | sed 's/,$//')
                    fi

                    rx_setup_prompt_reconfigure "󰕰" "Current Timeshift Configuration" \
                        "Device" "$cur_device" \
                        "Type" "$([ "$cur_btrfs" == "true" ] && echo "BTRFS" || echo "RSYNC")" \
                        "Daily" "$cur_daily" \
                        "Weekly" "$cur_weekly" \
                        "Monthly" "$cur_monthly" \
                        "Boot" "$cur_boot" \
                        "Filters" "$cur_filters" || return 0
                fi

                rx_log "info" "Timeshift setup"

                local devices=() device_labels=()
                while IFS= read -r line; do
                    IFS='|' read -r key dev size fstype mount <<<"$line"
                    [[ -z $dev || $key != "DEVICE" ]] && continue
                    devices+=("$dev")
                    device_labels+=("$dev (${size}, ${fstype:-unknown})")
                done < <(bash "$ts_script" --list-devices 2>/dev/null)

                if [[ ${#devices[@]} -eq 0 ]]; then
                    rx_log "error" "No writable devices found"
                    return 1
                fi

                local selected_device=$(rx_menu "󰏗" "Select backup device:" "${device_labels[@]}")
                device_choice="$selected_device"

                local fstype=""
                for i in "${!device_labels[@]}"; do
                    if [[ "${device_labels[$i]}" == "$selected_device" ]]; then
                        fstype=$(bash "$ts_script" --list-devices 2>/dev/null | grep "DEVICE|${devices[$i]}|" | cut -d'|' -f4)
                        break
                    fi
                done

                if [[ $fstype == "btrfs" ]]; then
                    btrfs_mode="true"
                    local type_label="BTRFS (recommended)"
                else
                    btrfs_mode="false"
                    local type_label="RSYNC"
                fi
                rx_log "info" "Backup type: ${PINK}${type_label}${RESET}"

                daily_count=$(rx_input_numeric "Daily snapshots" "5")
                weekly_count=$(rx_input_numeric "Weekly snapshots" "3")
                monthly_count=$(rx_input_numeric "Monthly snapshots" "2")

                if rx_confirm "Enable boot snapshots (before package updates)?" "Y"; then
                    boot_enabled="true"
                    boot_count=$(rx_input_numeric "Boot snapshots to keep" "2")
                else
                    boot_enabled="false"
                fi

                if [[ $btrfs_mode == "true" ]]; then
                    rx_confirm "Exclude /home from backups?" "N" && exclude_home="true" || exclude_home="false"
                fi

                if rx_confirm "Use optimized filters (+ .config, exclude home/root)?" "Y"; then
                    exclude_home="false"
                else
                    rx_log "info" "Tip: '+/pattern' to include, bare pattern to exclude"
                    local custom_filters=$(rx_input "Custom filter patterns (space-separated):")
                    if [[ -n $custom_filters ]]; then
                        exclude_home=""
                    fi
                fi

                local daily_label="$([ $daily_count -gt 0 ] && echo "$daily_count" || echo "off")"
                local weekly_label="$([ $weekly_count -gt 0 ] && echo "$weekly_count" || echo "off")"
                local monthly_label="$([ $monthly_count -gt 0 ] && echo "$monthly_count" || echo "off")"
                local boot_label="$([ $boot_enabled == "true" ] && echo "$boot_count boot snaps" || echo "off")"

                local summary_filters=""
                if [[ -n $custom_filters ]]; then
                    summary_filters="$custom_filters"
                elif [[ $exclude_home == "true" ]]; then
                    summary_filters="/home/*, /root"
                else
                    summary_filters="+ /home/*/.config/**, /home/*, /root"
                fi

                rx_setup_summary "󰕰" "Setup Summary" \
                    "Device" "$device_choice" \
                    "Type" "$([ "$btrfs_mode" == "true" ] && echo "BTRFS" || echo "RSYNC")" \
                    "Daily" "$daily_label" \
                    "Weekly" "$weekly_label" \
                    "Monthly" "$monthly_label" \
                    "Boot" "$boot_label" \
                    "Filters" "$summary_filters"

                rx_setup_confirm || return 0
            fi

            if [[ -z $summary_filters ]]; then
                if [[ -n $custom_filters ]]; then
                    summary_filters="$custom_filters"
                elif [[ $exclude_home == "true" ]]; then
                    summary_filters="/home/*, /root"
                else
                    summary_filters="+ /home/*/.config/**, /home/*, /root"
                fi
            fi

            local setup_args=(
                "device=${device_choice}"
                "btrfs=${btrfs_mode}"
                "daily=${daily_count}"
                "weekly=${weekly_count}"
                "monthly=${monthly_count}"
                "boot=${boot_enabled}"
                "boot_count=${boot_count}"
            )
            if [[ -z $exclude_home && -n $custom_filters ]]; then
                setup_args+=("filters=${custom_filters}")
            else
                setup_args+=("exclude_home=${exclude_home}")
            fi
            local result=$(sudo bash "$ts_script" --apply-setup "${setup_args[@]}" 2>&1)

            if echo "$result" | grep -q "^OK|"; then
                echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/timeshift" | \
                    sudo tee /etc/sudoers.d/timeshift >/dev/null && \
                    sudo chmod 0440 /etc/sudoers.d/timeshift

                rx_setup_success "󱗼" "Timeshift Configured" \
                    "Device" "$device_choice" \
                    "Type" "$([ "$btrfs_mode" == "true" ] && echo "BTRFS" || echo "RSYNC")" \
                    "Daily" "$daily_label" \
                    "Weekly" "$weekly_label" \
                    "Monthly" "$monthly_label" \
                    "Boot" "$boot_label" \
                    "Filters" "$summary_filters"

                { sudo systemctl restart timeshift 2>/dev/null || sudo systemctl restart timeshift.timer 2>/dev/null; } || true
            else
                rx_log "error" "Failed to apply Timeshift configuration: $result"
                return 1
            fi
            ;;

        "gui")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_confirm "Timeshift is not installed. Would you like to install it?" "Y" || {
                    rx_log "info" "Aborted."
                    return 0
                }

                local pkg_helper=$(get_var "PKG_HELPER" "yay")
                if command -v "$pkg_helper" >/dev/null 2>&1; then
                    $pkg_helper -S --needed --noconfirm timeshift 2>&1
                else
                    sudo pacman -S --needed --noconfirm timeshift 2>&1
                fi
                if [[ $? -eq 0 ]]; then
                    rx_log "success" "Timeshift installed successfully"
                else
                    rx_log "error" "Failed to install timeshift"
                    return 1
                fi
            fi

            local result=$(bash "$ts_script" --gui)

            if [[ $result == *"OPENED"* ]]; then
                rx_log "success" "Timeshift GUI opened"
            elif [[ $result == *"ERROR:no_gui"* ]]; then
                rx_log "error" "GUI not available. Install timeshift-gtk for graphical interface"
            else
                rx_log "error" "Failed to open Timeshift GUI"
            fi
            ;;

        *)
            rx_help_usage "retro timeshift <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show backup config and snapshot count" "40"
            rx_help_cmd "list" "List all snapshots" "40"
            rx_help_cmd "create [comment]" "Create a new snapshot" "40"
            rx_help_cmd "restore <snapshot>" "Restore a specific snapshot" "40"
            rx_help_cmd "delete <snapshot>" "Delete a specific snapshot" "40"
            rx_help_cmd "config" "Show current Timeshift configuration" "40"
            rx_help_cmd "schedule [timeframe] [count|disable]" "Show or set snapshot retention schedule" "40"
            rx_help_cmd "setup [-o key=val,...]" "Interactive or scripted setup wizard" "40"
            rx_help_cmd "gui" "Open Timeshift graphical interface" "40"
            rx_help_examples
            rx_help_example "retro timeshift status" "Show current config and snapshot count" "40"
            rx_help_example "retro timeshift list" "List all snapshots" "40"
            rx_help_example "retro timeshift create 'Before update'" "Create a snapshot with comment" "40"
            rx_help_example "retro timeshift schedule daily 5" "Keep 5 daily snapshots" "40"
            rx_help_example "retro timeshift schedule weekly disable" "Turn off weekly backups" "40"
            rx_help_example "retro timeshift setup" "Interactive setup wizard" "40"
            rx_help_example "retro timeshift setup -o device=/dev/sda1,daily=5,weekly=3,monthly=2,boot=true" "Non-interactive setup" "40"
            rx_help_example "retro timeshift gui" "Open GUI for manual management" "40"
            rx_help_spacer
            ;;
    esac
}

if command -v timeshift &>/dev/null; then
    register_command "TOOLS" "timeshift" "Timeshift backup manager — snapshots, scheduling, and setup" "cmd_timeshift"
fi
